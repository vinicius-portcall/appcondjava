# 3. Chamadas SIP (voz e vídeo)

Arquivos principais: `lib/services/sip_service.dart`, `lib/screens/call_screen.dart`, pacotes `sip_ua` e `flutter_webrtc`.

## `SipService`

`SipService` é um `ChangeNotifier` que encapsula o `SIPUAHelper` do pacote `sip_ua` e implementa `SipUaHelperListener` para reagir a eventos da pilha SIP. É instanciado uma vez por sessão de uso, em `HomeScreen.initState()`, e compartilhado (via construtor) com as telas que precisam originar ou controlar chamadas (`CallScreen`, `ApartamentosScreen`, `DialpadScreen`).

### Estado exposto

| Propriedade | Significado |
|---|---|
| `registrationState` | estado do registro SIP (`REGISTERED`, `REGISTRATION_FAILED`, `UNREGISTERED`, etc.) |
| `isRegistered` | atalho para `registrationState == REGISTERED` |
| `activeCall` / `callState` | chamada em andamento e seu estado (`CALL_INITIATION`, `PROGRESS`, `CONFIRMED`, `ENDED`, `FAILED`...) |
| `emChamada` | `true` quando há `activeCall` e o estado não é `ENDED`/`FAILED` |
| `localStream` / `remoteStream` | streams de mídia WebRTC (áudio/vídeo) local e remoto |
| `chamadaComVideo` | se a chamada atual é (ou deve ser) com vídeo |
| `lastError` | última causa de falha de registro |

## Registro no servidor

`conectar(SipAccount conta)` monta um `UaSettings` e chama `_helper.start(settings)`:

- **Transporte fixo em TCP** (`TransportType.TCP`), usando `servidor`/`porta` da conta. Há um comentário no código indicando que, se o Asterisk migrar para PJSIP/WSS, basta trocar para `TransportType.WS` + `webSocketUrl`.
- `uri` montado como `ramal@servidor`, autenticação com `authorizationUser`/`password` do ramal.
- `register: true`, `register_expires: 300` (renovação a cada 5 minutos, controlada internamente pelo `sip_ua`).
- `userAgent: 'PortcallApp'`, DTMF em modo `RFC2833`.

Mudanças de estado do registro chegam em `registrationStateChanged()`, que atualiza `registrationState` (e `lastError` em caso de falha) e notifica os listeners — é isso que a `HomeScreen` usa para mostrar o indicador "Online / Conectando… / Falha ao conectar / Desconectado".

## Originando uma chamada

`ligarPara(String destino, {bool video = false})` chama `_helper.call(destino, voiceOnly: !video)`. É usado em três lugares:

- Botões de discagem configurados pelo condomínio (`AppButton` do tipo `discar`, na grade da `HomeScreen`).
- `ApartamentosScreen`, ao tocar em ligar/vídeo para uma unidade da lista.
- `DialpadScreen`, para qualquer número digitado manualmente.

Em todos os casos, antes de discar é checado `sip.isRegistered`; se ainda não estiver registrado, é exibido um aviso e a chamada não é iniciada.

## Recebendo uma chamada

Eventos de chamada chegam em `callStateChanged(Call call, CallState state)`:

- Quando detecta uma chamada **entrante nova** (`direction == incoming`, estado `PROGRESS`/`CALL_INITIATION` e ainda sem notificação nativa disparada), chama `_mostrarChamadaEntrante()`, que aciona o CallKit (ver [documento 4](04-segundo-plano-e-callkit.md)).
- Ao receber um evento de estado `STREAM`, associa o stream ao `localStream` ou `remoteStream` conforme o `Originator` (local/remoto); se o stream remoto vier com vídeo, marca `chamadaComVideo = true`.
- Ao atingir `ENDED`/`FAILED`, limpa `activeCall`, os streams e `chamadaComVideo`, e encerra a notificação nativa da chamada.

`ofertaEntranteTemVideo` inspeciona o corpo SDP da requisição de convite (`activeCall?.session.request?.body`) procurando `m=video`, para saber se a chamada entrante oferece vídeo — usado tanto para decidir o áudio/vídeo ao atender via CallKit quanto para mostrar as opções "Sem vídeo / Com vídeo" na `CallScreen`.

### Atender e desligar

- `atender({bool? video})`: se `video` não for informado (ex.: aceite pela tela de bloqueio via CallKit), usa `ofertaEntranteTemVideo` para decidir sozinho; caso contrário respeita a escolha explícita do usuário na `CallScreen`. Chama `activeCall.answer(...)` com as opções de mídia adequadas e confirma a chamada no CallKit.
- `desligar()`: encerra a chamada ativa (`hangup()`), limpa os streams locais e encerra a notificação do CallKit.

### DTMF

`enviarDtmf(String digitos)` envia tons DTMF na chamada ativa. É usado para:
- o teclado numérico dentro da `CallScreen` (`showModalBottomSheet` com teclas de 0–9, `*`, `#`);
- os botões de "portão" (`AppButton` do tipo `dtmf`) mostrados na `CallScreen` durante a chamada — cada botão dispara uma sequência DTMF fixa (`dtmfDigitos`) configurada pelo painel do condomínio.

## Tela de chamada (`CallScreen`)

Recebe `SipService`, a lista de botões DTMF disponíveis (`botoesDtmf`), se a chamada é entrante (`chamadaEntrante`) e, desde o módulo Histórico de Acessos, também `ApiService`/`SipAccount` (`api`/`conta`, obrigatórios) — só usados para registrar o acionamento de portão, não para originar a chamada em si:

- Inicializa dois `RTCVideoRenderer` (local e remoto) e os associa aos streams do `SipService` sempre que eles mudam.
- Mostra vídeo remoto em tela cheia e um preview local (espelhado) no canto superior direito quando `chamadaComVideo` é verdadeiro e há stream remoto; caso contrário, mostra um ícone de pessoa (chamada de voz).
- Enquanto aguarda o usuário atender uma chamada entrante com oferta de vídeo, mostra dois botões — "Sem vídeo" e "Com vídeo" — que chamam `atender(video: false/true)` explicitamente.
- Mostra os botões de portão (DTMF) e o botão de teclado numérico apenas quando não está mais aguardando atendimento.
- `_abrirPortao(b)` envia o DTMF **e** chama `ApiService.registrarAcessoPortao(ramal, senha, b.nome)` em paralelo (`unawaited`, erro engolido com `.catchError((_) {})`) — grava no histórico de acessos (ver [documento 6](06-integracao-com-o-painel.md)). O registro é "melhor esforço": se a chamada à API falhar, o portão já foi aberto mesmo assim, então não faz sentido travar a UI ou avisar o morador de um erro no log.
- Assina o `SipService` e, assim que `emChamada` se torna falso (chamada encerrada por qualquer lado), faz `Navigator.maybePop()` para fechar a tela automaticamente.
