# Roadmap — Gestão de Convidados (lista pra portaria)

Segundo método de convite da especificação original (o primeiro, QR Code Pass, já está pronto — ver [roadmap-qrcode-visitante.md](roadmap-qrcode-visitante.md)). Aqui o morador só avisa a portaria com antecedência: nome do(s) convidado(s), período esperado e observação — sem QR, sem código, a portaria já vê a lista de quem está esperado.

Legenda de status: 🟢 Concluído · 🟡 Em andamento · 🟢 Concluído

Servidor de referência: `clienteauto.portcallvoip.com.br`.

## Decisões de escopo (v1) — leia antes de usar

- **Sem validação de identidade** — diferente do QR (código de uso único conferido na entrada), aqui é só um aviso informativo. A portaria vê o nome esperado na lista e deixa entrar, sem nenhuma conferência automática. É o método "mais informal" dos dois, do jeito que a especificação descreve ("Avisar Portaria").
- **Período com data/hora de início e fim** — `data_inicio`/`data_fim` (`DATETIME`), cobre tanto "convidado chega hoje às 20h" quanto "diarista, toda semana das 8h às 12h por um mês" (basta um período longo).
- **"Marcar chegada" é manual pela portaria** — não mexe no Histórico de Acessos existente (que é sobre abertura de portão/identificação, não sobre aviso de expectativa de visita). Ficou como um registro próprio, mostrado só nesse módulo.
- **Reaproveita a tela de Visitantes no app** — em vez de criar uma tela nova solta, a `VisitantesQrScreen` virou uma tela com duas abas: "QR Code" (o que já existia) e "Lista (portaria)" (novo). Mesma ideia de domínio (visitante esperado), só o método de aviso muda.

## Backend (MySQL + PHP)

| # | Item | Status |
|---|---|---|
| 1 | Criar tabela `convidados_lista` no banco `azcall` | 🟢 Concluído |
| 2 | `api_convidado_criar.php` (POST, auth ramal+senha) — cadastra convidado esperado | 🟢 Concluído |
| 3 | `api_convidados_listar.php` (GET) — lista convidados cadastrados pelo próprio ramal | 🟢 Concluído |
| 4 | `api_convidado_cancelar.php` (POST) — cancela um convidado ainda `aguardando` | 🟢 Concluído |
| 5 | Testar os três endpoints via curl com dados descartáveis | 🟢 Concluído |
| 6 | Painel `portaria_convidados.php` — lista de quem está esperado (todo o condomínio), botão "Marcar chegada" | 🟢 Concluído |
| 7 | Item no menu lateral | 🟢 Concluído |

## App Flutter

| # | Item | Status |
|---|---|---|
| 8 | Model `ConvidadoLista` | 🟢 Concluído |
| 9 | Métodos no `ApiService` (criar/listar/cancelar) | 🟢 Concluído |
| 10 | Transformar `VisitantesQrScreen` numa tela com abas (QR Code / Lista pra portaria) | 🟢 Concluído |
| 11 | `dart analyze` + build/install/launch no device conectado | 🟢 Concluído |
| 12 | Atualizar `docs/05` e `docs/06` | 🟢 Concluído |
