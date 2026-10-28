import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:sip_ua/sip_ua.dart';
import 'package:uuid/uuid.dart';

import '../versao_app.dart';
import '../models/interfone.dart';
import 'api_service.dart';
import 'foreground_service.dart';
import 'session_service.dart';

/// Encapsula o registro SIP e as chamadas usando o pacote sip_ua.
/// Conecta via WSS (porta 8089, transporte [transport-ws] do painel) — os
/// endpoints estão configurados com webrtc=yes (ICE, BUNDLE áudio+vídeo),
/// que é pensado pra sinalização WebSocket. TCP puro já foi usado antes,
/// mas causava negociação de ICE estranha (candidato de rede trocando no
/// meio da ligação, áudio picotado/robotizado) por sinalizar via TCP algo
/// que o servidor trata como sessão WebRTC.
class SipService extends ChangeNotifier implements SipUaHelperListener {
  final SIPUAHelper _helper = SIPUAHelper();
  final Uuid _uuid = const Uuid();
  StreamSubscription<CallEvent?>? _callKitSub;
  String? _callKitId;

  /// Atendimento pedido antes de existir chamada SIP pra responder — ver
  /// `atender()`. Só acontece no iPhone, onde o push VoIP faz o telefone
  /// tocar antes do INVITE chegar.
  bool _atendimentoPendente = false;
  bool? _videoDoAtendimentoPendente;

  /// O par do campo acima: recusa feita antes do INVITE existir.
  bool _recusaPendente = false;

  /// Quem está ligando, guardado enquanto a chamada entrante toca — depois
  /// que ela termina o `remote_identity` já não está mais disponível, e é
  /// justamente aí que a notificação de perdida precisa do nome.
  String? _nomeEntrante;
  String? _numeroEntrante;

  /// A chamada entrante chegou a ser atendida? Usado para decidir se vira
  /// "chamada perdida" quando termina.
  bool _entranteAtendida = false;

  /// O morador recusou de propósito? Telefone nenhum mostra "perdida" quando
  /// a pessoa aperta recusar — ela sabe que a chamada existiu.
  bool _entranteRecusada = false;

  /// A conta da sessão, guardada no conectar() — usada pra buscar a lista de
  /// interfones quando uma chamada chega.
  SipAccount? _conta;

  /// Nome que aparece nas notificações de chamada do Android.
  ///
  /// Vem do branding do painel (`app_nome`), não de texto fixo: o app é
  /// white-label e cada condomínio tem o seu — estava chegando "Portcall" na
  /// notificação de um app que o morador conhece como "MultVirtual Video
  /// Atende". Lido do cache (SessionService), porque a notificação precisa do
  /// nome no instante em que a chamada chega, sem tempo pra ir na rede.
  String _nomeApp = 'Vídeo Atende';

  Future<void> _carregarNomeApp() async {
    try {
      final branding = await SessionService().loadBranding();
      final nome = branding?.appNome.trim();
      if (nome != null && nome.isNotEmpty) _nomeApp = nome;
    } catch (_) {
      // Fica o padrão — nome errado na notificação é menos grave do que
      // atrapalhar o registro SIP.
    }
  }

  /// Interfones do condomínio, com a câmera que o painel associou a cada um.
  /// Buscados sob demanda e mantidos em memória: a lista muda raramente e a
  /// chamada não pode esperar rede pra decidir o que mostrar.
  List<Interfone>? _interfones;

  /// Câmera a mostrar na chamada atual, quando quem liga é um interfone com
  /// câmera associada no painel. Nulo em chamada de unidade ou de interfone
  /// sem câmera.
  String? cameraDaChamadaUrl;
  String? cameraDaChamadaNome;

  /// Fonte de vídeo escolhida pelo morador durante a chamada. Só faz
  /// diferença quando existem as duas (vídeo do interfone e câmera) — é o
  /// botão de alternar da tela de chamada.
  bool mostrandoCamera = false;

  RegistrationStateEnum registrationState = RegistrationStateEnum.NONE;
  Call? activeCall;
  CallStateEnum callState = CallStateEnum.NONE;
  String? lastError;
  MediaStream? localStream;
  MediaStream? remoteStream;
  bool chamadaComVideo = false;
  bool _ofertaEntranteTemVideoCache = false;
  bool muted = false;
  bool altoFalante = false;
  String? _ultimoDestino;

  /// Quem está do outro lado, para a tela de chamada mostrar.
  ///
  /// Na chamada recebida é o nome que o servidor montou no CALLERID — o
  /// `portcall_router.agi` manda "Interfone Portão" ou "Unidade 102", que é
  /// o que o morador reconhece; o ramal cru (5000) não diz nada a ele. Numa
  /// chamada que sai daqui é o destino discado.
  ///
  /// Vazio quando não há chamada, e a tela simplesmente não mostra a linha.
  ///
  /// Na chamada que sai daqui, o nome do morador vem da unidade escolhida na
  /// tela (campo opcional da rota, no painel) — "102 — João Silva" em vez de
  /// só "102". Quem disca pelo teclado não tem nome a informar e continua
  /// vendo o número.
  String get nomeDaChamada =>
      _nomeEntrante ??
      _nomeDestino ??
      _ultimoDestino ??
      _numeroEntrante ??
      '';

  /// Nome amigável do destino de uma chamada que sai daqui. Ver [ligarPara].
  String? _nomeDestino;

  /// Sala de conferência (ver salas_conferencia_screen.dart) usa números
  /// reservados no padrão "9" + 4 dígitos — nunca um apartamento/dialpad
  /// normal. A tela de chamada usa isso pra simplificar os botões (sem
  /// atalho de portão/teclado, já que não faz sentido numa reunião).
  bool get emSalaConferencia =>
      _ultimoDestino != null && RegExp(r'^9\d{4}$').hasMatch(_ultimoDestino!);

  /// Id da sala (mesmo id da tabela salas_conferencia) pra consultar o
  /// contador de participantes — número de discagem é sempre 90000 + id.
  int? get idSalaConferencia =>
      emSalaConferencia ? int.parse(_ultimoDestino!) - 90000 : null;

  /// Ligação de morador pra morador. A tela de chamada usa isso pra esconder
  /// os atalhos de portão: abrir o portão faz sentido falando com a
  /// portaria, não com o vizinho.
  ///
  /// Vale nos dois sentidos. Na chamada que sai daqui, quem marca é a tela
  /// (`ligarPara(entreUnidades: true)`). Na chamada recebida, o app sozinho
  /// só enxerga o ramal de origem (ex.: 5001) e não tem como saber de quem
  /// é — o vínculo ramal→unidade mora no servidor. Por isso o
  /// `portcall_router.agi` identifica a origem no CALLERID como
  /// "Unidade 102", e é esse prefixo que reconhecemos aqui.
  bool get chamadaEntreUnidades => _entreUnidades;
  bool _entreUnidades = false;

