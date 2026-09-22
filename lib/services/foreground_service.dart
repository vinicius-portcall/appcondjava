import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Mantém o app vivo em segundo plano (tela apagada / minimizado / fechado)
/// através de um Service Android nativo (`PersistentEngineService`) que
/// segura vivo o MESMO FlutterEngine da tela principal — ver
/// `EngineHolder.kt`/`MainActivity.provideFlutterEngine()`. Diferente da
/// versão anterior (baseada no pacote flutter_foreground_task), não existe
/// mais um isolate/engine separado nem handoff de registro entre dois
/// `SIPUAHelper`: o `SipService` é sempre o mesmo objeto, sempre registrado,
/// com ou sem tela visível — inclusive vídeo funciona numa ligação atendida
/// com o app fechado, já que é a mesma sessão WebRTC que a `CallScreen` lê.
class ForegroundService {
  static const _channel = MethodChannel('portcall/persistent_service');

  static Future<void> ensureNotificationPermission() async {
    final status = await Permission.notification.status;
    if (!status.isGranted) {
      await Permission.notification.request();
    }
  }

  static Future<void> start({required String ramal}) async {
    await ensureNotificationPermission();
    await _channel.invokeMethod('start', {'ramal': ramal});
  }

  static Future<void> stop() async {
    await _channel.invokeMethod('stop');
  }

  static Future<void> requestIgnoreBatteryOptimizations() async {
    final ignorando =
        await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ??
        true;
    if (!ignorando) {
      await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
    }
  }

  /// Abre a tela de detalhes do app nas configurações do Android — de lá
  /// dá pra chegar em "Bateria" e escolher "Sem restrições". Em aparelhos
  /// Samsung existe uma camada de gerenciamento de bateria própria (One UI)
  /// que pode limitar o app em segundo plano mesmo já isento do Doze padrão
  /// do Android (o que `requestIgnoreBatteryOptimizations` acima cobre) —
  /// não tem Intent direta pra essa tela específica em todo fabricante, a
  /// tela de detalhes do app é o caminho universal.
  static Future<void> abrirConfiguracoesBateria() async {
    await _channel.invokeMethod('openBatterySettings');
  }
}
