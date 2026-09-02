import 'dart:async';

import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:sip_ua/sip_ua.dart';
import 'package:uuid/uuid.dart';

import 'session_service.dart';

/// Ponto de entrada do isolate do serviço de segundo plano — precisa ser uma
/// função top-level (fora de classe) com esse pragma, senão o
/// flutter_foreground_task não consegue re-invocar depois que o Android
/// mata e recria o processo.
@pragma('vm:entry-point')
void iniciarSipTaskHandler() {
  FlutterForegroundTask.setTaskHandler(SipTaskHandler());
}

/// Mantém o ramal registrado e atende chamadas (só áudio) quando o app está
/// minimizado/fechado — roda no isolate próprio do flutter_foreground_task,
/// sem acesso ao SipService da tela principal. home_screen.dart cede o
/// controle pra cá (`connect`) quando o app sai de primeiro plano, e retoma
/// (`disconnect`) quando volta — só um lado fica registrado por vez, pra não
/// tocar duas notificações de chamada ao mesmo tempo.
///
/// Sem vídeo e sem teclado DTMF aqui (não tem tela pra isso) — quem quiser
/// vídeo ou abrir o portão durante uma chamada atendida em segundo plano
/// precisa abrir o app; a ligação continua rolando enquanto isso.
class SipTaskHandler extends TaskHandler implements SipUaHelperListener {
  final SIPUAHelper _helper = SIPUAHelper();
  final Uuid _uuid = const Uuid();

  StreamSubscription<CallEvent?>? _callKitSub;
  String? _callKitId;
  Call? _activeCall;
  bool _conectado = false;
  bool _handoffPendente = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _helper.addSipUaHelperListener(this);
    _callKitSub = FlutterCallkitIncoming.onEvent.listen(_onCallKitEvent);
  }

  Future<void> _conectar() async {
    if (_conectado) {
      FlutterForegroundTask.sendDataToMain({'ack': 'connected'});
      return;
    }
    final conta = await SessionService().load();
    if (conta == null) {
      // Sem conta salva não tem como registrar — ainda manda o ack, senão
      // o lado principal fica esperando pra sempre até o timeout.
      FlutterForegroundTask.sendDataToMain({'ack': 'connected'});
      return;
    }

    final settings = UaSettings()
      // Mesmo transporte usado em sip_service.dart — ver o comentário lá
      // pra entender por que WSS (não TCP) é o transporte certo pro
      // endpoint webrtc=yes do painel.
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
      ..register_expires = 60;

    await _helper.start(settings);
    _conectado = true;
    FlutterForegroundTask.sendDataToMain({'ack': 'connected'});
  }

  /// Aguarda o unregister de verdade (REGISTER Expires:0) antes de fechar o
  /// socket — não é só limpeza, é o que impede o SipService da tela
  /// principal de registrar em cima de um contato nosso ainda vivo no
  /// Asterisk (ver o mesmo comentário em SipService.desconectar()).
  Future<void> _desconectar() async {
    if (!_conectado) {
      FlutterForegroundTask.sendDataToMain({'ack': 'disconnected'});
      return;
    }
    // Ligação em andamento (atendida em segundo plano, sem tela) — nunca
    // derrubar aqui. Isso já aconteceu na prática: reabrir o app durante uma
    // ligação em segundo plano mandava 'disconnect' incondicionalmente,
    // matando a chamada bem no momento em que o usuário tentava voltar pra
    // ela. Fica marcado pendente; callStateChanged termina o handoff sozinho
    // assim que a ligação acabar.
    if (_activeCall != null) {
      _handoffPendente = true;
      FlutterForegroundTask.sendDataToMain({'ack': 'ocupado'});
      return;
    }
    if (_helper.registered) {
      try {
        await _helper.unregister();
      } catch (_) {
        // Best-effort — segue pro stop() abaixo de qualquer jeito.
      }
    }
    _helper.stop();
    _conectado = false;
    FlutterForegroundTask.sendDataToMain({'ack': 'disconnected'});
  }

  @override
  void onReceiveData(Object data) {
    if (data is! Map) return;
    switch (data['cmd']) {
      case 'connect':
        unawaited(_conectar());
        break;
      case 'disconnect':
        unawaited(_desconectar());
        break;
      case 'hangup':
        _desligar();
        break;
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    await _callKitSub?.cancel();
    _helper.removeSipUaHelperListener(this);
    _desconectar();
  }

  void _onCallKitEvent(CallEvent? event) {
    switch (event) {
      case CallEventActionCallAccept():
        _atender();
      case CallEventActionCallDecline():
      case CallEventActionCallTimeout():
        _desligar();
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

  /// NÃO zera _callKitId aqui — é o mesmo id da conexão de Telecom de
  /// verdade, ainda precisado quando a ligação terminar de vez pra chamar
  /// endCall() (ver o mesmo comentário em SipService._esconderChamadaKit()).
  Future<void> _esconderChamadaKit() async {
    final id = _callKitId;
    if (id == null) return;
    await FlutterCallkitIncoming.hideCallkitIncoming(CallKitParams(id: id));
  }

  Future<void> _encerrarChamadaKit() async {
    final id = _callKitId;
    if (id == null) return;
    _callKitId = null;
    await FlutterCallkitIncoming.endCall(id);
  }

  void _atender() {
    // Sempre só áudio aqui — sem tela pra escolher vídeo em segundo plano.
    // Fone de ouvido normal por padrão (mesmo comportamento de
    // sip_service.dart) — sem isso o Android decide sozinho a rota, e nem
    // sempre escolhe o fone.
    unawaited(Helper.setSpeakerphoneOn(false));
    _activeCall?.answer(_helper.buildCallOptions(true));
    final id = _callKitId;
    if (id != null) {
      unawaited(FlutterCallkitIncoming.setCallConnected(id));
    }
    unawaited(_esconderChamadaKit());
  }

  void _desligar() {
    _activeCall?.hangup();
    unawaited(_encerrarChamadaKit());
  }

  @override
  void registrationStateChanged(RegistrationState state) {}

  @override
  void callStateChanged(Call call, CallState state) {
    final entrante = call.session.direction == Direction.incoming;
    final aindaTocando =
        state.state == CallStateEnum.PROGRESS ||
        state.state == CallStateEnum.CALL_INITIATION;

    if (entrante && aindaTocando && _callKitId == null) {
      _activeCall = call;
      unawaited(_mostrarChamadaEntrante(call));
    }

    // Mesmo fix de sip_service.dart: o Android às vezes inicia a faixa de
    // áudio local já mutada quando a chamada é atendida pela UI nativa do
    // CallKit — aqui é onde isso mais importa, já que chamada entrante em
    // segundo plano é sempre atendida assim (sem tela pra mutar/desmutar
    // manualmente).
    if (state.state == CallStateEnum.STREAM &&
        state.stream != null &&
        state.originator == Originator.local) {
      for (final track in state.stream!.getAudioTracks()) {
        unawaited(Helper.setMicrophoneMute(false, track));
      }
    }

    if (state.state == CallStateEnum.ENDED ||
        state.state == CallStateEnum.FAILED) {
      _activeCall = null;
      unawaited(_encerrarChamadaKit());
      if (_handoffPendente) {
        _handoffPendente = false;
        unawaited(_desconectar());
      }
    }
  }

  @override
  void transportStateChanged(TransportState state) {}

  @override
  void onNewMessage(SIPMessageRequest msg) {}

  @override
  void onNewNotify(Notify ntf) {}

  @override
  void onNewReinvite(ReInvite event) {}
}
