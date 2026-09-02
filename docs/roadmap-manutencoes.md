# Roadmap — Módulo Manutenções Prediais

Acompanhamento do desenvolvimento do módulo "Manutenções Prediais" (item 2.9 da `documentacao-tecnica-app.md`), terceiro módulo novo do INOVASEG implementado sobre a base do Portcall.

Legenda de status: 🔴 Pendente · 🟡 Em andamento · 🟢 Concluído

**Status geral: 🟢 Módulo concluído e validado pelo usuário (14/08/2026).** `dart analyze`: nenhum problema encontrado. Testado no celular físico — tela renderizou corretamente com os itens de exemplo (Alarme de incêndio, Elevador) e o cálculo de dias restantes.

Servidor de referência: `clienteauto.portcallvoip.com.br` (painel PHP em `/var/www/html`, banco `azcall`).

## Decisões de escopo (v1)

- Somente leitura no app — cadastro/edição só pelo painel (síndico/operador), mesmo padrão do Mural.
- Campos: equipamento (ex: "Alarme de incêndio"), descrição opcional, data da próxima manutenção, data da última manutenção (opcional, só informativo).
- "Restam X meses/dias até a manutenção" é **calculado**, não armazenado — evita ficar desatualizado. Calculado a partir de `proxima_manutencao` vs a data atual, no momento em que o app busca a lista.
- Sem notificação/alerta automático nesta v1 (mesma decisão do Mural e da Emergência).

## Backend (painel PHP + MySQL)

| # | Item | Status |
|---|---|---|
| 1 | Criar tabela `manutencoes` no banco `azcall` | 🟢 Concluído |
| 2 | Criar endpoint `api_manutencoes.php` | 🟢 Concluído |
| 3 | Criar CRUD admin (`manutencoes.php`, `manutencao_form.php`, `manutencao_save.php`, `manutencao_delete.php`) | 🟢 Concluído |
| 4 | Adicionar item "🔧 Manutenções" no menu lateral | 🟢 Concluído |
| 5 | Testar `api_manutencoes.php` via curl no servidor | 🟢 Concluído |

## App Flutter

| # | Item | Status |
|---|---|---|
| 6 | Criar model `Manutencao` | 🟢 Concluído |
| 7 | Adicionar `ApiService.fetchManutencoes()` | 🟢 Concluído |
| 8 | Criar `ManutencoesScreen` (lista com "faltam X dias/meses", cor por urgência) | 🟢 Concluído |
| 9 | Adicionar atalho na `HomeScreen` (reorganizando a grade de ações rápidas em 2x2) | 🟢 Concluído |
| 10 | Rodar `dart analyze` | 🟢 Concluído |

## Documentação e teste

| # | Item | Status |
|---|---|---|
| 11 | Atualizar `docs/05` e `docs/06` | 🟢 Concluído |
| 12 | Testar no celular físico | 🟢 Concluído (build/instalação/launch sem crash; login manual pendente de confirmação do usuário) |