  /// Prefixo que o portcall_router.agi coloca no CALLERID quando quem liga
  /// é outra unidade. Mudou lá? Mude aqui.
  static const _prefixoUnidade = 'Unidade ';

  SipService() {
    _helper.addSipUaHelperListener(this);
    _callKitSub = FlutterCallkitIncoming.onEvent.listen(_onCallKitEvent);
  }

  /// Android 14+: sem essa permissão a tela de chamada do CallKit não
  /// aparece com o celular bloqueado/tela apagada (só a notificação normal,
  /// que o usuário precisa desbloquear o telefone e abrir pra ver). Precisa
  /// ser concedida manualmente pelo usuário numa tela do sistema, não é um
  /// diálogo simples — por isso só pede se ainda não tiver.
  static Future<void> solicitarPermissaoTelaCheia() async {
    try {
      final jaTem = await FlutterCallkitIncoming.canUseFullScreenIntent();
      if (jaTem != true) {
        await FlutterCallkitIncoming.requestFullIntentPermission();
      }
    } catch (_) {
      // Best-effort — sem essa permissão o app ainda funciona, só a chamada
      // não aparece automaticamente com a tela apagada.
    }
  }

  void _onCallKitEvent(CallEvent? event) {
    switch (event) {
      case CallEventActionCallAccept():
        _entranteAtendida = true;
        atender();
      case CallEventActionCallDecline():
        // Recusa deliberada não vira "perdida" — o morador já sabe que
        // ligaram, foi ele quem dispensou.
        _entranteRecusada = true;
        desligar();
      case CallEventActionCallTimeout():
        desligar();
      default:
        break;
    }
  }

  /// No iPhone a chamada pode já estar tocando ANTES deste INVITE chegar: o
  /// push VoIP acorda o app e o `AppDelegate` é obrigado a reportar a
  /// chamada ao CallKit na hora (o iOS mata quem recebe push VoIP e não
  /// reporta). Quando o registro SIP termina e o INVITE enfim chega, mostrar
  /// outra chamada criaria DUAS entradas no CallKit para o mesmo toque — e
  /// como só uma é encerrada no fim, o iPhone fica preso achando que ainda
  /// está em ligação.
  ///
  /// Devolve o id da chamada que já está na tela, para ser reaproveitado.
  Future<String?> _chamadaJaReportadaPeloPush() async {
    if (!Platform.isIOS) return null;
    try {
      final ativas = await FlutterCallkitIncoming.activeCalls();
      for (final c in ativas) {
        final id = c.id;
        if (id.isNotEmpty) return id;
      }
    } catch (e) {
      debugPrint('[Portcall] activeCalls() falhou: $e');
    }
    return null;
  }

  /// Lê quem está ligando da sessão SIP. SÍNCRONO de propósito.
  ///
  /// Isto ficava dentro de `_mostrarChamadaEntrante`, depois de um `await` —
  /// e o `notifyListeners()` do `callStateChanged` já tinha rodado antes,
  /// então a tela de chamada abria com o nome ainda vazio e nada a
  /// atualizava depois. Não incomodava enquanto o nome não era exibido;
  /// passou a aparecer como "chamada sem o nome de quem liga".
  void _identificarQuemLiga(Call call) {
    final remoteId = call.session.remote_identity;
    final numero = remoteId?.uri?.user;
    _numeroEntrante = numero;
    _nomeEntrante = (remoteId?.display_name?.isNotEmpty == true)
        ? remoteId!.display_name!
        : (numero ?? 'Desconhecido');
  }

  Future<void> _mostrarChamadaEntrante(Call call) async {
    final idDoPush = await _chamadaJaReportadaPeloPush();
    _callKitId = idDoPush ?? _uuid.v4();
    final numero = _numeroEntrante;
    final nome = _nomeEntrante ?? numero ?? 'Desconhecido';

    // Nome e número já foram lidos em _identificarQuemLiga, antes do await
    // acima — ver lá o porquê. Aqui só se zera o que é desta chamada.
    _entranteAtendida = false;
    _entranteRecusada = false;

    // Sem await: a decisão sobre a câmera não pode atrasar a tela de chamada
    // aparecer. Quando a resposta chega, o notifyListeners() de dentro faz a
    // tela se atualizar sozinha.
    unawaited(_resolverCameraDaChamada(numero));

    // Já está tocando por causa do push VoIP — só adotamos o id dela acima.
    // Reportar de novo duplicaria a chamada no CallKit.
    if (idDoPush != null) {
      debugPrint('[Portcall] INVITE adotou a chamada do push VoIP ($idDoPush)');
      return;
    }

    await FlutterCallkitIncoming.showCallkitIncoming(
      CallKitParams(
        id: _callKitId!,
        nameCaller: nome,
        appName: _nomeApp,
        handle: numero ?? nome,
        type: 0,
        duration: 30000,
        android: const AndroidParams(
          isCustomNotification: true,
          ringtonePath: 'system_ringtone_default',
          backgroundColor: '#1565C0',
          actionColor: '#FFB300',
          incomingCallNotificationChannelName: 'Chamada recebida',
          missedCallNotificationChannelName: 'Chamada perdida',
          textAccept: 'Atender',
          textDecline: 'Recusar',
        ),
        ios: const IOSParams(
          iconName: 'AppIcon',
          handleType: 'generic',
          supportsVideo: true,
          supportsDTMF: true,
          supportsHolding: false,
          supportsGrouping: false,
          supportsUngrouping: false,
          // Sem isto a chamada entra no histórico do app Telefone, e tocar no
          // número lá tentaria discá-lo pela operadora — o "número" aqui é um
          // ramal do condomínio, que não existe fora do PBX.
          includesCallsInRecents: false,
          // ESTA é a linha do viva-voz. Com `true` (o padrão), o plugin
          // reconfigura a AVAudioSession inteira por conta própria quando o
          // CallKit ativa a sessão — por fora do RTCAudioSession, que é quem
          // o WebRTC usa e o único caminho que respeita o lock dele.
          // Resultado: o flutter_webrtc colocava o som no viva-voz e um
          // instante depois o plugin devolvia pro fone do ouvido.
          //
          // Num app WebRTC quem deve mandar na sessão de áudio é o WebRTC.
          // Desligando isto, o `Helper.setSpeakerphoneOn` passa a ser a
          // palavra final — e é ele que o `_aplicarSaidaDeAudio` chama.
          configureAudioSession: false,
          audioSessionMode: 'voiceChat',
        ),
      ),
    );
  }

