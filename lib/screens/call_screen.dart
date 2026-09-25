import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:sip_ua/sip_ua.dart';

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

class _CallScreenState extends State<CallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _renderersProntos = false;
  final Set<String> _portoesAbrindo = {};
  MediaStream? _remoteStreamAnexado;
  int _remoteVideoTracksAnexado = -1;
  Timer? _pollParticipantes;
  int? _participantes;
  late final AppLifecycleListener _lifecycleListener;

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
  }

  @override
  void dispose() {
    widget.sip.removeListener(_onSipChange);
    _lifecycleListener.dispose();
    _pollParticipantes?.cancel();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  void _onSipChange() {
    if (!mounted) return;
    _atualizarStreams();
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
            if (comVideo)
              Positioned.fill(
                child: RTCVideoView(
                  _remoteRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),
            if (comVideo && widget.sip.localStream != null)
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
                if (!comVideo) ...[
                  Icon(
                    Icons.person,
                    size: 96,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                  const SizedBox(height: 16),
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
