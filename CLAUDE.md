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

**Esse código do servidor tem versionamento próprio, direto em produção** (`clienteauto.portcallvoip.com.br`), porque uma edição errada no `portcall_router.agi` derruba todas as ligações do condomínio e antes o único backup era uma cópia manual com data no nome:

```bash
portcall-git status              # o que mudou desde o último save
portcall-git diff                # as mudanças em detalhe
portcall-git save "mensagem"     # grava um ponto de restauração
portcall-git restore <arquivo>   # volta UM arquivo pro último save
```

Cobre `/var/www/html` (o painel) e os `portcall_*.agi` em `/var/lib/asterisk/agi-bin`. Os diretórios `.git` ficam em `/opt/portcall-git`, **fora do docroot** de propósito — dentro dele, qualquer um baixaria o código-fonte e as senhas de banco pela web (confirmado: `/.git/config` responde 404). Tarballs, APKs e `uploads/` ficam de fora (2,3 GB dos 2,4 GB da pasta eram lixo de build).

Repare que é um repositório **local, sem remote**: serve pra desfazer erro e ver histórico, não como backup contra a perda do servidor. As senhas de banco estão hardcoded em `funcoes.php` e nos AGIs, então espelhar isso num remote exigiria antes movê-las pra um arquivo de configuração fora do versionamento.

**Nesta máquina Windows específica**, o Flutter não vinha instalado nem no PATH; foi instalado via `winget install pingbird.Puro` (gerenciador de versões Flutter) e `puro create stable stable`, ficando em `C:\Users\<usuário>\.puro\envs\stable\flutter\bin\`. **`flutter analyze` trava com `FormatException` no canal LSP** nesta máquina — a causa é o `ç` no caminho da pasta (`Projetos Programaçao`), que corrompe o framing `Content-Length` da comunicação com o `analysis_server`. Usar `dart analyze` (mesmo binário, mesma config de lint) como alternativa — funciona normalmente e não passa pelo canal LSP problemático.

Builds Android (`flutter build apk`) que envolvem plugins com dependências nativas pesadas (ex.: Firebase) podem falhar com erros como `immutable workspace ... have been modified` ou transforms do Gradle "corrompidos" — na prática isso costuma ser **limite de caminho longo do Windows (260 caracteres)** truncando a exclusão de subpastas fundas em `C:\Users\<usuário>\.gradle\caches\`, não corrupção de disco de verdade. O `Remove-Item -Recurse -Force` do PowerShell falha *silenciosamente* nesses casos (não lança erro, só deixa lixo pra trás). Para limpar de vez: matar processos `java` (daemon do Gradle preso segurando lock) e apagar `~/.gradle/caches` via `rm -rf` no Git Bash, que lida melhor com caminhos longos. Também vale checar espaço em disco livre antes de builds grandes — historicamente esta máquina já ficou com o disco C: cheio (pasta Downloads acumulando instaladores de Windows/Office na casa de dezenas de GB).

Os dois parágrafos acima valem só pra máquina Windows onde o app foi desenvolvido. Num Mac, o fluxo é o padrão do Flutter (`flutter run -d <id>`), `flutter analyze` funciona normalmente e nada disso se aplica.

### Estado do iOS

**Nunca foi compilado nem rodado num aparelho iOS** — todo o desenvolvimento e teste até aqui foi Android. O que já está preparado:

- Bundle id `br.com.portcall.portcallApp` (repare que difere do `applicationId` do Android, `br.com.portcall.portcall_app`).
- `Info.plist` com `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, `NSPhotoLibraryUsageDescription` e `UIBackgroundModes: audio`. Sem as três primeiras o iOS encerra o app na hora em que ele pede a permissão — faltavam e foram adicionadas.
- Ícones gerados pra todos os tamanhos (`flutter_launcher_icons`, com `remove_alpha_ios` — a App Store recusa ícone com canal alfa).
- `codemagic.yaml` na raiz, com um workflow ad-hoc e um de TestFlight. Depende de integração App Store Connect configurada no painel do Codemagic, que **ainda não existe**.

**O que NÃO existe no iOS:** todo o mecanismo de continuar registrado com o app fechado é Android puro (`PersistentEngineService`, `RestartReceiver`, `BOOT_COMPLETED`, foreground service). O iOS não permite manter um WebSocket SIP vivo em segundo plano; o equivalente seria PushKit + CallKit (VoIP push), que não está implementado. Portanto, no iPhone, espere receber chamada só com o app em primeiro plano até isso existir. A keystore de release é Android-only e não tem efeito aqui.

## Arquitetura

O app é orientado a serviços, pequeno, sem framework de gerenciamento de estado (sem Provider/Riverpod/Bloc) — as telas mantêm seu próprio estado e falam diretamente com classes de serviço simples (`ChangeNotifier`).

**Fluxo:** `main.dart` cria o `SipService` e, se já existir conta salva no `SessionService`, dispara o registro SIP **antes do `runApp()`** → `_SplashRouter` direciona para `LoginScreen` (sem sessão salva) ou `HomeScreen` (sessão existente), repassando o `SipService` por construtor.

O registro ficar no `main()`, e não dentro de `HomeScreen.initState()`, é deliberado: quando o engine sobe pelo `PersistentEngineService` depois de reiniciar o celular não existe `Activity`, e sem superfície de desenho o Flutter não agenda frames — a navegação da splash pra home fica pendente pra sempre e nenhum `initState()` roda (timers e I/O, por outro lado, continuam normais). Ver `docs/04-segundo-plano-e-callkit.md`.

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
- `cameras_screen.dart` — lista as câmeras do condomínio e abre o stream RTSP ao vivo com `media_kit`/`media_kit_video`. É essa dependência (libmpv nativa) que responde pela maior parte do tamanho do pacote, então não remova achando que é peso morto.

**`lib/models/`** — classes de dados simples com factories `fromJson` que espelham o formato JSON da API do painel: `AppButton` (tipo `discar` = ligar, ou `dtmf`; tem `ordem` para ordenação), `Branding`.

## Observações para fazer alterações

- Mantenha as novas strings de UI e identificadores consistentes com o vocabulário de domínio em português já existente, em vez de misturar com inglês.
- As telas recebem os serviços (`SipService`, `ApiService`, `SipAccount`) via injeção pelo construtor, a partir de quem as chama — siga esse padrão em vez de introduzir um service locator ou singletons globais.
- `SipService` e qualquer tela que mantenha uma referência a ele devem fazer `addListener`/`removeListener` em `initState`/`dispose` — veja `home_screen.dart` e `call_screen.dart` para o padrão já estabelecido de reagir a mudanças de estado do SIP e navegar automaticamente.