  /// Deixa a notificação de chamada perdida no celular, como faz o telefone.
  ///
  /// Sem isso, uma chamada do interfone que o morador não ouviu não deixava
  /// rastro nenhum: ele descobria depois, pelo visitante, que alguém tinha
  /// tocado. O canal já estava declarado em AndroidParams
  /// (`missedCallNotificationChannelName`), só faltava chamar o método.
  ///
  /// NÃO é mostrada quando o morador recusa de propósito — telefone nenhum
  /// avisa "perdida" para uma chamada que a pessoa dispensou.
  Future<void> _notificarChamadaPerdida() async {
    final nome = _nomeEntrante;
    if (nome == null) return;
    try {
      await FlutterCallkitIncoming.showMissCallNotification(
        CallKitParams(
          id: _uuid.v4(),
          nameCaller: nome,
          appName: _nomeApp,
          handle: _numeroEntrante ?? nome,
          type: 0,
          // Sem este bloco a notificação aparece, mas MUDA: o lado Android lê
          // o texto de `subtitle` (EXTRA_CALLKIT_MISSED_CALL_SUBTITLE) e, se
          // vier vazio, mostra só o nome de quem ligou — sem dizer que foi
          // uma chamada perdida.
          missedCallNotification: const NotificationParams(
            showNotification: true,
            subtitle: 'Chamada perdida',
            // O botão de "ligar de volta" fica desligado de propósito: o
            // evento dele ainda não é tratado em _onCallKitEvent, e botão que
            // não faz nada ao ser tocado é pior do que botão nenhum.
            isShowCallback: false,
          ),
          android: const AndroidParams(
            // FALSE aqui de propósito, diferente da chamada entrante.
            //
            // Com `true`, o CallkitNotificationManager monta a notificação com
            // um RemoteViews próprio (layout_custom_miss_notification) que só
            // preenche o nome de quem ligou — e o texto definido em
            // `subtitle` vai pro setSubText do builder padrão, que o layout
            // customizado substitui. Resultado: a notificação aparecia sem
            // dizer que era uma chamada perdida.
            //
            // Com `false` vale o estilo padrão do Android, que mostra o
            // subtexto e ainda usa CATEGORY_MISSED_CALL — o sistema agrupa e
            // apresenta como o telefone faz.
            isCustomNotification: false,
            missedCallNotificationChannelName: 'Chamada perdida',
          ),
        ),
      );
    } catch (e) {
      // Melhor esforço: a notificação é um conforto, não pode derrubar o
      // encerramento da chamada se falhar.
      debugPrint('[Portcall] notificação de chamada perdida falhou: $e');
    }
  }

  Future<void> _encerrarChamadaKit() async {
    final id = _callKitId;
    if (id == null) return;
    _callKitId = null;
    await FlutterCallkitIncoming.endCall(id);
  }

  /// Só esconde a notificação/popup nativo, sem mandar broadcast de
  /// aceitar/recusar pro Android. endCall() manda "decline" quando o
  /// próprio popup nativo nunca foi tocado (isAccepted continua false do
  /// lado nativo) — isso volta como Event.actionCallDecline no nosso
  /// listener e desliga a ligação que acabamos de atender pelo botão do
  /// app. hideCallkitIncoming() só limpa a notificação, sem broadcast.
  ///
  /// NÃO zera _callKitId aqui — esse é o mesmo id da conexão de Telecom de
  /// verdade (self-managed ConnectionService da v3), ainda precisado quando
  /// a ligação terminar de vez pra chamar endCall(). Zerar aqui (bug real,
  /// encontrado em produção) fazia _encerrarChamadaKit() virar um no-op
  /// silencioso em TODA ligação atendida — a conexão nunca era encerrada de
  /// verdade no Android, ficava presa pra sempre (viu-se travando o
  /// roteamento de áudio do celular inteiro, não só do app).
  Future<void> _esconderChamadaKit() async {
    final id = _callKitId;
    if (id == null) return;
    await FlutterCallkitIncoming.hideCallkitIncoming(CallKitParams(id: id));
  }

  bool get isRegistered =>
      registrationState == RegistrationStateEnum.REGISTERED;
  bool get emChamada =>
      activeCall != null &&
      callState != CallStateEnum.ENDED &&
      callState != CallStateEnum.FAILED;

  /// Descobre se quem está ligando é um interfone com câmera associada.
  ///
  /// A busca é feita aqui, e não na tela, de propósito: quando o celular
  /// recebe a chamada com o app fechado não existe Activity nenhuma, nenhum
  /// widget é construído e nada do lado da interface chega a rodar — mas
  /// rede e timers continuam funcionando normalmente (ver main.dart). Deixar
  /// isso na tela faria a câmera aparecer só quando o app já estivesse aberto,
  /// justamente o caso em que o morador menos precisa.
  Future<void> _resolverCameraDaChamada(String? numeroOrigem) async {
    cameraDaChamadaUrl = null;
    cameraDaChamadaNome = null;
    mostrandoCamera = false;

    final conta = _conta;
    if (numeroOrigem == null || numeroOrigem.isEmpty || conta == null) return;

    // Com lista em memória, decide AGORA e revalida depois: a chamada não
    // pode esperar rede pra saber o que mostrar.
    //
    // O `??=` que estava aqui nunca reconsultava o painel. Como o SipService
    // vive junto com o serviço persistente (ou seja: quase sempre, no
    // Android), trocar a câmera do interfone no painel não tinha efeito
    // nenhum até alguém reinstalar o app — o morador via a câmera antiga.
    if (_interfones != null) {
      _aplicarCameraDoInterfone(numeroOrigem);
      unawaited(_recarregarInterfones(conta, numeroOrigem));
      return;
    }

    try {
      _interfones = await ApiService(
        conta.painelUrl,
      ).fetchInterfonia(conta.ramal, conta.senha);
      _aplicarCameraDoInterfone(numeroOrigem);
    } catch (e) {
      // Melhor esforço: sem a lista, a chamada acontece normalmente, só sem
      // a imagem da câmera. Não pode atrapalhar o interfone tocar.
      debugPrint('[Portcall] não consegui resolver a câmera do interfone: $e');
    }
  }

  /// Rebusca a lista e, se a câmera daquele interfone mudou, troca a imagem
  /// durante a própria chamada — a tela escuta o notifyListeners.
  Future<void> _recarregarInterfones(
    SipAccount conta,
    String? numeroOrigem,
  ) async {
    try {
      _interfones = await ApiService(
        conta.painelUrl,
      ).fetchInterfonia(conta.ramal, conta.senha);
      _aplicarCameraDoInterfone(numeroOrigem);
    } catch (_) {
      // Fica o que já estava em memória.
    }
  }

