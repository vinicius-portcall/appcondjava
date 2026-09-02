# CLAUDE.md

Este arquivo fornece orientações ao Claude Code (claude.ai/code) ao trabalhar com código neste repositório.

## Visão geral do projeto

**Portcall** (`portcall_app`) é um app Flutter que funciona como cliente de interfone SIP para condomínios. Ele permite que o celular de um morador se registre como um ramal SIP em um painel PBX baseado em Asterisk, receba/faça chamadas do interfone (áudio ou vídeo), abra portões/portas via DTMF e disque para outras unidades. Strings de UI, comentários e o vocabulário do domínio estão em português (ramal, painel, apartamentos, portão etc.).

Apesar do nome da pasta do repositório (`appcondjava`), este é um app **Flutter/Dart**, não Java. O arquivo `src/Main.java` na raiz é um arquivo de rascunho do IntelliJ, sem uso — não tem alvo de build e não faz parte do app.

## Comandos

Fluxo padrão do Flutter (execute a partir da raiz do repositório):

- Instalar dependências: `flutter pub get`
- Rodar em um dispositivo/emulador conectado: `flutter run`
- Análise estática (usa `flutter_lints` via `analysis_options.yaml`): `flutter analyze`
- Rodar testes: `flutter test` (um arquivo específico: `flutter test test/algum_teste.dart`)
- Build de APK de release Android: `flutter build apk`
- Build de app bundle Android: `flutter build appbundle`

Não há configuração de CI, script de build customizado nem código de backend neste repositório — a API PHP do painel (`api_app_config.php`, `api_botoes.php`, `ramal_qrcode.php`) com a qual o app se comunica vive fora deste repositório.

