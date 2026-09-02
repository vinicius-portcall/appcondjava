# 7. Permissões e configuração de plataforma

## Permissões em runtime (Dart, via `permission_handler`)

Solicitadas explicitamente pelo código Dart:

| Permissão | Onde é pedida | Comportamento se negada |
|---|---|---|
| Microfone | `HomeScreen._iniciar()` | mostra aviso (SnackBar de 6s) de que chamadas não vão funcionar; app continua |
| Câmera | `HomeScreen._iniciar()` | resultado não é tratado explicitamente (necessária para chamadas de vídeo) |
| Notificações (Android 13+) | `ForegroundService.ensureNotificationPermission()` | sem essa permissão a notificação do serviço em primeiro plano pode não aparecer |

## Permissões declaradas no Android (`android/app/src/main/AndroidManifest.xml`)

| Permissão | Motivo |
|---|---|
| `INTERNET`, `ACCESS_NETWORK_STATE` | comunicação com o painel HTTP e o servidor SIP |
| `RECORD_AUDIO`, `MODIFY_AUDIO_SETTINGS` | captura de áudio para chamadas (WebRTC) |
| `CAMERA` | chamadas de vídeo |
| `BLUETOOTH` (até SDK 30) / `BLUETOOTH_CONNECT` | roteamento de áudio para fones/dispositivos Bluetooth durante a chamada |
| `WAKE_LOCK` | manter a CPU ativa durante chamadas / serviço em primeiro plano |
| `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC` | serviço em primeiro plano (`flutter_foreground_task`) que mantém o registro SIP vivo |
| `POST_NOTIFICATIONS` | notificação persistente do serviço em primeiro plano e notificação de chamada recebida |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | pedir ao usuário para excluir o app da otimização de bateria |
| `USE_FULL_SCREEN_INTENT` | exibir a UI de chamada recebida (CallKit) por cima da tela de bloqueio |

## Configuração da `MainActivity`

No `AndroidManifest.xml`, a activity principal usa:

- `launchMode="singleInstance"` e `taskAffinity=""` — evita múltiplas instâncias e isola a task, importante para a UI de chamada abrir de forma consistente mesmo vindo de uma notificação/CallKit.
- `showWhenLocked="true"` e `turnScreenOn="true"` — permite abrir o app (tela de chamada) por cima da tela de bloqueio e ligar a tela automaticamente ao receber uma chamada.

Há também um `<service>` registrado explicitamente para o `flutter_foreground_task` (`com.pravera.flutter_foreground_task.service.ForegroundService`, `foregroundServiceType="dataSync"`) — o comentário no manifesto avisa para **não renomear** esse serviço, pois o nome é referenciado internamente pelo plugin.

## Identificação do app

- `applicationId` / `namespace` Android: `br.com.portcall.portcall_app`.
- Nome do pacote Dart/Flutter: `portcall_app`.
- SDK Dart: `^3.12.2` (ver `pubspec.yaml`).

## Plataformas com projeto gerado

O repositório contém os projetos de todas as plataformas Flutter padrão (`android/`, `ios/`, `linux/`, `macos/`, `windows/`, `web/`), mas as permissões e integrações nativas específicas (CallKit, foreground service, Bluetooth) descritas acima só foram configuradas/verificadas para **Android**. Não há evidência no código de configuração equivalente para iOS (ex.: `Info.plist` para CallKit/PushKit nativo do iOS) além do bridging header padrão gerado pelo Flutter.