  void _aplicarCameraDoInterfone(String? numeroOrigem) {
    for (final i in _interfones ?? const <Interfone>[]) {
      if (i.destino == numeroOrigem && i.temCamera) {
        final mudou = cameraDaChamadaUrl != i.cameraUrl;
        cameraDaChamadaUrl = i.cameraUrl;
        cameraDaChamadaNome = i.cameraNome;
        // Sem vídeo próprio, a câmera é a única imagem possível — já começa
        // mostrando ela. Com vídeo, começa no vídeo do interfone e o
        // morador alterna se quiser. Só reposiciona na primeira resolução:
        // numa revalidação no meio da chamada, respeita o que o morador
        // escolheu no botão.
        if (mudou) mostrandoCamera = !i.suportaVideo;
        notifyListeners();
        return;
      }
    }
  }

  /// Alterna entre o vídeo do próprio interfone e a câmera do condomínio.
  void alternarFonteDeVideo() {
    if (cameraDaChamadaUrl == null) return;
    mostrandoCamera = !mostrandoCamera;
    notifyListeners();
  }

  /// Guarda a conexão em andamento. Sem isso, duas chamadas concorrentes de
  /// conectar() abriam dois WebSockets para o mesmo ramal: main() conecta no
  /// arranque e HomeScreen._iniciar() chamava de novo, porque a guarda
  /// `if (!isRegistered)` lá ainda via false — o registro do main() estava em
  /// trânsito. O servidor aceitava o segundo REGISTER, o primeiro socket
  /// fechava, e o UNREGISTERED desse fechamento era o último estado que a
  /// tela recebia: ramal registrado no Asterisk, mas "Desconectado" no visor.
  Future<void>? _conexaoEmAndamento;
  bool _helperIniciado = false;

  Future<void> conectar(SipAccount conta) async {
    final emAndamento = _conexaoEmAndamento;
    if (emAndamento != null) return emAndamento;
    // Já iniciado para esta conta: não reinicia. conectar() devolve antes do
    // registro concluir (start() só dispara o transporte), então a guarda
    // `if (!isRegistered)` de quem chama ainda vê false e chamaria de novo —
    // e um segundo start() no sip_ua derruba a UA atual pra criar outra
    // ("UA instance already exist!, stopping UA"), gerando a oscilação
    // REGISTERED -> DISCONNECTED -> UNREGISTERED.
    final atual = _conta;
    if (_helperIniciado &&
        atual != null &&
        atual.ramal == conta.ramal &&
        atual.servidor == conta.servidor) {
      return;
    }
    final futuro = _conectar(conta);
    _conexaoEmAndamento = futuro;
    try {
      await futuro;
    } finally {
      _conexaoEmAndamento = null;
    }
  }

  Future<void> _conectar(SipAccount conta) async {
    _conta = conta;
    unawaited(_carregarNomeApp());
    final settings = UaSettings()
      // O endpoint no painel está com webrtc=yes (ICE, BUNDLE áudio+vídeo na
      // mesma porta) — isso é pensado pra sinalização WebSocket, não TCP puro.
      // Registrar por TCP mas negociar SDP como se fosse WebRTC gerava
      // comportamento de ICE estranho (troca de candidato IPv4/IPv6 no meio
      // da ligação, áudio picotado/robotizado). WSS usa o transporte
      // [transport-ws] que já existe no painel (porta 8089, TLS Let's
      // Encrypt válido, path /ws).
      ..webSocketUrl = 'wss://${conta.servidor}:8089/ws'
      ..transportType = TransportType.WS
      ..host = conta.servidor
      ..port = conta.porta
      ..uri = '${conta.ramal}@${conta.servidor}'
      ..authorizationUser = conta.ramal
      ..password = conta.senha
      ..displayName = conta.displayName.isNotEmpty
          ? conta.displayName
          : conta.ramal
      // A versão vai no User-Agent de propósito: ela aparece em todo
      // REGISTER e INVITE no log do Asterisk, e é a única forma de saber,
      // do servidor, qual build o aparelho está rodando. Já perdemos tempo
      // depurando um sintoma sem saber se o celular tinha mesmo a versão
      // nova instalada — o TestFlight demora horas para contabilizar
      // instalações e não serve para confirmar isso na hora.
      ..userAgent = 'PortcallApp/$versaoApp'
      ..dtmfMode = DtmfMode.RFC2833
      ..register = true
      // Curto de propósito: o transporte TCP do sip_ua não manda nenhum
      // keepalive entre um REGISTER e outro, e o mapeamento de NAT de rede
      // móvel costuma cair bem antes de 300s, deixando o app "registrado"
      // mas com a conexão de verdade morta (chamada entrante cai no vazio).
      ..register_expires = 60;

    debugPrint('[Portcall] SipService.conectar: iniciando helper (${conta.ramal}@${conta.servidor})');
    await _helper.start(settings);
    _helperIniciado = true;
    debugPrint('[Portcall] SipService.conectar: helper.start() retornou');
  }

  /// Teto de resolução e quadros do vídeo que ESTE aparelho envia.
  ///
  /// O sip_ua só define mínimos por padrão (`minWidth: 640`,
  /// `minHeight: 480`, `minFrameRate: 30`) e nenhum máximo — num celular
  /// moderno o WebRTC sobe bem acima disso, gastando dados e bateria à toa
  /// pra um interfone, onde basta enxergar quem está na portaria.
  ///
  /// Pra baixar mais (rede ruim, plano limitado), reduza `maxWidth`/
  /// `maxHeight` aqui — 480x360 ainda é perfeitamente legível. Os mínimos
  /// também caem junto, senão a câmera não consegue atender ao pedido.
  static const Map<String, dynamic> _constraintsVideoLeve = <String, dynamic>{
    'mediaConstraints': <String, dynamic>{
      'video': <String, dynamic>{
        // Os limites vão em `optional`, NUNCA em `mandatory`. No WebRTC,
        // `mandatory` é exigência: se a câmera não conseguir respeitar o
        // teto exato, o getUserMedia falha e o aparelho entra na chamada
        // SEM VÍDEO — foi o que aconteceu ao pôr maxFrameRate: 20 como
        // obrigatório, já que muita câmera Android só opera a 30fps. O
        // sintoma no SDP é `m=video 9` com `c=IN IP4 0.0.0.0`.
        //
        // Em `optional` o WebRTC aplica o que conseguir e, quando não
        // conseguir, manda vídeo assim mesmo — que é o que interessa num
        // interfone: melhor vídeo pesado que nenhum vídeo.
        'mandatory': <String, dynamic>{
          'minWidth': '320',
          'minHeight': '240',
          'minFrameRate': '10',
        },
        'facingMode': 'user',
        'optional': <dynamic>[
          <String, dynamic>{'maxWidth': '640'},
          <String, dynamic>{'maxHeight': '480'},
          <String, dynamic>{'maxFrameRate': '20'},
        ],
      },
    },
  };

