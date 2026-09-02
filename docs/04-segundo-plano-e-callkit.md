# 4. Chamadas em segundo plano e CallKit

Arquivos principais: `lib/services/foreground_service.dart`, `lib/services/sip_service.dart` (integração com `flutter_callkit_incoming`).

O app soluciona dois problemas distintos de Android quando o assunto é "ficar disponível para receber chamadas mesmo com o app minimizado ou a tela apagada":

1. **Manter o registro SIP vivo** (o socket TCP e o timer de re-registro não podem ser mortos pelo gerenciador de energia).
2. **Mostrar a UI de chamada recebida** mesmo com o app em segundo plano ou com a tela bloqueada.

## Manter o app vivo: `ForegroundService`

Encapsula o pacote `flutter_foreground_task`. Métodos:

- `init()` — configura o canal de notificação Android (`portcall_sip_channel`, importância baixa, "Conexão SIP"), desativa notificação no iOS (`showNotification: false`) e habilita `allowWakeLock`/`allowWifiLock`. É idempotente (`_initialized` evita reconfigurar).
- `ensureNotificationPermission()` — solicita permissão de notificação em runtime (Android 13+) se ainda não concedida.
- `start({required String ramal})` — inicializa, garante a permissão, e inicia o serviço em primeiro plano com uma notificação persistente ("Portcall conectado — Ramal X — online"). Não faz nada se o serviço já estiver rodando.
- `stop()` — para o serviço, se estiver rodando.
- `requestIgnoreBatteryOptimizations()` — pede ao usuário para ignorar a otimização de bateria do Android para o app (reduz a chance do sistema encerrar o processo).

Esse serviço é iniciado em `HomeScreen._iniciar()`, logo depois de carregar branding/botões e antes de `SipService.conectar()`. Se o início falhar (ex.: permissão negada), o erro é silenciado — o registro SIP continua funcionando em primeiro plano mesmo sem o serviço de background, então uma falha aqui não deve travar o login.

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

## Por que as duas coisas são necessárias

- Sem o `ForegroundService`, o Android pode suspender o processo do app (e o socket SIP registrado) pouco depois de minimizado, fazendo o ramal cair.
- Sem o `flutter_callkit_incoming`, mesmo com o processo vivo, não haveria uma forma padrão de mostrar a tela de "chamada recebida" com o aparelho bloqueado — o usuário só veria a chamada se abrisse o app manualmente.
