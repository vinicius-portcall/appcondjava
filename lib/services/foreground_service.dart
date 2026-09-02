import 'dart:async';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'sip_task_handler.dart';

/// Mantém o app vivo em segundo plano (tela apagada / app minimizado) com
/// uma notificação persistente, para que o registro SIP não seja derrubado
/// pelo gerenciamento de energia do Android.
class ForegroundService {
  static bool _initialized = false;

  static void init() {
    if (_initialized) return;
    _initialized = true;

    // Necessário pro SipTaskHandler (isolate de segundo plano) conseguir
    // avisar de volta quando terminou de conectar/desconectar de verdade —
    // sem isso, assumirSip()/devolverSip() não tem como saber quando é
    // seguro deixar o outro lado registrar (ver o comentário grande em
    // SipService.desconectar()).
    FlutterForegroundTask.initCommunicationPort();

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'portcall_sip_channel',
        channelName: 'Conexão SIP',
        channelDescription: 'Mantém o ramal registrado em segundo plano.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  static Future<void> ensureNotificationPermission() async {
    final permission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (permission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
  }

  static Future<void> start({required String ramal}) async {
    init();
    await ensureNotificationPermission();
    if (await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.startService(
      notificationTitle: 'Portcall conectado',
      notificationText: 'Ramal $ramal — online',
      callback: iniciarSipTaskHandler,
    );
  }

  static Future<void> stop() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }

  static Future<void> requestIgnoreBatteryOptimizations() async {
    final ignoring = await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    if (!ignoring) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
  }

  /// Manda um comando pro SipTaskHandler e espera o "ack" de volta (mensagem
  /// {'ack': ackEsperado} via sendDataToMain) antes de retornar — timeout
  /// curto como rede de segurança caso o serviço não esteja rodando (ex:
  /// ForegroundService.start() nunca foi chamado) e a mensagem se perca no
  /// vazio, senão quem chama ficaria esperando pra sempre.
  static Future<void> _enviarComandoEAguardarAck(
    Map<String, String> comando,
    String ackEsperado,
  ) {
    final completer = Completer<void>();
    late void Function(Object) callback;
    callback = (Object data) {
      if (data is Map && data['ack'] == ackEsperado) {
        FlutterForegroundTask.removeTaskDataCallback(callback);
        if (!completer.isCompleted) completer.complete();
      }
    };
    FlutterForegroundTask.addTaskDataCallback(callback);
    FlutterForegroundTask.sendDataToTask(comando);
    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => FlutterForegroundTask.removeTaskDataCallback(callback),
    );
  }

  /// Chamado quando o app sai de primeiro plano — o SipTaskHandler assume o
  /// registro SIP (áudio, sem tela) pra continuar recebendo chamada mesmo se
  /// o Android matar o app depois. Só retorna depois que o SipTaskHandler
  /// confirma que terminou de registrar — quem chama deve aguardar isso
  /// ANTES de considerar o handoff completo (ver SipService.desconectar()
  /// pra entender por que registro duplicado é um problema sério, não só
  /// cosmético).
  static Future<void> assumirSip() =>
      _enviarComandoEAguardarAck({'cmd': 'connect'}, 'connected');

  /// Chamado quando o app volta pra primeiro plano — devolve o registro SIP
  /// pro SipService da tela principal (que tem vídeo/DTMF/etc). Retorna
  /// `true` quando o SipTaskHandler já desregistrou de vez (REGISTER
  /// Expires:0, não só fechou o socket) — só aí é seguro reconectar o
  /// SipService da tela principal. Retorna `false` quando o SipTaskHandler
  /// recusa porque está com uma ligação em andamento (atendida em segundo
  /// plano) — nesse caso NÃO reconectar o SipService por cima (registro
  /// duplicado trava o roteamento de áudio do celular, já visto acontecer);
  /// [aoLiberarHandoff] avisa sozinho quando essa ligação terminar.
  static Future<bool> devolverSip() {
    final completer = Completer<bool>();
    late void Function(Object) callback;
    callback = (Object data) {
      if (data is! Map) return;
      if (data['ack'] == 'disconnected') {
        FlutterForegroundTask.removeTaskDataCallback(callback);
        if (!completer.isCompleted) completer.complete(true);
      } else if (data['ack'] == 'ocupado') {
        FlutterForegroundTask.removeTaskDataCallback(callback);
        if (!completer.isCompleted) completer.complete(false);
      }
    };
    FlutterForegroundTask.addTaskDataCallback(callback);
    FlutterForegroundTask.sendDataToTask({'cmd': 'disconnect'});
    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        FlutterForegroundTask.removeTaskDataCallback(callback);
        return false;
      },
    );
  }

  static void Function(Object)? _liberacaoCallback;

  /// Registra [aoLiberar] pra disparar toda vez que o SipTaskHandler avisar
  /// 'disconnected' por conta própria — ou seja, quando uma ligação que
  /// tinha recusado devolverSip() (retornou `false`) finalmente termina e o
  /// handoff completa sozinho, sem ninguém esperando ativamente por isso
  /// naquele momento. Chamar de novo substitui o callback anterior (só um
  /// de cada vez, consistente com a tela principal ser praticamente
  /// singleton nesse app).
  static void aoLiberarHandoff(void Function() aoLiberar) {
    pararDeEscutarLiberacao();
    _liberacaoCallback = (data) {
      if (data is Map && data['ack'] == 'disconnected') {
        aoLiberar();
      }
    };
    FlutterForegroundTask.addTaskDataCallback(_liberacaoCallback!);
  }

  static void pararDeEscutarLiberacao() {
    if (_liberacaoCallback != null) {
      FlutterForegroundTask.removeTaskDataCallback(_liberacaoCallback!);
      _liberacaoCallback = null;
    }
  }

  /// Desliga, à distância, a ligação que o SipTaskHandler está segurando em
  /// segundo plano (só áudio) — usado pelo aviso na Home quando o app é
  /// reaberto no meio dessa ligação, já que a tela principal não tem acesso
  /// direto à Call/MediaStream que vive no outro isolate.
  static void desligarChamadaSegundoPlano() {
    FlutterForegroundTask.sendDataToTask({'cmd': 'hangup'});
  }
}