  /// [entreUnidades] marca ligação de morador pra morador (tela Unidades) —
  /// ver `chamadaEntreUnidades`.
  /// [nomeExibicao] é quem a tela de chamada vai mostrar no lugar do número
  /// cru. Opcional: quem liga pelo teclado não tem nome nenhum para dar, e
  /// aí continua aparecendo o número discado.
  Future<bool> ligarPara(
    String destino, {
    bool video = false,
    bool entreUnidades = false,
    String? nomeExibicao,
  }) async {
    chamadaComVideo = video;
    muted = false;
    _ultimoDestino = destino;
    _nomeDestino = nomeExibicao?.trim().isEmpty == true ? null : nomeExibicao;
    _entreUnidades = entreUnidades;
    // Com vídeo, não dá pra ver a tela com o telefone no ouvido — liga o
    // viva-voz (ou fone bluetooth, se tiver um conectado) de cara. Sem
    // vídeo, começa no fone de ouvido normal (igual ligação de telefone
    // comum) — o usuário decide se quer viva-voz pelo botão na tela.
    altoFalante = video;
    // Enquanto CHAMA, o som vai pro alto-falante mesmo na ligação de áudio —
    // e isso não é o mesmo que `altoFalante`, que guarda a rota desejada pra
    // conversa (fone no áudio, viva-voz no vídeo).
    //
    // O tom de chamada sai pelo canal de voz (ver EngineHolder), e no fone de
    // ouvido ele é inaudível com o celular na mão: quem discou ouvia silêncio
    // e achava que a ligação não tinha completado. Só a chamada de vídeo
    // parecia funcionar, porque já começava no viva-voz.
    //
    // Em CONFIRMED, `_aplicarSaidaDeAudio()` devolve a rota escolhida acima —
    // é o mesmo ponto que já corrigia a assimetria do CallKit, então o
    // comportamento durante a conversa não muda em nada.
    unawaited(Helper.setSpeakerphoneOnButPreferBluetooth());
    // customOptions só quando há vídeo: o merge do sip_ua é recursivo, e
    // sobrepor um Map em cima de `video: false` transformaria uma chamada
    // de áudio em vídeo sem querer.
    //
    // E só no Android. O bloco `mandatory` do _constraintsVideoLeve está no
    // formato legado do Chrome/Android (minWidth/minHeight/minFrameRate como
    // texto); no iPhone ele faz a câmera nem abrir e a ligação cair logo em
    // seguida. O que denunciou foi a assimetria: chamada de vídeo RECEBIDA no
    // iPhone funciona — e é o único caminho que não passa por aqui, porque
    // quem responde usa o padrão do sip_ua.
    //
    // No iOS fica o padrão então. Perde-se o teto de resolução (mais dados
    // num interfone que não precisa de HD), mas vídeo pesado é melhor que
    // vídeo nenhum. Para otimizar lá, o caminho é o formato moderno de
    // constraints (width/height/frameRate), não este.
    // try/catch porque nenhuma das telas que chamam ligarPara trata exceção:
    // uma falha ao montar a chamada (câmera negada, constraint que o aparelho
    // recusa) sumia sem deixar rastro, e pro morador a ligação simplesmente
    // "não completava". Guardar em lastError deixa o motivo visível — é o
    // mesmo campo que a home já lê pra mostrar falha de registro.
    try {
      return await _helper.call(
        destino,
        voiceOnly: !video,
        customOptions: video && Platform.isAndroid
            ? _constraintsVideoLeve
            : null,
      );
    } catch (e) {
      lastError = 'Não foi possível iniciar a chamada: $e';
      debugPrint('[Portcall] ligarPara($destino, video: $video) falhou: $e');
      notifyListeners();
      return false;
    }
  }

  /// Muta/desmuta o microfone desativando a faixa de áudio local — o outro
  /// lado simplesmente para de receber áudio, sem precisar de suporte
  /// especial do lado remoto (funciona igual numa ligação normal ou numa
  /// sala de conferência).
  void alternarMudo() {
    muted = !muted;
    for (final t in localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !muted;
    }
    notifyListeners();
  }

  /// Alterna entre fone de ouvido e viva-voz — antes disso não tinha como
  /// voltar pro fone numa ligação de áudio (só vídeo tinha o viva-voz
  /// forçado de propósito; áudio ficava sem controle nenhum de rota,
  /// dependendo do que o Android decidisse por padrão).
  /// Usa o mesmo caminho do `_aplicarSaidaDeAudio` — com CallKit ativo,
  /// `setSpeakerphoneOn` sozinho não muda nada (ver lá o porquê).
  void alternarAltoFalante() {
    altoFalante = !altoFalante;
    unawaited(_aplicarSaidaDeAudio());
    notifyListeners();
  }

  /// Se a oferta da chamada (entrante) inclui vídeo — usado tanto pra decidir
  /// como atender automaticamente (CallKit) quanto pra mostrar a opção de
  /// vídeo/normal na tela de chamada. Calculado uma única vez, em
  /// callStateChanged() assim que a chamada chega (não relido a cada
  /// rebuild) — reler ao vivo já causou falso-negativo esporádico
  /// (ofertaEntranteTemVideo batendo antes do corpo do INVITE estar
  /// totalmente associado à sessão, atendendo sem vídeo por engano).
  bool get ofertaEntranteTemVideo => _ofertaEntranteTemVideoCache;

