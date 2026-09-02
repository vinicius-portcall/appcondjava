import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:sip_ua/sip_ua.dart';
import 'package:uuid/uuid.dart';

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
        atender();
      case CallEventActionCallDecline():
      case CallEventActionCallTimeout():
        desligar();
      default:
        break;
    }
  }

  Future<void> _mostrarChamadaEntrante(Call call) async {
    _callKitId = _uuid.v4();
    final remoteId = call.session.remote_identity;
    final numero = remoteId?.uri?.user;
    final nome = (remoteId?.display_name?.isNotEmpty == true)
        ? remoteId!.display_name!
        : (numero ?? 'Desconhecido');
    await FlutterCallkitIncoming.showCallkitIncoming(
      CallKitParams(
        id: _callKitId!,
        nameCaller: nome,
        appName: 'Portcall',
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
      ),
    );
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

  Future<void> conectar(SipAccount conta) async {
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
      ..userAgent = 'PortcallApp'
      ..dtmfMode = DtmfMode.RFC2833
      ..register = true
      // Curto de propósito: o transporte TCP do sip_ua não manda nenhum
      // keepalive entre um REGISTER e outro, e o mapeamento de NAT de rede
      // móvel costuma cair bem antes de 300s, deixando o app "registrado"
      // mas com a conexão de verdade morta (chamada entrante cai no vazio).
      ..register_expires = 60;

    await _helper.start(settings);
  }

  Future<bool> ligarPara(String destino, {bool video = false}) async {
    chamadaComVideo = video;
    muted = false;
    _ultimoDestino = destino;
    // Com vídeo, não dá pra ver a tela com o telefone no ouvido — liga o
    // viva-voz (ou fone bluetooth, se tiver um conectado) de cara. Sem
    // vídeo, começa no fone de ouvido normal (igual ligação de telefone
    // comum) — o usuário decide se quer viva-voz pelo botão na tela.
    altoFalante = video;
    unawaited(
      video
          ? Helper.setSpeakerphoneOnButPreferBluetooth()
          : Helper.setSpeakerphoneOn(false),
    );
    return _helper.call(destino, voiceOnly: !video);
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
  void alternarAltoFalante() {
    altoFalante = !altoFalante;
    unawaited(Helper.setSpeakerphoneOn(altoFalante));
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
    final comVideo = video ?? ofertaEntranteTemVideo;
    chamadaComVideo = comVideo;
    muted = false;
    _ultimoDestino = null;
    altoFalante = comVideo;
    unawaited(
      comVideo
          ? Helper.setSpeakerphoneOnButPreferBluetooth()
          : Helper.setSpeakerphoneOn(false),
    );
    activeCall?.answer(_helper.buildCallOptions(!comVideo));
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

  void desligar() {
    activeCall?.hangup();
    localStream = null;
    remoteStream = null;
    unawaited(_encerrarChamadaKit());
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
    if (state.state == RegistrationStateEnum.REGISTRATION_FAILED) {
      lastError = state.cause?.cause?.toString() ?? 'Falha ao registrar.';
    }
    notifyListeners();
  }

  @override
  void callStateChanged(Call call, CallState state) {
    final entrante = call.session.direction == Direction.incoming;
    final aindaTocando =
        state.state == CallStateEnum.PROGRESS ||
        state.state == CallStateEnum.CALL_INITIATION;

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

    if (entrante && aindaTocando && _callKitId == null) {
      unawaited(_mostrarChamadaEntrante(call));
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

    activeCall = call;
    callState = state.state;
    if (state.state == CallStateEnum.ENDED ||
        state.state == CallStateEnum.FAILED) {
      activeCall = null;
      localStream = null;
      remoteStream = null;
      chamadaComVideo = false;
      _ofertaEntranteTemVideoCache = false;
      muted = false;
      altoFalante = false;
      _ultimoDestino = null;
      unawaited(_encerrarChamadaKit());
    }
    notifyListeners();
  }

  @override
  void transportStateChanged(TransportState state) {
    notifyListeners();
  }

  @override
  void onNewMessage(SIPMessageRequest msg) {}

  @override
  void onNewNotify(Notify ntf) {}

  @override
  void onNewReinvite(ReInvite event) {}
}
