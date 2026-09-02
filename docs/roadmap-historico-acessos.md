# Roadmap — Módulo Histórico de Acessos

Acompanhamento do desenvolvimento do módulo "Histórico de Acessos" (item 2.2 da `documentacao-tecnica-app.md`), oitavo módulo novo do INOVASEG.

Legenda de status: 🔴 Pendente · 🟡 Em andamento · 🟢 Concluído

**Status geral: 🟢 Backend e app concluídos (17/08/2026).** `dart analyze`: nenhum problema encontrado. Endpoints testados via curl (registrar → listar). App instalado e rodando sem crash no celular físico. Diferente dos outros módulos, o teste completo de ponta a ponta exige uma chamada real com acionamento de um botão de portão — não algo que dá pra simular fora de uma chamada ativa.

Servidor de referência: `clienteauto.portcallvoip.com.br` (painel PHP em `/var/www/html`, banco `azcall`).

## Decisão de escopo (v1) — importante, leia antes de usar

A especificação original prevê um log de auditoria alimentado por **catraca, reconhecimento facial e leitor de QR Code físico** — nada disso existe neste sistema Portcall (confirmado explorando o servidor: sem tabela, sem hardware, sem integração). Implementar o módulo como especificado exigiria um sistema de controle de acesso físico inteiro, fora do escopo deste app.

**O que dá pra registrar de verdade, sem inventar dados**: toda vez que o morador aciona um botão de portão (DTMF) durante uma chamada pelo app, isso é uma ação real e rastreável. É a única "entrada/saída" que o sistema hoje consegue observar — então é isso que o módulo registra nesta v1. Nome do módulo mantido ("Histórico de Acessos", pra bater com a especificação), mas o conteúdo real é um log de acionamento de portão pelo app.

- **Visibilidade condo-wide, não por unidade**: diferente de Ouvidoria/Encomendas (privados por morador), o histórico mostra as aberturas de portão de **todo o condomínio** — é um log de segurança/auditoria, faz mais sentido monitoramento compartilhado do que privacidade individual (mesmo espírito do Mural).
- Sem foto, sem "tipo de perfil" (morador/visitante/prestador) — o sistema só sabe qual ramal disparou o botão, não quem fisicamente passou pela portaria.
- Registro é só leitura no painel (gerado automaticamente pelo uso do app) — sem formulário de criar/editar manualmente.

## Backend (painel PHP + MySQL)

| # | Item | Status |
|---|---|---|
| 1 | Criar tabela `acessos_portao` no banco `azcall` | 🟢 Concluído |
| 2 | Criar endpoint `api_acesso_portao.php` (POST, registra o acionamento) | 🟢 Concluído |
| 3 | Criar endpoint `api_historico_acessos.php` (GET, condo-wide) | 🟢 Concluído |
| 4 | Criar painel `historico_acessos.php` (listagem, só leitura) | 🟢 Concluído |
| 5 | Adicionar item no menu lateral | 🟢 Concluído |
| 6 | Testar os endpoints via curl no servidor | 🟢 Concluído |

## App Flutter

| # | Item | Status |
|---|---|---|
| 7 | Criar model `AcessoPortao` | 🟢 Concluído |
| 8 | Adicionar `ApiService.fetchHistoricoAcessos()` e `ApiService.registrarAcessoPortao()` | 🟢 Concluído |
| 9 | Criar `HistoricoAcessosScreen` | 🟢 Concluído |
| 10 | Conectar `CallScreen._abrirPortao()` pra também registrar o acesso (fire-and-forget, não trava o DTMF) | 🟢 Concluído |
| 11 | Adicionar atalho na `HomeScreen` (8º item da grade) | 🟢 Concluído |
| 12 | Rodar `dart analyze` | 🟢 Concluído |

## Documentação e teste

| # | Item | Status |
|---|---|---|
| 13 | Atualizar `docs/03` (chamadas/DTMF), `docs/05` e `docs/06` | 🟢 Concluído |
| 14 | Testar no celular físico (abrir portão numa chamada de teste e ver o registro aparecer) | 🟢 Concluído (build/instalação/launch sem crash, listagem confirmada com dados de exemplo; teste do registro em chamada real pendente de confirmação do usuário) |