  /// [video] nulo = detecta sozinho pela oferta SDP recebida (usado pelo
  /// aceite via CallKit, tela bloqueada). Passe explicitamente pra respeitar
  /// a escolha do usuário na tela de chamada (atender com ou sem vídeo).
  void atender({bool? video}) {
    // Também marcado aqui, e não só no evento do CallKit: o morador pode
    // atender pelo botão da própria tela do app, caminho que não passa pelo
    // CallKit — sem isso, uma chamada atendida assim viraria "perdida" ao
    // terminar.
    _entranteAtendida = true;

    // Atendeu antes do INVITE existir (iPhone acordado por push VoIP: o
    // CallKit toca na hora, o SIP ainda está se registrando). Guarda a
    // intenção; callStateChanged atende assim que a chamada chegar.
    if (activeCall == null) {
      _atendimentoPendente = true;
      _videoDoAtendimentoPendente = video;
      debugPrint('[Portcall] atender() antes do INVITE — ficou pendente');
      return;
    }
    final comVideo = video ?? ofertaEntranteTemVideo;
    chamadaComVideo = comVideo;
    muted = false;
    _ultimoDestino = null;
    _nomeDestino = null;
    // NÃO zera _entreUnidades aqui: numa chamada recebida ele já foi
    // definido em callStateChanged, a partir do CALLERID que o servidor
    // montou. Zerar traria os atalhos de portão de volta justamente na
    // ligação do vizinho.
    altoFalante = comVideo;
    unawaited(
      comVideo
          ? Helper.setSpeakerphoneOnButPreferBluetooth()
          : Helper.setSpeakerphoneOn(false),
    );
    // Mesmo teto de vídeo de quem origina (ver _constraintsVideoLeve) —
    // sem isso, só metade das chamadas sairia com a resolução controlada.
    final opcoes = _helper.buildCallOptions(!comVideo);
    if (comVideo) {
      (opcoes['mediaConstraints'] as Map<String, dynamic>)['video'] =
          (_constraintsVideoLeve['mediaConstraints']
              as Map<String, dynamic>)['video'];
    }
    activeCall?.answer(opcoes);
    // Desde a v3 do flutter_callkit_incoming (ConnectionService próprio no
    // Android), setCallConnected é o que avisa o sistema que a ligação
    // ficou ativa de verdade — sem isso o áudio não roteia direito. Usa
    // hideCallkitIncoming em vez de endCall — endCall manda um broadcast
    // de "decline" quando o popup nativo nunca foi tocado, o que volta
    // pelo nosso próprio listener e desliga a ligação que acabou de ser
    // atendida pelo botão do app.
    final id = _callKitId;
    if (id != null) {
      unawaited(FlutterCallkitIncoming.setCallConnected(id));
    }
    unawaited(_esconderChamadaKit());
  }

  /// Força a saída de áudio atual (viva-voz ou fone), usando a API de
  /// seleção de dispositivo do flutter_webrtc em vez de
  /// `setSpeakerphoneOn`.
  ///
  /// Motivo: com o CallKit v3 o app roda como *self-managed
  /// ConnectionService*, e nesse modo quem decide a rota de áudio é o
  /// Telecom do Android — `AudioManager.setSpeakerphoneOn()` (o que
  /// `setSpeakerphoneOn`/`setSpeakerphoneOnButPreferBluetooth` chamam por
  /// baixo) simplesmente não tem efeito. `selectAudioOutput` passa pelo
  /// AudioSwitchManager, que fala a língua certa. Sem isso, numa chamada de
  /// vídeo quem atendia ouvia no fone enquanto quem ligou ouvia no
  /// viva-voz — só o lado que atende passa por CallKit.
  ///
  /// Fone Bluetooth tem precedência sobre o viva-voz: forçar o alto-falante
  /// com um fone conectado seria pior que o problema original.
  Future<void> _aplicarSaidaDeAudio() async {
    // Numa chamada que passou pelo CallKit (ou seja: toda chamada que o
    // morador ATENDE), quem decide a rota é o Telecom — ele se registra
    // como cliente privilegiado e o app, cliente comum, perde a disputa.
    // Confirmado em `dumpsys audio` durante uma chamada real:
    //
    //   app     -> pede SPEAKER   (mIsPrivileged: false)
    //   telecom -> pede EARPIECE  (mIsPrivileged: true)
    //   Active communication device: EARPIECE
    //
    // Então o pedido tem que sair de dentro do próprio Telecom. É o que o
    // setAudioRoute (patch local do pacote) faz. Se não houver conexão
    // CallKit — chamada originada aqui —, ele devolve false e seguimos
    // pelo caminho normal, que nesse caso funciona.
    // iOS tem outra história. Tudo abaixo foi escrito contra o Telecom do
    // Android: o setAudioRoute é patch nosso no lado Kotlin do pacote, o
    // setAndroidAudioConfiguration nem existe aqui, e o selectAudioOutput
    // vira no-op silencioso — ou seja, falha sem lançar, e aí o fallback
    // nunca roda. Era por isso que o viva-voz não saía no iPhone.
    //
    // No iOS o caminho é um só, e tem que ser um só: o `setSpeakerphoneOn`
    // do flutter_webrtc, que fala com a AVAudioSession através do
    // RTCAudioSession — com `lockForConfiguration`, como o WebRTC exige.
    //
    // Mexer na AVAudioSession por fora desse lock não adianta: o WebRTC
    // observa mudanças de rota e reaplica a configuração dele por cima. Foi
    // justamente o que fazia o viva-voz não sair aqui — não por falta de
    // pedido, mas porque o plugin do CallKit reconfigurava a sessão sozinho
    // quando o CallKit a ativava. Isso agora está desligado na própria
    // chamada (`configureAudioSession: false` no IOSParams), deixando o
    // WebRTC como dono da sessão.
    //
    // Nada de setAudioRoute aqui, então: no iOS ele seria um segundo dono
    // da mesma sessão, exatamente o problema que acabamos de tirar.
    if (Platform.isIOS) {
      try {
        if (altoFalante) {
          await Helper.setSpeakerphoneOnButPreferBluetooth();
        } else {
          await Helper.setSpeakerphoneOn(false);
        }
      } catch (e) {
        debugPrint('[Portcall] rota de áudio (iOS) falhou: $e');
      }
      return;
    }

    final id = _callKitId;
    if (id != null) {
      try {
        final ok = await FlutterCallkitIncoming.setAudioRoute(
          id,
          speaker: altoFalante,
        );
        if (ok) return;
      } catch (_) {
        // Segue pro caminho antigo.
      }
    }

    // ESTA é a linha que faz o resto funcionar. O CallKit coloca o
    // AudioManager em MODE_IN_CALL, e nesse modo o flutter_webrtc
    // DESLIGA o roteamento de áudio por conta própria (ver
    // `forceHandleAudioRouting` em audio_configuration.dart) — com isso
    // tanto setSpeakerphoneOn quanto selectAudioOutput viram no-op
    // silencioso. Era por isso que nem o viva-voz automático nem o botão
    // da tela de chamada surtiam efeito pra quem atendia.
    try {
      await Helper.setAndroidAudioConfiguration(
        AndroidAudioConfiguration(
          androidAudioMode: AndroidAudioMode.inCommunication,
          forceHandleAudioRouting: true,
        ),
      );
    } catch (_) {
      // Só existe no Android; no iOS a chamada não se aplica.
    }

    if (!altoFalante) {
      try {
        await Helper.selectAudioOutput('earpiece');
      } catch (_) {
        unawaited(Helper.setSpeakerphoneOn(false));
      }
      return;
    }

    try {
      final saidas = await Helper.audiooutputs;
      final temBluetooth = saidas.any(
        (d) => d.label.toLowerCase().contains('bluetooth'),
      );
      if (temBluetooth) {
        await Helper.setSpeakerphoneOnButPreferBluetooth();
        return;
      }
      await Helper.selectAudioOutput('speaker');
    } catch (_) {
      unawaited(Helper.setSpeakerphoneOn(true));
    }
  }

