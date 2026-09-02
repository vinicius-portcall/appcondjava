# 4. Chamadas em segundo plano e CallKit

Arquivos principais: `lib/services/foreground_service.dart`, `lib/services/sip_service.dart` (integração com `flutter_callkit_incoming`), e do lado nativo Android: `android/app/src/main/kotlin/br/com/portcall/portcall_app/EngineHolder.kt`, `PersistentEngineService.kt`, `RestartReceiver.kt`, `MainActivity.kt`.

O app soluciona dois problemas distintos de Android quando o assunto é "ficar disponível para receber chamadas (com vídeo) mesmo com o app minimizado, com a tela apagada ou fechado":

1. **Manter o mesmo `SipService` (registro SIP + WebRTC) vivo**, mesmo depois do Android matar a `MainActivity`.
2. **Mostrar a UI de chamada recebida** mesmo com o app em segundo plano ou com a tela bloqueada.

## Manter o app vivo: um único FlutterEngine persistente

Diferente de uma versão anterior (baseada no pacote `flutter_foreground_task`, que rodava um **isolate/FlutterEngine totalmente separado** em segundo plano, com seu próprio `SIPUAHelper` independente da tela principal — por isso só atendia em áudio, nunca vídeo, já que não existe como transferir uma `RTCPeerConnection`/`MediaStream` viva entre dois engines diferentes), a arquitetura atual mantém **o próprio engine principal do app vivo**, com ou sem `Activity` anexada:

- `EngineHolder.kt` (`getOrCreateEngine`) — cria (ou reaproveita, via `FlutterEngineCache` com id fixo `"persistent_engine"`) um único `FlutterEngine`, rodando o `main()` normal do app (`DartExecutor.DartEntrypoint.createDefault()`). Também registra um `MethodChannel` (`portcall/persistent_service`) usado pelo lado Dart (`ForegroundService`) para pedir pra iniciar/parar o serviço de segundo plano e checar/pedir isenção de otimização de bateria.
- `MainActivity.kt` — em vez de deixar o framework criar um engine novo por conta própria, `provideFlutterEngine()` retorna o mesmo engine cacheado. Isso significa que o app **não reinicia** (nem perde estado — `HomeScreen`, `SipService`, ligação em andamento etc.) quando a Activity é destruída e recriada pelo Android; ela só volta a "desenhar" a mesma árvore de widgets que já estava rodando.
- `PersistentEngineService.kt` — Service Android nativo (tipo `phoneCall`) que só existe pra manter esse engine vivo quando não tem nenhuma Activity em primeiro plano: notificação persistente (canal `portcall_sip_channel`), `PARTIAL_WAKE_LOCK`, `START_STICKY`. Não tem nenhuma lógica de SIP aqui — é só "segurar o processo".
- `RestartReceiver.kt` — se o Android matar o Service sem ter sido um `stop()` deliberado (logout), agenda um restart via `AlarmManager` (`onDestroy`/`onTaskRemoved`).

Do lado Dart, `ForegroundService` (`lib/services/foreground_service.dart`) só conversa com esse Service via `MethodChannel`:

- `ensureNotificationPermission()` — pede a permissão de notificação (Android 13+) via `permission_handler`.
- `start({required String ramal})` — garante a permissão e chama `'start'` no canal (mostra a notificação com o número do ramal).
- `stop()` — chama `'stop'` (usado no logout).
- `requestIgnoreBatteryOptimizations()` — checa e, se necessário, pede isenção de otimização de bateria.

Chamado em `HomeScreen._iniciar()`, depois de carregar branding/botões e antes de `SipService.conectar()`. Como só existe **um** `SipService`, sempre o mesmo objeto, não tem handoff de registro entre dois lados pra fazer — o app é o app, com ou sem tela visível.

### Permissões que exigem Activity

`Permission.microphone.request()`/`.camera.request()` (e `SipService.solicitarPermissaoTelaCheia()`, via `flutter_callkit_incoming`) exigem uma `Activity` anexada — lançam erro se chamadas num engine rodando "de cabeça fria" em segundo plano (cenário raro: o processo inteiro morreu e o `PersistentEngineService` reiniciou sozinho antes do usuário abrir o app de novo nesse boot). `HomeScreen._pedirPermissoesDeMidia()` engole esse erro pra não travar o resto de `_iniciar()` — sem isso, `SipService.conectar()` nunca rodaria e o ramal ficaria sem registro.

## Notificação nativa de chamada: `flutter_callkit_incoming`

Quando uma chamada SIP entrante é detectada (`SipService.callStateChanged`, direção `incoming`, estado inicial e ainda sem notificação disparada), `_mostrarChamadaEntrante(call)` é chamado:

- Gera um `id` único (`uuid.v4()`) para essa chamada, guardado em `_callKitId`.
- Extrai nome/número de quem chama a partir da identidade remota SIP (`display_name` se houver, senão o número/usuário).
- Chama `FlutterCallkitIncoming.showCallkitIncoming(...)`, exibindo a UI nativa de chamada recebida do Android (funciona com tela bloqueada), com textos "Atender"/"Recusar", 30s de timeout, cor de fundo azul e cor de ação amarela (mesma paleta do app), tocando o toque padrão do sistema.

O app escuta os eventos dessa UI nativa via `FlutterCallkitIncoming.onEvent` (assinado no construtor do `SipService`):

| Evento nativo | Ação no app |
|---|---|
| `actionCallAccept` | chama `atender()` (decide áudio/vídeo pela oferta SDP, já que o usuário aceitou pela notificação nativa, sem abrir a `CallScreen` antes) |
| `actionCallDecline` / `actionCallTimeout` | chama `desligar()` |

Quando a chamada é atendida (`atender()`) ou encerrada (`desligar()` / estado `ENDED`/`FAILED`), `_encerrarChamadaKit()` chama `FlutterCallkitIncoming.endCall(id)` para remover a notificação/UI nativa correspondente.

Como o engine é sempre o mesmo, atender uma chamada de vídeo pela notificação nativa com o app fechado funciona igual a atender com o app aberto: `HomeScreen._onSipChange` detecta `_sip.emChamada` e empurra a `CallScreen` automaticamente assim que alguma Activity for aberta — a sessão WebRTC (áudio e vídeo) já está rodando no mesmo `SipService` que a tela lê.

## Por que as duas coisas são necessárias

- Sem o `PersistentEngineService`, o Android mata o processo (e o `SipService`/registro SIP) pouco depois da `Activity` ser destruída.
- Sem o `flutter_callkit_incoming`, mesmo com o processo vivo, não haveria uma forma padrão de mostrar a tela de "chamada recebida" com o aparelho bloqueado — o usuário só veria a chamada se abrisse o app manualmente.
