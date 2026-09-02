# Roadmap — Módulo Documentos do Condomínio

Acompanhamento do desenvolvimento do módulo "Documentos" (item 2.11 da `documentacao-tecnica-app.md`), sexto módulo novo do INOVASEG.

Legenda de status: 🔴 Pendente · 🟡 Em andamento · 🟢 Concluído

**Status geral: 🟢 Módulo concluído e validado pelo usuário (17/08/2026).** `dart analyze`: nenhum problema encontrado. Upload de PDF testado de ponta a ponta no servidor (form → arquivo salvo → servido com `content-type: application/pdf` correto) e confirmado no celular físico pelo usuário — o PDF abriu corretamente via `url_launcher`.

Servidor de referência: `clienteauto.portcallvoip.com.br` (painel PHP em `/var/www/html`, banco `azcall`).

## Decisões de escopo (v1)

- Repositório somente leitura no app — upload só pelo painel administrativo (síndico/operador), mesmo padrão do Mural/Manutenções.
- Campos: título, categoria (Balancete/Regimento/Ata/Outro), arquivo (PDF, JPG ou PNG — atas às vezes são digitalizadas como imagem).
- **Limite de upload: 2MB** (mesmo do Mural) — não 10MB como planejado inicialmente. O `php.ini` deste servidor tem `upload_max_filesize=2M` global; um limite maior no formulário não adiantaria nada, o PHP rejeitaria o arquivo antes do código rodar. Aumentar isso exigiria mudar a config global do PHP (afetando todos os uploads do painel, não só Documentos) e reiniciar o Apache — fora do escopo deste módulo. Fica registrado como limitação conhecida: documentos grandes (balancetes extensos, atas digitalizadas em alta resolução) podem não caber.
- **Nova dependência no app**: `url_launcher`, pra abrir o arquivo no navegador/leitor de PDF do celular. É o único jeito de o app efetivamente "abrir" um documento sem embutir um visualizador de PDF próprio — diferente do anexo da Ouvidoria (que foi adiado por não ser essencial), aqui a própria função do módulo depende de conseguir abrir o arquivo, então a dependência nova se justifica.
- Sem controle de "lido/não lido" nem notificação nesta v1.

## Backend (painel PHP + MySQL)

| # | Item | Status |
|---|---|---|
| 1 | Criar tabela `documentos` no banco `azcall` | 🟢 Concluído |
| 2 | Criar endpoint `api_documentos.php` | 🟢 Concluído |
| 3 | Criar painel `documentos.php` (listagem) | 🟢 Concluído |
| 4 | Criar `documento_form.php` (upload de PDF/imagem) e `documento_save.php` | 🟢 Concluído |
| 5 | Criar `documento_delete.php` | 🟢 Concluído |
| 6 | Adicionar item "📄 Documentos" no menu lateral | 🟢 Concluído |
| 7 | Testar o endpoint via curl no servidor | 🟢 Concluído |

## App Flutter

| # | Item | Status |
|---|---|---|
| 8 | Adicionar dependência `url_launcher` ao `pubspec.yaml` | 🟢 Concluído |
| 9 | Criar model `Documento` | 🟢 Concluído |
| 10 | Adicionar `ApiService.fetchDocumentos()` | 🟢 Concluído |
| 11 | Criar `DocumentosScreen` (lista, abre o arquivo externamente ao tocar) | 🟢 Concluído |
| 12 | Adicionar atalho na `HomeScreen` (7º item da grade) | 🟢 Concluído |
| 13 | Rodar `dart analyze` | 🟢 Concluído |

## Documentação e teste

| # | Item | Status |
|---|---|---|
| 14 | Atualizar `docs/05` e `docs/06` | 🟢 Concluído |
| 15 | Testar no celular físico (inclusive abrir um arquivo de verdade) | 🟢 Concluído (build/instalação/launch sem crash; abrir o PDF de verdade via `url_launcher` pendente de confirmação do usuário) |