  /// Zera tudo que pertence a UMA chamada.
  ///
  /// Chamado dos dois caminhos que encerram uma ligação — o evento
  /// ENDED/FAILED do sip_ua e o `desligar()` daqui. Ter um lugar só evita
  /// que um deles limpe pela metade: `emChamada` depende de `activeCall`
  /// ser nulo, e qualquer campo esquecido vaza para a próxima chamada.
  void _limparEstadoDaChamada() {
    _nomeEntrante = null;
    _numeroEntrante = null;
    _entranteAtendida = false;
    _entranteRecusada = false;
    // Uma intenção de atender que sobrasse aqui faria a PRÓXIMA chamada
    // ser atendida sozinha, sem ninguém tocar em nada.
    _atendimentoPendente = false;
    _videoDoAtendimentoPendente = null;
    _recusaPendente = false;
    cameraDaChamadaUrl = null;
    cameraDaChamadaNome = null;
    mostrandoCamera = false;

    activeCall = null;
    localStream = null;
    remoteStream = null;
    chamadaComVideo = false;
    _ofertaEntranteTemVideoCache = false;
    muted = false;
    altoFalante = false;
    _ultimoDestino = null;
    _nomeDestino = null;
  }

  void desligar() {
    // Mesma corrida de `atender()`, do outro lado: no iPhone dá pra recusar
    // a chamada do push VoIP antes do INVITE chegar. Sem lembrar da recusa,
    // o INVITE chegaria depois e o telefone voltaria a tocar sozinho — uma
    // chamada que o morador já tinha dispensado.
    final chamada = activeCall;
    if (chamada == null) {
      _recusaPendente = true;
    }
    chamada?.hangup();

    // Limpa o estado AQUI, sem esperar o evento ENDED do sip_ua.
    //
    // Confiar nesse evento deixava o app preso: quando a sessão já morreu do
    // lado do sip_ua (resposta 480 do servidor, transporte caído, chamada
    // que terminou com o app em segundo plano), o ENDED nunca chega,
    // `activeCall` continua preenchido e `emChamada` fica true para sempre.
    // A tela de chamada não fecha, o botão de desligar não resolve — e no
    // Android, onde o engine é persistente, nem fechar e reabrir o app
    // adianta: o estado sobrevive junto com o engine. Só "Forçar parada"
    // saía dali.
    //
    // Pedir o hangup é uma gentileza com o outro lado; o encerramento local
    // é decisão nossa e não pode depender de confirmação que talvez nunca
    // venha.
    _limparEstadoDaChamada();
    callState = CallStateEnum.ENDED;
    _entreUnidades = false;

    unawaited(_encerrarChamadaKit());
    notifyListeners();
  }

  void enviarDtmf(String digitos) {
    activeCall?.sendDTMF(digitos);
  }

  /// Assíncrono e realmente aguarda o unregister terminar (não só fechar o
  /// socket) — importante pro handoff com o SipTaskHandler em segundo plano:
  /// se os dois lados registrarem ao mesmo tempo (mesmo que por um instante),
  /// o Asterisk toca a chamada pros dois contatos ao mesmo tempo
  /// (PJSIP_DIAL_CONTACTS/max_contacts>1), cada um criando sua própria
  /// conexão de Telecom — uma delas fica "presa" (nunca é encerrada por
  /// ninguém) e trava o roteamento de áudio do celular até force-stop/
  /// desinstalar. `_helper.stop()` sozinho só fecha o socket, sem mandar
  /// REGISTER Expires:0 — o contato antigo só some do Asterisk depois de até
  /// register_expires (60s), janela grande demais pra evitar essa corrida.
  Future<void> desconectar() async {
    if (_helper.registered) {
      try {
        await _helper.unregister();
      } catch (_) {
        // Best-effort — se a rede já caiu, não tem REGISTER Expires:0 pra
        // mandar mesmo; segue pro stop() abaixo de qualquer jeito.
      }
    }
    _helper.stop();
    _helperIniciado = false;
  }

  @override
  void dispose() {
    _helper.removeSipUaHelperListener(this);
    _callKitSub?.cancel();
    _helper.stop();
    super.dispose();
  }

  @override
  void registrationStateChanged(RegistrationState state) {
    registrationState = state.state ?? RegistrationStateEnum.NONE;
    debugPrint('[Portcall] SIP registro -> ${state.state}');
    if (state.state == RegistrationStateEnum.REGISTRATION_FAILED) {
      lastError = state.cause?.cause?.toString() ?? 'Falha ao registrar.';
      debugPrint('[Portcall] SIP falha de registro: $lastError');
    }
    notifyListeners();
  }

