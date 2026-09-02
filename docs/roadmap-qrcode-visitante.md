# Roadmap — QR Code de Visitante

Passe de visitante gerado pelo morador no app, na forma de um QR Code, validado manualmente pela portaria (sistema próprio, **não** integrado ao leitor nativo do equipamento Control iD — decisão do usuário, ver seção abaixo).

Legenda de status: 🟢 Concluído · 🟡 Em andamento · 🟢 Concluído

Servidor de referência: `clienteauto.portcallvoip.com.br`.

## Decisão de escopo (v1) — leia antes de usar

- **Por que não integrar com o leitor de QR do Control iD**: o equipamento tem leitor de QR nativo, mas cadastrar o QR gerado pelo app como credencial válida *dentro* do equipamento exigiria nosso servidor se conectar direto na API local dele (IP/porta acessíveis, não só o equipamento nos chamando como no [webhook facial](roadmap-integracao-facial-controlid.md)) e credenciais de admin do equipamento. O usuário optou por um sistema próprio, independente, evitando essa dependência de rede/infra do equipamento.
- **Validação manual pela portaria**: o morador gera o QR no app; a portaria digita ou escaneia o código (qualquer leitor USB tipo "teclado" ou a câmera de um celular/tablet) numa tela do painel (`portaria_qr.php`), que mostra os dados do visitante e confirma a entrada.
- **Código de uso único**: cada passe tem um `codigo` aleatório (16 caracteres hex, `random_bytes(8)`) que vira o conteúdo do QR. Ao validar, o passe muda de `ativo` para `usado` — não dá pra usar de novo.
- **Validade**: o passe expira num horário definido na criação (padrão sugerido no app, mas o morador escolhe). Passe expirado não é aceito na validação mesmo que o código esteja certo.
- **Sem geração de PDF/impressão** — o QR é mostrado na tela do app do morador (compartilhar/mostrar a foto/print pro visitante é problema de UX do usuário, não escopo do v1).

## Backend (MySQL + PHP)

| # | Item | Status |
|---|---|---|
| 1 | Criar tabela `visitantes_qr` no banco `azcall` | 🟢 Concluído |
| 2 | `api_qr_criar.php` (POST, auth ramal+senha) — cria o passe, devolve `codigo` | 🟢 Concluído |
| 3 | `api_qr_listar.php` (GET, auth ramal+senha) — lista os passes gerados pelo próprio ramal | 🟢 Concluído |
| 4 | `api_qr_cancelar.php` (POST, auth ramal+senha) — cancela um passe `ativo` | 🟢 Concluído |
| 5 | Testar os três endpoints via curl com ramal de teste | 🟢 Concluído |
| 6 | Painel `portaria_qr.php` — digitar/escanear código, ver dados do visitante, confirmar entrada | 🟢 Concluído |
| 7 | Item no menu lateral do painel | 🟢 Concluído |

## Integração com o Histórico de Acessos existente

| # | Item | Status |
|---|---|---|
| 8 | Unificar `api_historico_acessos.php` pra incluir passes `usado` como 3º tipo (`qrcode`) no `UNION` | 🟢 Concluído |
| 9 | Atualizar `historico_acessos.php` (painel) do mesmo jeito | 🟢 Concluído |
| 10 | Atualizar `TipoAcesso`/`AcessoPortao`/`historico_acessos_screen.dart` no app pro 3º tipo | 🟢 Concluído |

## App Flutter

| # | Item | Status |
|---|---|---|
| 11 | Adicionar dependência `qr_flutter` (gerar o QR na tela; `mobile_scanner`, já presente, só lê) | 🟢 Concluído |
| 12 | Model `VisitantePass` + métodos no `ApiService` (criar/listar/cancelar) | 🟢 Concluído |
| 13 | Tela `visitantes_qr_screen.dart` — gerar novo passe, listar passes ativos/usados/cancelados com o QR renderizado | 🟢 Concluído |
| 14 | Nova tile "Visitantes" na grade de ações rápidas da home | 🟢 Concluído |
| 15 | `dart analyze` + build/install/launch no device conectado | 🟢 Concluído |
| 16 | Atualizar `docs/05` e `docs/06` | 🟢 Concluído |
