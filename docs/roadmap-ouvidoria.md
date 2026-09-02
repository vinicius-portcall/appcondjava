# Roadmap — Módulo Pedidos e Manifestações (Ouvidoria)

Acompanhamento do desenvolvimento do módulo "Pedidos e Manifestações" (item 2.6 da `documentacao-tecnica-app.md`), quarto módulo novo do INOVASEG e o **primeiro onde o morador escreve pelo app**, não só lê.

Legenda de status: 🔴 Pendente · 🟡 Em andamento · 🟢 Concluído

**Status geral: 🟢 Backend e app concluídos (17/08/2026).** `dart analyze`: nenhum problema encontrado. Fluxo completo testado via curl (criar → isolamento por ramal → responder pelo painel → morador vê a resposta). App instalado e rodando sem crash no celular físico — falta a confirmação do usuário testando o envio de um chamado manualmente.

Servidor de referência: `clienteauto.portcallvoip.com.br` (painel PHP em `/var/www/html`, banco `azcall`).

## Decisões de escopo (v1)

- Campos do chamado: unidade (reaproveitando a mesma lista de apartamentos já usada em Apartamentos/`api_botoes.php`), assunto, mensagem. **Sem anexo de arquivo/foto nesta v1** — o app não tem nenhuma dependência de seleção de imagem/arquivo hoje (`image_picker`/`file_picker` não estão no `pubspec.yaml`); adicionar isso exigiria uma dependência nova, então fica como próximo passo, igual já fizemos com push notification no Mural.
- **Privacidade**: diferente do Mural (público), cada morador só vê os próprios chamados — filtrado pelo `ramal` de quem enviou, não por todo o condomínio.
- Painel: síndico/operador vê todos os chamados do condomínio, responde com uma mensagem de texto e muda o status (`aberto` → `em_andamento` → `respondido`/`fechado`).
- Sem notificação/push quando o chamado é respondido nesta v1 — o morador vê a resposta na próxima vez que abrir a tela.

## Backend (painel PHP + MySQL)

| # | Item | Status |
|---|---|---|
| 1 | Criar tabela `chamados` no banco `azcall` | 🟢 Concluído |
| 2 | Criar endpoint `api_chamado_criar.php` (POST, morador envia) | 🟢 Concluído |
| 3 | Criar endpoint `api_chamados.php` (GET, morador vê só os próprios) | 🟢 Concluído |
| 4 | Criar painel `chamados.php` (listagem de todos do condomínio, com status) | 🟢 Concluído |
| 5 | Criar `chamado.php` (detalhe + responder) e `chamado_responder_save.php` | 🟢 Concluído |
| 6 | Adicionar item "📋 Ouvidoria" no menu lateral | 🟢 Concluído |
| 7 | Testar os dois endpoints via curl no servidor | 🟢 Concluído |

## App Flutter

| # | Item | Status |
|---|---|---|
| 8 | Criar model `Chamado` | 🟢 Concluído |
| 9 | Adicionar `ApiService.enviarChamado()` e `ApiService.fetchChamados()` | 🟢 Concluído |
| 10 | Criar `OuvidoriaScreen` (lista de chamados enviados + formulário de novo chamado) | 🟢 Concluído |
| 11 | Adicionar atalho na `HomeScreen` (migrar a grade de ações rápidas pra `GridView`, já que passa de 4 pra 5 itens) | 🟢 Concluído |
| 12 | Rodar `dart analyze` | 🟢 Concluído |

## Documentação e teste

| # | Item | Status |
|---|---|---|
| 13 | Atualizar `docs/05` e `docs/06` | 🟢 Concluído |
| 14 | Testar no celular físico | 🟢 Concluído e validado pelo usuário |

## Correção pós-entrega: overflow na grade de ações rápidas (17/08/2026)

Usuário reportou "BOTTOM OVERFLOWED BY 8.9 PIXELS" nos cards de atalho da Home depois de testar. Causa: `_tileAcaoRapida` foi desenhado originalmente para caber numa `Row` sem altura fixa; ao migrar a grade pra `GridView.count(childAspectRatio: 1.35)` (necessário pra caber o 5º atalho, Ouvidoria), o texto "Manutenções" (o mais longo) quebrava linha e estourava a altura fixa da célula. Corrigido com três ajustes em `home_screen.dart`:
- `childAspectRatio` reduzido de `1.35` para `1.1` (células mais altas).
- Título do card com `maxLines: 1, overflow: TextOverflow.ellipsis` (mesma proteção já usada em `_cardBotao`, nunca mais quebra linha independente do tamanho de fonte do aparelho).
- Padding/ícone do card levemente reduzidos (18→12 vertical, ícone 52→48px) para dar mais folga.

Validado pelo usuário no celular físico após a correção.