  @override
  void callStateChanged(Call call, CallState state) {
    final entrante = call.session.direction == Direction.incoming;
    final aindaTocando =
        state.state == CallStateEnum.PROGRESS ||
        state.state == CallStateEnum.CALL_INITIATION;

    // Tom de chamada de quem liga: começa quando a ligação sai e para assim
    // que a chamada é atendida ou cai. Só pra chamada que sai daqui — quem
    // RECEBE já ouve o toque do CallKit.
    //
    // Começa tanto no CALL_INITIATION quanto no PROGRESS de propósito: o
    // PROGRESS depende do servidor responder "180 Ringing", e quando ele
    // atalha esse passo o tom nunca começava. O lado nativo ignora o segundo
    // pedido se o tom já estiver saindo, então pedir duas vezes não corta o
    // tom no meio — ver EngineHolder.iniciarRingback().
    if (!entrante) {
      if (state.state == CallStateEnum.CALL_INITIATION ||
          state.state == CallStateEnum.PROGRESS) {
        unawaited(ForegroundService.iniciarTomDeChamada());
      } else if (state.state == CallStateEnum.CONFIRMED ||
          state.state == CallStateEnum.ACCEPTED ||
          state.state == CallStateEnum.ENDED ||
          state.state == CallStateEnum.FAILED) {
        unawaited(ForegroundService.pararTomDeChamada());
      }
    }

    // Confere de novo a cada evento enquanto ainda está tocando (não só uma
    // vez no primeiro evento) — o corpo do INVITE (com "m=video") às vezes
    // ainda não está associado à sessão no exato primeiro callStateChanged,
    // e travar num falso-negativo aí faz atender sem vídeo por engano.
    // Só assume true quando de fato achar "m=video"; nunca volta pra false.
    if (entrante && aindaTocando && !_ofertaEntranteTemVideoCache) {
      final body = call.session.request?.body as String?;
      if (body != null && body.contains('m=video')) {
        _ofertaEntranteTemVideoCache = true;
      }
    }

    // Quem está ligando é outra unidade? Só dá pra saber pelo CALLERID que o
    // servidor montou (ver _prefixoUnidade) — o ramal cru não diz nada.
    // Marcado enquanto ainda toca, pra CallScreen já abrir sem os atalhos
    // de portão em vez de escondê-los depois, na frente do usuário.
    if (entrante && aindaTocando) {
      final nomeOrigem = call.session.remote_identity?.display_name ?? '';
      if (nomeOrigem.startsWith(_prefixoUnidade)) {
        _entreUnidades = true;
      }
    }

    // Antes de qualquer await: a tela de chamada é montada no
    // notifyListeners() do fim deste método, e precisa do nome já aqui.
    if (entrante && aindaTocando) {
      _identificarQuemLiga(call);
    }

    if (entrante && aindaTocando && _callKitId == null) {
      unawaited(_mostrarChamadaEntrante(call));
    }

    // O morador já apertou "atender" na tela do CallKit, mas naquele momento
    // ainda não existia chamada SIP pra responder — acontece no iPhone, onde
    // quem faz o telefone tocar é o push VoIP e o INVITE só chega depois que
    // o app acorda e se registra. Sem isto o atendimento caía no vazio
    // (`activeCall?.answer` num nulo) e a ligação ficava muda dos dois lados.
    if (entrante && aindaTocando && _recusaPendente) {
      _recusaPendente = false;
      activeCall = call;
      call.hangup();
    } else if (entrante && aindaTocando && _atendimentoPendente) {
      _atendimentoPendente = false;
      activeCall = call;
      atender(video: _videoDoAtendimentoPendente);
    }

    if (state.state == CallStateEnum.STREAM && state.stream != null) {
      if (state.originator == Originator.local) {
        localStream = state.stream;
        // Garante que o microfone não fica mudo — visto em campo (e
        // confirmado no app_morador/PortConnect, que não tem esse bug):
        // ligar PARA o app (ramal respondendo via CallKit) saía sem áudio
        // local enquanto ligar DO app funcionava normal. O Android às vezes
        // inicia a faixa de áudio já mutada quando a chamada é atendida
        // pela UI nativa do CallKit (fora do controle do flutter_webrtc/
        // sip_ua) — forçar unmute aqui, assim que a faixa local realmente
        // existe, cobre os dois casos (atender e originar) sem custo.
        for (final track in state.stream!.getAudioTracks()) {
          unawaited(Helper.setMicrophoneMute(false, track));
        }
      } else if (state.originator == Originator.remote) {
        remoteStream = state.stream;
        if (state.video == true) chamadaComVideo = true;
      }
    }

    // Mesma história do unmute acima, agora na saída de áudio: quem ATENDE
    // passa pelo setCallConnected() do CallKit, e o ConnectionService do
    // Telecom redefine a rota pro padrão (fone) DEPOIS de já termos pedido
    // viva-voz em atender() — que roda antes mesmo do answer(), quando
    // ainda não existe áudio nenhum pra rotear. O efeito era assimétrico e
    // confuso: numa chamada de vídeo, quem ligou ouvia no viva-voz e quem
    // atendeu ouvia no fone. Quem origina não passa por CallKit, por isso
    // só o lado que recebe era afetado.
    //
    // CONFIRMED é o primeiro momento em que a chamada está de fato
    // estabelecida (ACK trocado, áudio fluindo) — reaplicar aqui é o que
    // faz a escolha persistir.
    if (state.state == CallStateEnum.CONFIRMED) {
      unawaited(_aplicarSaidaDeAudio());
    }

    activeCall = call;
    callState = state.state;
    if (state.state == CallStateEnum.ENDED ||
        state.state == CallStateEnum.FAILED) {
      // Chamada que chegou, nunca foi atendida e não foi recusada de
      // propósito = perdida. Cobre tanto o tempo esgotado do CallKit quanto
      // quem desistiu e desligou enquanto ainda tocava.
      if (entrante && !_entranteAtendida && !_entranteRecusada) {
        unawaited(_notificarChamadaPerdida());
      }
      _limparEstadoDaChamada();
      _entreUnidades = false;
      unawaited(_encerrarChamadaKit());
    }
    notifyListeners();
  }

  @override
  void transportStateChanged(TransportState state) {
    debugPrint('[Portcall] SIP transporte -> ${state.state}');
    notifyListeners();
  }

  @override
  void onNewMessage(SIPMessageRequest msg) {}

  @override
  void onNewNotify(Notify ntf) {}

  /// Responde ao re-INVITE. Deixar este método vazio — como estava — não é
  /// "ignorar uma renegociação sem importância": é deixar o servidor
  /// esperando uma resposta que nunca chega.
  ///
  /// O sip_ua só processa o SDP e entrega o evento; quem responde é o app,
  /// chamando `accept` (ou `reject`). Sem isso o Asterisk recebia o nosso
  /// "100 Trying" e mais nada, e a transação INVITE ficava pendente no
  /// diálogo para sempre.
  ///
  /// O estrago aparecia longe daqui: pelo RFC 3261 não se manda BYE com uma
  /// transação INVITE pendente, então quando o visitante desligava no
  /// interfone o Asterisk NÃO conseguia avisar o app. A ligação continuava
  /// aberta no celular — microfone, câmera, dados e bateria — até o Timer B
  /// do SIP estourar, 32 segundos depois. Confirmado no log do servidor: o
  /// re-INVITE sai às 12:20:48, recebe o 100 Trying, e a resposta final
  /// nunca vem.
  ///
  /// Só acontecia em chamada de VÍDEO porque é só nela que o Asterisk
  /// renegocia a topologia ao atender (áudio puro não gera re-INVITE) — foi
  /// o que fez o problema parecer, por um tempo, coisa de iPhone.
  @override
  void onNewReinvite(ReInvite event) {
    final aceitar = event.accept;
    if (aceitar == null) return;
    debugPrint(
      '[Portcall] re-INVITE recebido (áudio: ${event.hasAudio}, '
      'vídeo: ${event.hasVideo}) — respondendo',
    );
    unawaited(
      aceitar(<String, dynamic>{}).catchError((Object e) {
        debugPrint('[Portcall] falha ao responder re-INVITE: $e');
        return false;
      }),
    );
  }
}
