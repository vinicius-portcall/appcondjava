# Roadmap — Módulo Emergência / Monitoramento

Acompanhamento do desenvolvimento do módulo "Atendimento de Emergência / Monitoramento" (item 2.12 da `documentacao-tecnica-app.md`), segundo módulo novo do INOVASEG implementado sobre a base do Portcall.

Legenda de status: 🔴 Pendente · 🟡 Em andamento · 🟢 Concluído

**Status geral: 🟢 Módulo concluído e validado (14/08/2026).** Testado de ponta a ponta: alerta "Elevador Parado" enviado do celular real (ramal 5500) e confirmado no banco (`emergencia_alertas`). Extensão de ligação automática pra uma rota também implementada e validada via log do Asterisk (dois bugs pré-existentes de roteamento de apartamento corrigidos no caminho — ver seção própria abaixo).

Servidor de referência: `clienteauto.portcallvoip.com.br` (painel PHP em `/var/www/html`, banco `azcall`).

## Decisões de escopo (v1)

- 4 tipos de alerta, conforme a especificação: **Elevador Parado**, **Emergência**, **Entrada Assistida**, **Socorro Médico**.
- O morador toca o botão → app pede confirmação ("Confirma o alerta de [tipo]?") → envia → mostra sucesso/erro. Sem cancelamento após enviado (é um alerta, não uma reserva).
- "Central de monitoramento" nesta v1 = uma tela nova no painel administrativo (`alertas.php`) listando os alertas recebidos, mais recentes primeiro, com ação para marcar como "Atendido". Não há integração com sistema de monitoramento externo nem push notification nesta v1 (mesma decisão já tomada no módulo Mural).
- **Socorro Médico com janela de horário configurável**: dois campos novos em `app_config` (`socorro_medico_inicio`/`socorro_medico_fim`, tipo `TIME`, nulos = sempre disponível). O app esconde o botão fora da janela (UX), mas a validação de verdade é sempre no servidor (`api_alerta.php`) — nunca confiar só no relógio do celular.
- Tabela nova chamada `emergencia_alertas` (não `ramais_alertas`, que já existe pra outra coisa: monitoramento de queda/recuperação de ramal SIP — nomes diferentes de propósito para não confundir).
- Cada alerta grava `ramal` (quem enviou) e `condominio_id`; sem geolocalização/foto nesta v1.

## Backend (painel PHP + MySQL)

| # | Item | Status |
|---|---|---|
| 1 | Criar tabela `emergencia_alertas` no banco `azcall` | 🟢 Concluído |
| 2 | Adicionar colunas `socorro_medico_inicio`/`socorro_medico_fim` em `app_config` | 🟢 Concluído |
| 3 | Criar endpoint `api_alerta.php` (POST, autenticado por ramal/senha, valida janela de horário do Socorro Médico no servidor) | 🟢 Concluído |
| 4 | Expor a janela do Socorro Médico em `api_app_config.php` (branding) pro app saber quando esconder o botão | 🟢 Concluído |
| 5 | Criar página `alertas.php` no painel (listagem + marcar como atendido) | 🟢 Concluído |
| 6 | Adicionar campos de horário do Socorro Médico ao formulário existente de config do app (`app_download.php`) | 🟢 Concluído |
| 7 | Adicionar item "🚨 Emergência" no menu lateral | 🟢 Concluído |
| 8 | Testar `api_alerta.php` via curl no servidor (dentro e fora da janela de Socorro Médico) | 🟢 Concluído |

## App Flutter

| # | Item | Status |
|---|---|---|
| 9 | Estender `Branding` com a janela do Socorro Médico | 🟢 Concluído |
| 10 | Adicionar `ApiService.enviarAlerta()` | 🟢 Concluído |
| 11 | Criar `EmergenciaScreen` (4 botões + confirmação) | 🟢 Concluído |
| 12 | Adicionar entrada "Emergência" na `HomeScreen` (destaque visual, não é mais um ícone igual aos outros) | 🟢 Concluído |
| 13 | Rodar `dart analyze` para validar | 🟢 Concluído |

