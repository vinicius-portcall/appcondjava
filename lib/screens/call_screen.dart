import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:sip_ua/sip_ua.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/app_button.dart';
import '../services/api_service.dart';
import '../services/session_service.dart';
import '../services/sip_service.dart';

class CallScreen extends StatefulWidget {
  final SipService sip;
  final List<AppButton> botoesDtmf;
  final bool chamadaEntrante;
  final ApiService api;
  final SipAccount conta;

  const CallScreen({
    super.key,
    required this.sip,
    required this.botoesDtmf,
    required this.api,
    required this.conta,
    this.chamadaEntrante = false,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen>
    with SingleTickerProviderStateMixin {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  /// Player da câmera do condomínio acoplada ao interfone. Criado só quando a
  /// chamada de fato tem câmera — abrir um player por chamada, mesmo sem usar,
  /// desperdiçaria memória num aparelho que já está com uma sessão WebRTC
  /// aberta.
  Player? _cameraPlayer;
  VideoController? _cameraController;
  String? _cameraUrlAberta;
  StreamSubscription<String>? _erroCameraSub;
  String? _erroCamera;
  bool _renderersProntos = false;
  final Set<String> _portoesAbrindo = {};
  MediaStream? _remoteStreamAnexado;
  int _remoteVideoTracksAnexado = -1;
  Timer? _pollParticipantes;
  int? _participantes;
  late final AppLifecycleListener _lifecycleListener;

  /// Logo do condomínio, do branding que o painel manda. Lida do cache
  /// (SessionService) e não da rede: a tela de chamada aparece no instante
  /// em que o interfone toca e não pode esperar uma requisição.
  String? _logoUrl;

  /// Quando a conversa começou de fato (CONFIRMED). Nulo enquanto só toca.
  DateTime? _inicioConversa;
  Timer? _tickDuracao;

  /// Pulsa a logo enquanto a chamada está tocando. Para assim que atende —
  /// a animação serve para dizer "está chamando agora", e continuar pulsando
  /// durante a conversa só distrairia.
  late final AnimationController _pulso;

  @override
  void initState() {
    super.initState();
    widget.sip.addListener(_onSipChange);
    // O pop automático (_onSipChange) roda mesmo com o app em segundo
    // plano, mas sem uma Activity/Surface anexada o Flutter não chega a
    // desenhar o frame que aplicaria esse pop — a tela fica "presa" até
    // algo forçar uma nova checagem. Reconferir ao voltar pro primeiro
    // plano cobre exatamente o caso relatado: ligação que termina (do outro
    // lado) com o app fechado/tela apagada.
    _lifecycleListener = AppLifecycleListener(
      onResume: () {
        if (!mounted) return;
        if (!widget.sip.emChamada) {
          Navigator.of(context).maybePop();
        }
      },
    );
    _pulso = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _carregarLogo();
    _sincronizarDuracao();
    _iniciarRenderers();
    final salaId = widget.sip.idSalaConferencia;
    if (salaId != null) {
      _atualizarParticipantes(salaId);
      _pollParticipantes = Timer.periodic(
        const Duration(seconds: 4),
        (_) => _atualizarParticipantes(salaId),
      );
    }
  }

  /// Logo do condomínio dentro de um círculo claro, pulsando enquanto a
  /// chamada toca.
  ///
  /// A logo vem do painel (branding) e cai no ícone do próprio app quando o
  /// condomínio não cadastrou uma — o app é white-label e nem todo cliente
  /// sobe logo. `Image.network` com `errorBuilder` pelo mesmo motivo: URL
  /// quebrada no painel não pode deixar um quadrado vazio no meio da tela de
  /// chamada.
  Widget _marcaDaChamada({required bool tocando}) {
    final url = _logoUrl;
    final Widget imagem = url == null
        ? Image.asset('assets/icon/app_icon.png', fit: BoxFit.cover)
        : Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) =>
                Image.asset('assets/icon/app_icon.png', fit: BoxFit.cover),
          );

    final avatar = Container(
      width: 132,
      height: 132,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 18,
          ),
        ],
      ),
      child: ClipOval(child: Padding(padding: const EdgeInsets.all(14), child: imagem)),
    );

    if (!tocando) return avatar;

    // Dois anéis que crescem e somem, como a onda de um telefone tocando. O
    // avatar em si não muda de tamanho: logo que estica e encolhe fica
    // amadora, e a leitura da marca se perde.
    return AnimatedBuilder(
      animation: _pulso,
      builder: (context, child) {
        return SizedBox(
          width: 200,
          height: 200,
          child: Stack(
            alignment: Alignment.center,
            children: [
              for (final atraso in const [0.0, 0.5])
                _anelDoPulso((_pulso.value + atraso) % 1.0),
              child!,
            ],
          ),
        );
      },
      child: avatar,
    );
  }

  Widget _anelDoPulso(double t) {
    return Container(
      width: 132 + (68 * t),
      height: 132 + (68 * t),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: (1 - t) * 0.45),
          width: 2,
        ),
      ),
    );
  }

  Future<void> _carregarLogo() async {
    try {
      final branding = await SessionService().loadBranding();
      final url = branding?.logoUrl?.trim();
      if (!mounted || url == null || url.isEmpty) return;
      setState(() => _logoUrl = url);
    } catch (_) {
      // Sem logo cai no ícone do próprio app — ver _marcaDaChamada().
    }
  }

  /// Segura a tela acesa enquanto houver vídeo na chamada.
  ///
  /// Numa chamada de vídeo o morador fica olhando a imagem do interfone sem
  /// encostar no aparelho, e o Android apaga a tela em 30 segundos — no meio
  /// da conversa, com a pessoa tentando enxergar quem está na portaria.
  ///
  /// Só com vídeo: numa chamada de áudio a tela apagada é o comportamento
  /// certo (o telefone no ouvido, inclusive, apaga por sensor de
  /// proximidade), e manter acesa à toa gasta bateria.
  Future<void> _sincronizarTelaAcesa(bool manterAcesa) async {
    if (_telaAcesa == manterAcesa) return;
    _telaAcesa = manterAcesa;
    try {
      await WakelockPlus.toggle(enable: manterAcesa);
    } catch (e) {
      debugPrint('[Portcall] wakelock falhou: $e');
    }
  }

  bool _telaAcesa = false;

  /// Liga e desliga o cronômetro conforme a chamada é atendida ou encerrada.
  ///
  /// Chamado do listener do SIP, não do build: o build roda a cada frame da
  /// animação, e criar um Timer ali ligaria um novo a cada pulso.
  void _sincronizarDuracao() {
    // `conversaIniciada`, não `callState == CONFIRMED`: o estado guarda o
    // último evento recebido, e o STREAM chega depois do CONFIRMED e o
    // sobrescreve. Testar o estado atual dava "ainda não atendeu" no meio da
    // conversa — a logo ficava sobre o vídeo e o cronômetro não aparecia.
    final emConversa = widget.sip.conversaIniciada;

    if (emConversa && _inicioConversa == null) {
      _inicioConversa = DateTime.now();
      // Para de pulsar: a animação diz "está chamando", e a chamada já foi
      // atendida.
      _pulso.stop();
      _tickDuracao = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!emConversa && _inicioConversa != null) {
      _inicioConversa = null;
      _tickDuracao?.cancel();
      _tickDuracao = null;
    }
  }

  /// mm:ss, virando h:mm:ss só quando passa de uma hora — chamada de
  /// interfone raramente chega lá, e mostrar "00:" na frente o tempo todo
  /// rouba atenção de um número que a pessoa olha de relance.
  String get _duracaoTexto {
    final inicio = _inicioConversa;
    if (inicio == null) return '';
    final d = DateTime.now().difference(inicio);
    String doisDigitos(int n) => n.toString().padLeft(2, '0');
    final mm = doisDigitos(d.inMinutes.remainder(60));
    final ss = doisDigitos(d.inSeconds.remainder(60));
    return d.inHours > 0 ? '${d.inHours}:$mm:$ss' : '$mm:$ss';
  }

  Future<void> _atualizarParticipantes(int salaId) async {
    try {
      final n = await widget.api.fetchParticipantesSala(
        widget.conta.ramal,
        widget.conta.senha,
        salaId,
      );
      if (!mounted) return;
      setState(() => _participantes = n);
    } catch (_) {
      // Best-effort — sem contador não deve travar a ligação em andamento.
    }
  }

  Future<void> _iniciarRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    _renderersProntos = true;
    _atualizarStreams();
  }

  void _atualizarStreams() {
    if (!_renderersProntos) return;
    _localRenderer.srcObject = widget.sip.localStream;
    // O onTrack do sip_ua dispara uma vez por faixa (áudio primeiro, vídeo
    // um pouco depois) — se for o mesmo objeto MediaStream ganhando a
    // faixa de vídeo por dentro, só reatribuir a mesma referência não
    // avisa o RTCVideoView que tem vídeo novo pra desenhar. Zera e
    // reatribui pra forçar reconectar — mas só quando o stream/faixas de
    // vídeo realmente mudaram. Fazer isso a cada mudança de estado do SIP
    // (mesmo sem relação com vídeo) recria a superfície de renderização
    // repetidas vezes seguidas e deixa a tela presa em preto (visto no
    // logcat como "EglImage dataspace changed, need recreate" em rajada).
    final remoto = widget.sip.remoteStream;
    final videoTracks = remoto?.getVideoTracks().length ?? 0;
    final mudou =
        remoto != _remoteStreamAnexado || videoTracks != _remoteVideoTracksAnexado;
    if (mudou) {
      _remoteRenderer.srcObject = null;
      _remoteRenderer.srcObject = remoto;
      _remoteStreamAnexado = remoto;
      _remoteVideoTracksAnexado = videoTracks;
    }

    unawaited(_sincronizarCamera());
  }

  /// Abre (uma única vez) o stream da câmera acoplada ao interfone.
  ///
  /// A URL só chega depois que o SipService consulta a lista de interfones —
  /// isso acontece em paralelo com a chamada tocando, pra não atrasá-la. Por
  /// isso o player é criado aqui, a cada mudança de estado, e não no
  /// initState: no momento em que a tela abre a URL ainda pode não existir.
  Future<void> _sincronizarCamera() async {
    final url = widget.sip.cameraDaChamadaUrl;
    if (url == null || url.isEmpty) return;
    if (_cameraUrlAberta == url) return;

    _cameraUrlAberta = url;
    _cameraPlayer?.dispose();
    try {
      final player = Player();
      _cameraPlayer = player;
      _cameraController = VideoController(player);
      // RTSP por TCP, não UDP. O padrão do libmpv tenta UDP primeiro, e no
      // 4G/5G do morador o NAT da operadora costuma descartar os pacotes de
      // volta — a imagem simplesmente não vem, sem erro claro. Em TCP o
      // stream desce pela mesma conexão que já foi aberta e autenticada.
      final nativo = player.platform;
      if (nativo is NativePlayer) {
        await nativo.setProperty('rtsp-transport', 'tcp');
      }
      // O player avisa por aqui quando não consegue abrir o stream (DVR fora
      // do ar, credencial errada, rede bloqueando RTSP). Sem escutar isso, a
      // falha era invisível: a tela só voltava a mostrar o vídeo do interfone
      // e parecia que o botão de trocar câmera não funcionava.
      _erroCameraSub = player.stream.error.listen((e) {
        debugPrint('[Portcall] câmera da chamada falhou: $e');
        if (mounted) setState(() => _erroCamera = e);
      });
      player.open(Media(url));
    } catch (e) {
      debugPrint('[Portcall] não consegui criar o player da câmera: $e');
      _cameraController = null;
      if (mounted) setState(() => _erroCamera = '$e');
    }
  }

  @override
  void dispose() {
    widget.sip.removeListener(_onSipChange);
    _lifecycleListener.dispose();
    _pollParticipantes?.cancel();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    // Sem isso o libmpv continua puxando o stream RTSP depois da chamada
    // terminar — consumindo dados móveis do morador em segundo plano.
    _erroCameraSub?.cancel();
    _cameraPlayer?.dispose();
    _tickDuracao?.cancel();
    _pulso.dispose();
    // Solta a tela ao sair da chamada. Sem isto o aparelho ficaria aceso
    // indefinidamente depois de uma ligação de vídeo — o wakelock é do
    // processo, não da tela, e não cai sozinho quando a tela fecha.
    unawaited(_sincronizarTelaAcesa(false));
    super.dispose();
  }

  void _onSipChange() {
    if (!mounted) return;
    _atualizarStreams();
    _sincronizarDuracao();
    // Tela acesa só quando há imagem de verdade chegando — enquanto a
    // chamada apenas toca não faz diferença, e numa chamada de áudio seria
    // desperdício de bateria.
    unawaited(
      _sincronizarTelaAcesa(
        widget.sip.remoteStream?.getVideoTracks().isNotEmpty ?? false,
      ),
    );
    setState(() {});
    if (!widget.sip.emChamada) {
      Navigator.of(context).maybePop();
    }
  }

  void _abrirTeclado() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        const teclas = [
          '1',
          '2',
          '3',
          '4',
          '5',
          '6',
          '7',
          '8',
          '9',
          '*',
          '0',
          '#',
        ];
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: GridView.count(
              shrinkWrap: true,
              crossAxisCount: 3,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.4,
              children: teclas.map((tecla) {
                return Material(
                  color: Colors.white10,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => widget.sip.enviarDtmf(tecla),
                    child: Center(
                      child: Text(
                        tecla,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  void _abrirPortao(AppButton b) {
    widget.sip.enviarDtmf(b.dtmfDigitos ?? '');
    setState(() => _portoesAbrindo.add(b.nome));
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _portoesAbrindo.remove(b.nome));
    });

    // Fire-and-forget: o portão já foi acionado (DTMF enviado); se o registro
    // do histórico falhar (rede etc.), não deve incomodar o morador com erro.
    unawaited(
      widget.api
          .registrarAcessoPortao(widget.conta.ramal, widget.conta.senha, b.nome)
          .catchError((_) {}),
    );
  }

  String _statusTexto(CallStateEnum estado) {
    switch (estado) {
      case CallStateEnum.CALL_INITIATION:
      case CallStateEnum.CONNECTING:
        return 'Chamando…';
      case CallStateEnum.PROGRESS:
        return widget.chamadaEntrante ? 'Chamada recebida' : 'Tocando…';
      case CallStateEnum.ACCEPTED:
      case CallStateEnum.CONFIRMED:
        return 'Em chamada';
      case CallStateEnum.HOLD:
        return 'Em espera';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final estado = widget.sip.callState;
    final aguardandoAtender =
        widget.chamadaEntrante && estado == CallStateEnum.PROGRESS;
    final ofertaTemVideo = widget.sip.ofertaEntranteTemVideo;
    // Não usa só chamadaComVideo: é decidido no instante de atender/ligar e
    // pode ficar preso em falso se a oferta de vídeo (SDP) ainda não tiver
    // sido totalmente associada à sessão naquele momento — mesmo com a
    // faixa de vídeo chegando de verdade no stream remoto depois. Aqui
    // confere se o stream tem uma faixa de vídeo de verdade, o que reflete
    // a realidade em vez de um flag que pode ter corrido errado.
    final comVideo =
        widget.sip.remoteStream?.getVideoTracks().isNotEmpty ?? false;

    // "É uma chamada de vídeo?" — diferente de `comVideo`, que é "a imagem
    // JÁ está chegando". Serve para esconder a logo assim que se atende: o
    // vídeo leva um instante para aparecer, e nesse intervalo a marca ficava
    // por cima da imagem que começava a surgir.
    final ehVideo =
        comVideo ||
        widget.sip.chamadaComVideo ||
        (widget.chamadaEntrante && widget.sip.ofertaEntranteTemVideo);

    final emSalaConferencia = widget.sip.emSalaConferencia;
    // Atalhos de portão só aparecem quando podem ser úteis: falando com a
    // portaria. Numa reunião ou numa ligação pro vizinho, só ocupam espaço.
    final mostrarAtalhosPortao =
        !emSalaConferencia && !widget.sip.chamadaEntreUnidades;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Câmera do condomínio ocupa a tela quando o morador escolheu ela
            // — ou automaticamente, quando o interfone não tem vídeo próprio e
            // ela é a única imagem possível (ver SipService.mostrandoCamera).
            // A câmera NÃO ocupa a tela toda, diferente do vídeo do interfone.
            //
            // Em tela cheia ela competia com os controles da chamada: o
            // morador abre a câmera justamente pra ver quem está no portão e
            // então apertar "abrir" — as duas coisas precisam estar visíveis
            // ao mesmo tempo. Ocupando a metade de cima, a imagem fica grande
            // o suficiente pra reconhecer alguém e o botão do portão continua
            // à mão, sobre fundo escuro.
            if (widget.sip.mostrandoCamera && _cameraController != null)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: MediaQuery.of(context).size.height * 0.52,
                child: Video(
                  controller: _cameraController!,
                  controls: NoVideoControls,
                  fit: BoxFit.cover,
                ),
              )
            // Sem isto, falha da câmera era indistinguível de botão quebrado:
            // a tela voltava calada pro vídeo do interfone.
            else if (widget.sip.mostrandoCamera)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: MediaQuery.of(context).size.height * 0.52,
                child: ColoredBox(
                  color: Colors.black87,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        _erroCamera == null
                            ? 'Conectando à câmera…'
                            : 'Câmera indisponível\n$_erroCamera',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                ),
              )
            else if (comVideo)
              Positioned.fill(
                child: RTCVideoView(
                  _remoteRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),
            // Botão de alternar entre as duas imagens. Só aparece quando
            // existem AS DUAS — com uma fonte só ele não teria o que alternar
            // e seria ruído numa tela que precisa ser óbvia em 2 segundos.
            if (widget.sip.cameraDaChamadaUrl != null && comVideo)
              Positioned(
                left: 16,
                top: 16,
                child: Material(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(24),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: widget.sip.alternarFonteDeVideo,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            widget.sip.mostrandoCamera
                                ? Icons.videocam_rounded
                                : Icons.photo_camera_outlined,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            widget.sip.mostrandoCamera
                                ? 'Ver interfone'
                                : 'Ver câmera',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            // Miniatura da própria câmera do morador: escondida enquanto ele
            // olha a câmera do condomínio — ali ele quer ver o portão, não o
            // próprio rosto ocupando canto da tela.
            if (comVideo &&
                widget.sip.localStream != null &&
                !widget.sip.mostrandoCamera)
              Positioned(
                right: 16,
                top: 16,
                width: 100,
                height: 140,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: RTCVideoView(
                    _localRenderer,
                    mirror: true,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                ),
              ),
            Column(
              children: [
                const Spacer(),
                // A marca aparece enquanto a chamada toca — inclusive numa
                // chamada de vídeo, porque até alguém atender não há imagem
                // nenhuma chegando e a tela ficaria preta e muda.
                //
                // Depois de atendida numa chamada de vídeo ela SOME, e quem
                // manda é `chamadaComVideo` (o que foi negociado), não o
                // stream já ter faixa de vídeo: o vídeo leva um instante
                // para chegar, e nesse intervalo a logo ficava por cima da
                // imagem que estava começando a aparecer.
                if (!ehVideo || _inicioConversa == null) ...[
                  _marcaDaChamada(tocando: _inicioConversa == null),
                  const SizedBox(height: 14),
                  // Quem está do outro lado. Em chamada recebida é o nome que
                  // o servidor montou no CALLERID ("Interfone Portão",
                  // "Unidade 102"); numa chamada que sai daqui, o destino.
                  if (widget.sip.nomeDaChamada.isNotEmpty)
                    Text(
                      widget.sip.nomeDaChamada,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        shadows: comVideo
                            ? const [Shadow(blurRadius: 8, color: Colors.black)]
                            : null,
                      ),
                    ),
                  const SizedBox(height: 6),
                ],
                Text(
                  _statusTexto(estado),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    shadows: comVideo
                        ? const [Shadow(blurRadius: 8, color: Colors.black)]
                        : null,
                  ),
                ),
                if (emSalaConferencia && _participantes != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.groups,
                          color: Colors.white,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _participantes == 1
                              ? 'Só você na sala'
                              : '$_participantes pessoas na sala',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const Spacer(),
                // Cronômetro aqui embaixo, perto dos controles, e não no
                // meio da tela: no meio ele disputa espaço com a imagem da
                // chamada de vídeo e com o nome de quem está falando. Só
                // existe depois de atender — um "00:00" parado em tela dá a
                // impressão de que a conversa já começou.
                if (_inicioConversa != null) ...[
                  Text(
                    _duracaoTexto,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 16,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      shadows: comVideo
                          ? const [Shadow(blurRadius: 8, color: Colors.black)]
                          : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (!aguardandoAtender &&
                    mostrarAtalhosPortao &&
                    widget.botoesDtmf.isNotEmpty) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: widget.botoesDtmf.map((b) {
                      final abrindo = _portoesAbrindo.contains(b.nome);
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FloatingActionButton(
                              heroTag: 'portao_${b.nome}',
                              backgroundColor: abrindo
                                  ? Colors.amber
                                  : Colors.white10,
                              foregroundColor: abrindo
                                  ? Colors.black
                                  : Colors.white,
                              onPressed: () => _abrirPortao(b),
                              child: Icon(
                                abrindo ? Icons.lock_open : Icons.lock_outline,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              b.nome,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                ],
                if (aguardandoAtender && ofertaTemVideo) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FloatingActionButton(
                            heroTag: 'atender_audio',
                            backgroundColor: Colors.white10,
                            foregroundColor: Colors.white,
                            onPressed: () => widget.sip.atender(video: false),
                            child: const Icon(Icons.call),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Sem vídeo',
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(width: 32),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FloatingActionButton(
                            heroTag: 'atender_video',
                            backgroundColor: Colors.green,
                            onPressed: () => widget.sip.atender(video: true),
                            child: const Icon(Icons.videocam),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Com vídeo',
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 30,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      if (aguardandoAtender && !ofertaTemVideo)
                        FloatingActionButton(
                          heroTag: 'atender',
                          backgroundColor: Colors.green,
                          onPressed: () => widget.sip.atender(),
                          child: const Icon(Icons.call),
                        ),
                      if (!aguardandoAtender)
                        FloatingActionButton(
                          heroTag: 'viva_voz',
                          backgroundColor: widget.sip.altoFalante
                              ? Colors.amber
                              : Colors.white10,
                          foregroundColor: widget.sip.altoFalante
                              ? Colors.black
                              : Colors.white,
                          onPressed: widget.sip.alternarAltoFalante,
                          child: Icon(
                            widget.sip.altoFalante
                                ? Icons.volume_up
                                : Icons.hearing,
                          ),
                        ),
                      if (!aguardandoAtender && emSalaConferencia)
                        FloatingActionButton(
                          heroTag: 'mudo',
                          backgroundColor: widget.sip.muted
                              ? Colors.amber
                              : Colors.white10,
                          foregroundColor: widget.sip.muted
                              ? Colors.black
                              : Colors.white,
                          onPressed: widget.sip.alternarMudo,
                          child: Icon(
                            widget.sip.muted ? Icons.mic_off : Icons.mic,
                          ),
                        ),
                      if (!aguardandoAtender && !emSalaConferencia)
                        FloatingActionButton(
                          heroTag: 'teclado',
                          backgroundColor: Colors.white10,
                          foregroundColor: Colors.white,
                          onPressed: _abrirTeclado,
                          child: const Icon(Icons.dialpad),
                        ),
                      FloatingActionButton(
                        heroTag: 'desligar',
                        backgroundColor: Colors.red,
                        onPressed: widget.sip.desligar,
                        child: const Icon(Icons.call_end),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
