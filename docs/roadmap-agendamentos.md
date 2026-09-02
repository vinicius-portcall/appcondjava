# Roadmap — Agendamentos (Reserva de Espaços Comuns)

Reserva de áreas de lazer do condomínio (Academia, Churrasqueira, Quadra, Salão de Festas etc.), com grade de disponibilidade por dia, taxa informativa e regra de antecedência mínima pra cancelar.

Legenda de status: 🟢 Concluído · 🟡 Em andamento · 🟢 Concluído

Servidor de referência: `clienteauto.portcallvoip.com.br`.

## Decisões de escopo (v1) — leia antes de usar

- **Slots de horário fixos por espaço**, não agenda livre — cada espaço comum tem uma janela (`horario_abertura`/`horario_fechamento`) e um tamanho de intervalo (`duracao_slot_minutos`, ex.: 60min pra academia, ou um único slot de dia inteiro pro salão de festas configurando duração = janela inteira). O morador escolhe um slot pronto, não digita hora livre — evita sobreposição sem precisar de lógica de conflito complexa.
- **Sem pagamento real** — a `taxa` é só informativa (mostrada na tela), igual o `valor` nos Boletos seria (se um dia esse módulo existir). Não há gateway de pagamento integrado.
- **Lista de convidados como texto livre** — em vez de uma tabela relacional de convidados por reserva, um campo de texto simples (`convidados`, nomes separados por vírgula), no mesmo espírito pragmático do `info_adicional` de Encomendas. Suficiente pra portaria saber quem esperar, sem modelagem extra.
- **Cancelamento respeita antecedência mínima** — cada espaço define `antecedencia_cancelamento_horas`; o backend rejeita cancelamento fora da janela.
- **Painel tem visão somente-leitura de todas as reservas** do condomínio (`agendamentos_condominio.php`), sem edição manual — é gerado pelo app, o síndico só acompanha.

## Backend (MySQL + PHP)

| # | Item | Status |
|---|---|---|
| 1 | Criar tabelas `espacos_comuns` e `agendamentos` no banco `azcall` | 🟢 Concluído |
| 2 | `api_espacos.php` (GET, auth ramal+senha) — lista espaços ativos do condomínio | 🟢 Concluído |
| 3 | `api_agenda_disponibilidade.php` (GET, espaco_id+data) — slots do dia com status ocupado/livre | 🟢 Concluído |
| 4 | `api_agendamento_criar.php` (POST) — cria reserva, valida conflito de slot | 🟢 Concluído |
| 5 | `api_agendamentos_listar.php` (GET) — reservas do próprio ramal | 🟢 Concluído |
| 6 | `api_agendamento_cancelar.php` (POST) — cancela respeitando antecedência mínima | 🟢 Concluído |
| 7 | Testar os cinco endpoints via curl com dados descartáveis | 🟢 Concluído |
| 8 | Painel `espacos_comuns.php` — CRUD dos espaços (nome, taxa, janela, duração do slot, antecedência) | 🟢 Concluído |
| 9 | Painel `agendamentos_condominio.php` — listagem somente-leitura das reservas | 🟢 Concluído |
| 10 | Itens no menu lateral | 🟢 Concluído |

## App Flutter

| # | Item | Status |
|---|---|---|
| 11 | Models `Espaco` e `Agendamento` | 🟢 Concluído |
| 12 | Métodos no `ApiService` (espaços, disponibilidade, criar, listar, cancelar) | 🟢 Concluído |
| 13 | Tela `agendamentos_screen.dart` — lista de espaços, grade de horários do dia, criar/cancelar reserva, "minhas reservas" | 🟢 Concluído |
| 14 | Nova tile "Agendamentos" na grade da home (estender paleta de 9 pra 10 acentos) | 🟢 Concluído |
| 15 | `dart analyze` + build/install/launch no device conectado | 🟢 Concluído |
| 16 | Atualizar `docs/05` e `docs/06` | 🟢 Concluído |