## Documentação e teste

| # | Item | Status |
|---|---|---|
| 14 | Atualizar `docs/05` e `docs/06` com o novo módulo | 🟢 Concluído |
| 15 | Testar no celular físico (build + instalar + validar fluxo) | 🟢 Concluído |

## Extensão: ligação automática pra uma rota configurada

Pedido do usuário: opção (por condomínio) pra habilitar/desabilitar, mais um campo pra escolher qual apartamento/rota (das já cadastradas em Rotas) recebe uma ligação de verdade quando um alerta de emergência é disparado — reaproveitando o mesmo motor de discagem (`rotas_horarios` + `portcall_router.agi`) que já existe pra chamadas normais de apartamento.

**Achado de segurança (não corrigido, fora de escopo — só registrado):** `/etc/sudoers` tem a linha `www-data ALL=NOPASSWD:ALL`, dando ao usuário do Apache/PHP sudo irrestrito como root, sem senha, pra qualquer comando — muito mais permissivo do que as regras específicas logo abaixo dela (`portcall-asterisk.sh`, `assign_ip.sh`, `ccd_rm.sh`). Qualquer vulnerabilidade de execução de código no painel PHP vira root instantâneo no servidor. Não mexi nisso — decisão do dono do servidor sobre quando/como reduzir esse escopo sem quebrar os scripts que dependem de sudo.

**Bug crítico encontrado no caminho (corrigido):** a tabela `condominios` não tinha a coluna `slug` que `portcall_router.agi` usa pra resolver o condomínio (`WHERE slug = ?`). Sem ela, **toda discagem de apartamento neste servidor falhava silenciosamente** — não é um bug introduzido por mim, é a mesma classe de problema do `app_botoes` faltando (schema incompleto neste clone do servidor). Corrigido: coluna `slug` adicionada e populada com `jardim_bot_nico_03` (o mesmo valor já gravado no `CONDOMINIO=` dos arquivos `.conf` do Asterisk pro condomínio 19) — confirmado via teste direto da query que o AGI usa.

| # | Item | Status |
|---|---|---|
| 16 | Corrigir coluna `slug` faltando em `condominios` (bloqueava toda discagem de apartamento, não só isso) | 🟢 Concluído |
| 17 | Colunas `emergencia_ligar_ativo` e `emergencia_apartamento` em `app_config` | 🟢 Concluído |
| 18 | Campo de checkbox + seletor de apartamento no formulário `app_download.php` (lista os apartamentos com rota ativa do condomínio) | 🟢 Concluído |
| 19 | `api_alerta.php` dispara a ligação via novo comando `alerta_ligar` em `portcall-asterisk.sh` (mesmo padrão de sudo restrito das outras ações), reaproveitando o cascade ramal→cel1→cel2 já existente. Roda em segundo plano (`exec(... &)`) pra não travar a resposta da API pelos até ~30s que a ligação pode levar | 🟢 Concluído |
| 20 | Testar com uma rota de teste segura (aponta só pro próprio ramal de teste, sem celular real) antes de habilitar em rota com número de celular de verdade | 🟢 Concluído |

### Segundo bug crítico encontrado e corrigido no caminho

`ensure_context_block()` (função que cria o bloco `[contexto]` em `extensions.conf` — onde mora o `AGI(portcall_router.agi,...)`) existia no script mas **nunca era chamada em lugar nenhum**, nem no caminho PJSIP nem no chan_sip. Ou seja: mesmo com o `slug` corrigido, nenhum condomínio novo (cujo primeiro ramal seja criado do zero, como o Jardim Botânico 03) teria esse bloco de dialplan — a discagem de apartamento simplesmente não existiria no Asterisk. Corrigido chamando `ensure_context_block` em `cmd_add_ramais` e `cmd_add_ramal_pjsip`, e reexecutado `add_ramal_pjsip` pro condomínio de teste pra gerar o contexto retroativamente. Confirmado via `dialplan show jardim_bot_nico_03` e teste real de originação (log do Asterisk mostrando o AGI resolvendo a rota e tentando discar).

