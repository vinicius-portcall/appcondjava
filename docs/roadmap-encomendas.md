# Roadmap — Módulo Encomendas

Acompanhamento do desenvolvimento do módulo "Gestão de Entregas e Encomendas" (item 2.8 da `documentacao-tecnica-app.md`), quinto módulo novo do INOVASEG.

Legenda de status: 🔴 Pendente · 🟡 Em andamento · 🟢 Concluído

**Status geral: 🟢 Módulo concluído e validado pelo usuário (17/08/2026).** `dart analyze`: nenhum problema encontrado. Fluxo completo testado via curl (listar por unidade via Rotas → confirmar retirada → isolamento entre unidades bloqueado corretamente) e confirmado funcionando no celular físico pelo usuário.

**Dependência criada para teste**: rota `apartamento=101 → ramal=5500` adicionada em `rotas_horarios` (condomínio 19) — sem ela, o ramal de teste não teria nenhuma unidade associada e a tela ficaria sempre vazia. Ficou como configuração permanente de teste, não foi removida.

Servidor de referência: `clienteauto.portcallvoip.com.br` (painel PHP em `/var/www/html`, banco `azcall`).

## Decisões de escopo (v1)

- Campos: apartamento, tipo (Pacote/Carta/Envelope/Remédio/Outro), código de rastreio interno (opcional), informação adicional (opcional, ex.: "Frágil"), foto do recebimento (opcional).
- **A foto é tirada/anexada pela portaria no painel administrativo** (upload de arquivo, mesmo padrão já usado no Mural — PNG/JPG/WEBP até 2MB), não pelo morador no app. Isso evita precisar adicionar `image_picker` ao app (mesma decisão de escopo já tomada na Ouvidoria).
- **Como o app descobre "quais encomendas são minhas"**: reaproveita a relação que já existe em `rotas_horarios` (apartamento → ramal). O endpoint resolve o(s) apartamento(s) associados ao ramal logado via essa tabela e filtra as encomendas por eles — sem precisar de uma coluna nova ligando ramal a apartamento. **Consequência**: um ramal sem nenhuma rota configurada em Rotas não verá nenhuma encomenda (o sistema não tem como saber de qual unidade ele é).
- Ação do morador: **confirmar retirada**, informando o nome de quem retirou (pode não ser o próprio morador — porteiro, familiar etc., conforme a especificação "Retirada por [Nome] em [Data/Hora]"). Sem "agendamento de retirada" nesta v1 (só confirmação simples).
- Painel: cadastro pela portaria/operador, listagem geral do condomínio, sem necessidade de "responder" (diferente da Ouvidoria) — só criar e, se necessário, excluir um lançamento errado.

## Backend (painel PHP + MySQL)

| # | Item | Status |
|---|---|---|
| 1 | Criar tabela `encomendas` no banco `azcall` | 🟢 Concluído |
| 2 | Criar endpoint `api_encomendas.php` (GET, resolve apartamento via `rotas_horarios`) | 🟢 Concluído |
| 3 | Criar endpoint `api_encomenda_retirar.php` (POST, morador confirma retirada) | 🟢 Concluído |
| 4 | Criar painel `encomendas.php` (listagem) | 🟢 Concluído |
| 5 | Criar `encomenda_form.php` (novo, com upload de foto) e `encomenda_save.php` | 🟢 Concluído |
| 6 | Criar `encomenda_delete.php` | 🟢 Concluído |
| 7 | Adicionar item "📦 Encomendas" no menu lateral | 🟢 Concluído |
| 8 | Testar os endpoints via curl no servidor | 🟢 Concluído |

## App Flutter

| # | Item | Status |
|---|---|---|
| 9 | Criar model `Encomenda` | 🟢 Concluído |
| 10 | Adicionar `ApiService.fetchEncomendas()` e `ApiService.confirmarRetirada()` | 🟢 Concluído |
| 11 | Criar `EncomendasScreen` (lista + confirmar retirada) | 🟢 Concluído |
| 12 | Adicionar atalho na `HomeScreen` (6º item da grade) | 🟢 Concluído |
| 13 | Rodar `dart analyze` | 🟢 Concluído |

## Documentação e teste

| # | Item | Status |
|---|---|---|
| 14 | Atualizar `docs/05` e `docs/06` | 🟢 Concluído |
| 15 | Testar no celular físico | 🟢 Concluído (build/instalação/launch sem crash; teste manual do fluxo pendente de confirmação do usuário) |