**Nesta máquina Windows específica**, o Flutter não vinha instalado nem no PATH; foi instalado via `winget install pingbird.Puro` (gerenciador de versões Flutter) e `puro create stable stable`, ficando em `C:\Users\<usuário>\.puro\envs\stable\flutter\bin\`. **`flutter analyze` trava com `FormatException` no canal LSP** nesta máquina — a causa é o `ç` no caminho da pasta (`Projetos Programaçao`), que corrompe o framing `Content-Length` da comunicação com o `analysis_server`. Usar `dart analyze` (mesmo binário, mesma config de lint) como alternativa — funciona normalmente e não passa pelo canal LSP problemático.

Builds Android (`flutter build apk`) que envolvem plugins com dependências nativas pesadas (ex.: Firebase) podem falhar com erros como `immutable workspace ... have been modified` ou transforms do Gradle "corrompidos" — na prática isso costuma ser **limite de caminho longo do Windows (260 caracteres)** truncando a exclusão de subpastas fundas em `C:\Users\<usuário>\.gradle\caches\`, não corrupção de disco de verdade. O `Remove-Item -Recurse -Force` do PowerShell falha *silenciosamente* nesses casos (não lança erro, só deixa lixo pra trás). Para limpar de vez: matar processos `java` (daemon do Gradle preso segurando lock) e apagar `~/.gradle/caches` via `rm -rf` no Git Bash, que lida melhor com caminhos longos. Também vale checar espaço em disco livre antes de builds grandes — historicamente esta máquina já ficou com o disco C: cheio (pasta Downloads acumulando instaladores de Windows/Office na casa de dezenas de GB).

## Arquitetura

O app é orientado a serviços, pequeno, sem framework de gerenciamento de estado (sem Provider/Riverpod/Bloc) — as telas mantêm seu próprio estado e falam diretamente com classes de serviço simples (`ChangeNotifier`).

**Fluxo:** `main.dart` → `_SplashRouter` verifica o `SessionService` em busca de uma conta salva → direciona para `LoginScreen` (sem sessão salva) ou `HomeScreen` (sessão existente).

**`lib/services/`** — toda a lógica de negócio fica aqui, desacoplada dos widgets:
- `session_service.dart` — persiste a conta SIP (`SipAccount`) no `shared_preferences` e faz o parse do texto do QR code no formato `PAINEL/SERVIDOR/PORTA/RAMAL/SENHA` gerado pelo `ramal_qrcode.php` do painel.
- `api_service.dart` — cliente HTTP para o backend do painel. Busca o `Branding` (nome do app/logo/config SIP padrão, com fallback fixo caso o painel esteja inacessível) e a lista de botões de discagem (`AppButton`) + lista de unidades via `api_botoes.php`. A validação de login reaproveita o `fetchBotoes` como checagem implícita de credenciais (não existe endpoint de autenticação dedicado).
- `sip_service.dart` — encapsula o pacote `sip_ua` (`SIPUAHelper`) como um `ChangeNotifier`. Controla o estado de registro SIP, o estado da chamada ativa, os streams de mídia WebRTC (local/remoto) e o envio de DTMF. Conecta via WSS (`TransportType.WS`, porta 8089, transporte `[transport-ws]` do painel) — necessário porque os endpoints estão com `webrtc=yes` (ICE, BUNDLE áudio+vídeo); ver comentário no arquivo. Também integra a UI nativa de chamada via `flutter_callkit_incoming` — chamadas SIP entrantes disparam `FlutterCallkitIncoming.showCallkitIncoming`, e os eventos de aceitar/recusar/timeout do CallKit chamam de volta `atender()`/`desligar()`.
- `foreground_service.dart` — fala (via `MethodChannel`) com um Service Android nativo (`PersistentEngineService.kt`) que mantém vivo o MESMO `FlutterEngine` da tela principal quando não tem `Activity` em primeiro plano — não é mais um isolate/engine separado, então existe só um `SipService`, sempre o mesmo objeto, registrado com ou sem tela visível (inclusive vídeo funciona em ligação atendida com o app fechado). Ver `docs/04-segundo-plano-e-callkit.md` e `android/app/src/main/kotlin/br/com/portcall/portcall_app/` (`EngineHolder.kt`, `PersistentEngineService.kt`, `RestartReceiver.kt`, `MainActivity.kt`).

**`lib/screens/`** — uma tela por arquivo, todas recebendo os serviços via construtor (não há service locator/DI):
- `login_screen.dart` — entrada manual ou leitura de QR (`qr_scan_screen.dart`, via `mobile_scanner`) de painel/servidor/ramal/senha; valida contra o painel antes de salvar a sessão.
- `home_screen.dart` — a tela principal após o login. Solicita permissões de microfone/câmera, carrega branding + botões de discagem + unidades, conecta o `SipService` e renderiza as ações rápidas (Apartamentos, Câmeras) e a grade de botões de discagem configurados pelo condomínio. Escuta o `SipService` e empurra automaticamente a `CallScreen` sempre que uma chamada fica ativa (entrante ou sainte).
- `call_screen.dart` — UI durante a chamada: renderiza vídeo WebRTC local/remoto via `RTCVideoView` quando o vídeo está ativo, teclado DTMF e atalhos de DTMF por botão ("portão", `AppButton` do tipo `dtmf`) exibidos apenas durante a chamada.
- `apartamentos_screen.dart` / `dialpad_screen.dart` — ligar para qualquer unidade da lista fornecida pelo painel, ou discar um número arbitrário.
- `cameras_screen.dart` — placeholder ("em breve"), ainda não implementada.

**`lib/models/`** — classes de dados simples com factories `fromJson` que espelham o formato JSON da API do painel: `AppButton` (tipo `discar` = ligar, ou `dtmf`; tem `ordem` para ordenação), `Branding`.

## Observações para fazer alterações

- Mantenha as novas strings de UI e identificadores consistentes com o vocabulário de domínio em português já existente, em vez de misturar com inglês.
- As telas recebem os serviços (`SipService`, `ApiService`, `SipAccount`) via injeção pelo construtor, a partir de quem as chama — siga esse padrão em vez de introduzir um service locator ou singletons globais.
- `SipService` e qualquer tela que mantenha uma referência a ele devem fazer `addListener`/`removeListener` em `initState`/`dispose` — veja `home_screen.dart` e `call_screen.dart` para o padrão já estabelecido de reagir a mudanças de estado do SIP e navegar automaticamente.