**Achado menor (não corrigido):** a função `db_log_tentativa()` dentro do `portcall_router.agi` (grava cada tentativa de discagem em `cdr_tentativas`, só para fins de log/auditoria) está falhando silenciosamente neste servidor — o `catch (Throwable $e)` engole o erro sem registrar nada. Não afeta a chamada em si (confirmado que o `Dial()` acontece normalmente, só o log auxiliar que não grava). Provavelmente mais uma peça de schema faltando neste clone do servidor.

## Limitação conhecida: tronco PJSIP não carrega no Asterisk (não resolvido)

Depois de validar a ligação via ramal interno, o usuário pediu pra ir além: ligar de verdade pro celular do porteiro via um tronco de operadora. Isso expôs uma cadeia de problemas de infraestrutura, dos quais os dois primeiros foram corrigidos e o terceiro ficou pendente:

1. **Corrigido:** `troncos_novo.php` tentava inserir na coluna `codecs` (plural), mas a tabela `troncos_condominio` tem a coluna `codec` (singular) — crash ao salvar um tronco pelo painel. Só esse arquivo tinha o problema (`troncos_editar.php`/`troncos.php` não referenciam essa coluna).
2. **Achado, não corrigido — gerador de tronco não existia:** `troncos_condominio` (tabela onde o formulário salva) nunca foi lida por nenhum script/AGI — não existia nenhum código que pegasse essa linha do banco e gerasse a configuração real no Asterisk. Escrevi um gerador novo (`cmd_add_tronco_pjsip` em `portcall-asterisk.sh`), já que `chan_sip` está desligado neste servidor (só PJSIP funciona) — o `portcall_router.agi` ainda usa sintaxe antiga `SIP/tronco/numero` pra discar celular, que precisaria virar `PJSIP/numero@tronco` (não cheguei a alterar o AGI por causa do bloqueio abaixo).
3. **Não resolvido:** aplicando o gerador pro tronco `portcall-auto` (dados reais: host `linhas.portcallvoip.com.br`, usuário/senha configurados), o arquivo `.conf` gerado é sintaticamente válido e não colide com nada — mas o objeto `[portcall-auto]` do tipo `endpoint` simplesmente não aparece em `pjsip show endpoints`, sem nenhum erro de parse no log (`/var/log/asterisk/messages`). Os objetos dependentes no mesmo arquivo (`auth`, `aor`, `identify`, `registration`) carregam normalmente — só o endpoint em si falha silenciosamente. Testado reload normal e unload/load completo do módulo (esse último falha por uso ativo — 47 outras coisas dependem de `res_pjsip.so`). Backups do script em `/usr/local/sbin/portcall-asterisk.sh.bak3-*`.

**Próximos passos sugeridos para quem retomar isso:** `pjsip set logger on` durante um reload pra ver o tráfego SIP real; testar um endpoint mínimo isolado (só `[nome] type=endpoint` sem os objetos dependentes) pra ver se o problema é o objeto em si ou uma interação; considerar se é preciso reiniciar o Asterisk por completo (não só reload/module reload) dado que a transport não é "fully reloadable" segundo o próprio log.

## Teste em dispositivo real (14/08/2026)

Build reinstalado no Samsung SM S916B (sessão anterior tinha sido perdida por causa da reinstalação do APK, que limpa dados do app). Login refeito manualmente com o ramal `5500`. Alerta de "Elevador Parado" enviado pelo app e confirmado no banco do servidor.

**Nota de segurança registrada**: durante uma tentativa de automatizar o preenchimento do formulário de login via ADB, um `keyevent BACK` inesperado saiu do Portcall e abriu um app de banco/pagamentos do próprio celular do usuário, com um modal de oferta financeira na tela. Fechado pelo X sem tocar em nenhuma ação (nada de financeiro foi acionado), e a partir daí o teste final de login + envio do alerta foi feito manualmente pelo usuário, não mais por automação de toques no aparelho pessoal dele.
