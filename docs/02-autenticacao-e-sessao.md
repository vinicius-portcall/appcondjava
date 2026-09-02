# 2. Autenticação e sessão

Arquivos principais: `lib/screens/login_screen.dart`, `lib/screens/qr_scan_screen.dart`, `lib/services/session_service.dart`, `lib/services/api_service.dart`.

## Dados de uma conta (`SipAccount`)

Uma sessão de login é representada por `SipAccount` (definida em `session_service.dart`), com os campos:

| Campo | Descrição |
|---|---|
| `painelUrl` | URL base do painel PHP (ex.: `https://seudominio.com/portcall`) |
| `servidor` | host/IP do servidor SIP (Asterisk) |
| `porta` | porta SIP, padrão `5060` |
| `ramal` | número do ramal SIP |
| `senha` | senha do ramal |
| `displayName` | nome de exibição usado no SIP (hoje sempre igual ao ramal) |

## Painel único, login simplificado (usuário = ramal)

Este app hoje atende **um único painel fixo** (`_painelUrlPadrao` em `login_screen.dart`, apontando pro servidor real do cliente) — não é mais um cliente genérico multi-painel. Por isso o morador só precisa saber "usuário" (que **é** o número do ramal, só renomeado na UI pra ficar mais familiar) e senha; servidor/porta SIP não aparecem mais no formulário, são resolvidos automaticamente por condomínio.

Na `LoginScreen`, duas formas de preencher usuário/senha:

### a) Leitura de QR code

O botão "Escanear QR do ramal" abre a `QrScanScreen` (`mobile_scanner`), lê o texto do QR gerado pelo painel (`ramal_qrcode.php`, fora deste repositório) no formato:

```
PAINEL: https://seudominio.com/portcall
SERVIDOR: sip.seudominio.com
PORTA: 5060
RAMAL: 101
SENHA: ********
```

`SessionService.parseQrText()` faz o parse de qualquer jeito (mantido genérico), mas a `LoginScreen` só aproveita `RAMAL` e `SENHA` — os campos `PAINEL`/`SERVIDOR`/`PORTA` do texto são ignorados, já que o app é fixo num único painel. Depois de extrair ramal/senha do QR, o login é **automático** (chama `_entrar()` sozinho, sem precisar tocar em "Entrar" de novo).

### b) Preenchimento manual

O usuário digita usuário (ramal) e senha diretamente.

## Validação e persistência

Ao tocar em "Entrar" (ou automaticamente após ler o QR) — `_entrar()` em `login_screen.dart`:

1. Valida que usuário e senha não estão vazios.
2. Cria um `ApiService(_painelUrlPadrao)` e chama `fetchBranding(usuario, senha)`.
3. **Não existe endpoint de autenticação dedicado** — a validação reaproveita `api_app_config.php`: o servidor faz o lookup de ramal+senha e, se válido, já devolve `sip_servidor`/`sip_porta` corretos pro condomínio daquele ramal (podem variar por condomínio, mesmo estando todos no mesmo painel). Uma chamada só resolve autenticação **e** configuração SIP. Qualquer exceção (rede, `ok: false`, HTTP de erro) é tratada como credencial inválida.
4. Se o servidor não devolver um `sip_servidor` válido, mostra "Não foi possível obter a configuração SIP do condomínio." (situação de configuração incompleta no painel, não de senha errada).
5. Se válido, monta o `SipAccount` (com `painelUrl` fixo, `servidor`/`porta` vindos da resposta) e chama `SessionService().save(conta)`.
6. Navega (`pushReplacement`) para `HomeScreen`.

Se a validação falhar, é exibida a mensagem "Usuário ou senha inválidos, ou painel inacessível." sem detalhar a causa exata (a API não distingue rede indisponível de credencial errada).

## Sessão persistida (auto-login)

Toda vez que o app abre, `_SplashRouter` (em `main.dart`) chama `SessionService().load()`:

- Se todos os campos obrigatórios (`painel`, `servidor`, `ramal`, `senha`) estiverem salvos, monta um `SipAccount` e vai direto para `HomeScreen` — **não há revalidação da senha nesse fluxo**, o app assume que a sessão salva ainda é válida e só vai descobrir o contrário quando o `SipService` tentar registrar no servidor SIP.
- Se faltar algum campo, retorna `null` e o app vai para `LoginScreen`.

## Logout

Em `HomeScreen._sair()`: desconecta o `SipService` (`desconectar()`), para o serviço de segundo plano (`ForegroundService.stop()`), limpa a sessão salva (`SessionService().clear()` — remove todas as chaves do `shared_preferences`) e volta para `LoginScreen`.
