# Roadmap — Integração facial Control iD (extensão do Histórico de Acessos)

Extensão do módulo Histórico de Acessos pra receber eventos reais de um equipamento de reconhecimento facial **Control iD**, via o mecanismo "Monitor" da API deles (webhook — o equipamento envia os eventos, não o servidor busca).

Legenda de status: 🔴 Pendente · 🟡 Em andamento · 🟢 Concluído

Servidor de referência: `clienteauto.portcallvoip.com.br`.

## Como funciona (documentação oficial consultada)

- Fonte: [Introdução ao Monitor](https://www.controlid.com.br/docs/access-api-pt/monitor/introducao-ao-monitor/) e [Eventos de Identificação Online](https://www.controlid.com.br/docs/access-api-pt/modos-de-operacao/eventos-de-identificacao-online/), documentação oficial Control iD.
- O equipamento é configurado (`/set_configuration.fcgi`, campo `monitor`) com `hostname`/`port`/`path` do nosso servidor.
- A cada identificação, o equipamento faz **POST** pra `hostname:port/{path}/dao` com um JSON `object_changes` contendo `object: "access_logs"` e `values` (`id`, `time` unix, `event`, `device_id`, `identifier_id`, `user_id`, `portal_id`, ...).
- Não há autenticação/token no payload — o próprio Control iD não manda nenhum segredo. Mitigação adotada: usar um `path` longo e aleatório (não adivinhável) em vez de algo óbvio como `/controlid`, e validar que o `device_id` recebido bate com um dispositivo já cadastrado no nosso banco antes de aceitar o evento.

## Decisões de escopo (v1) — leia antes de usar

- **Nome e foto do identificado, quando o dispositivo tem IP local + credenciais admin cadastrados** — ver seção "Nome e foto do identificado" abaixo. Sem essas credenciais, o histórico mostra só o `user_id` bruto (fallback original).
- **Um servidor pode atender vários equipamentos/condomínios** — tabela `controlid_dispositivos` mapeia `device_id` (vem no payload) → `condominio_id`, cadastrada manualmente no painel antes do equipamento começar a mandar eventos de verdade.
- **`AllowOverride None` no Apache impede `.htaccess`** — a rota `/{path}/dao` é criada direto no vhost (`000-default-le-ssl.conf`) via `RewriteRule`, não por arquivo físico. Mudança feita com backup do vhost, `apache2ctl configtest` antes de recarregar, e `systemctl reload apache2` (não `restart`).
- **O "Monitor" do Control iD não fala HTTPS/TLS** — confirmado num equipamento real (iDFace, firmware 8.4.0): configurado com `port: 443` a conexão nunca chegava no Apache (nem erro no log — a tentativa de handshake TLS com um cliente que só fala HTTP puro simplesmente não completa). A solução foi abrir uma exceção **também na porta 80**, direto no vhost `000-default.conf` (que normalmente redireciona tudo pra HTTPS): uma `RewriteRule` pro path exato do webhook, com `[L]`, *antes* da regra geral de redirect — só essa rota específica escapa do HTTPS, o resto do site continua redirecionando normal. O equipamento foi reconfigurado pra `port: 80` e passou a funcionar. Documentado aqui porque não é óbvio — a maioria dos exemplos oficiais da Control iD usa portas não-443 (ex.: 8000), o que já era uma pista.
- Testado com equipamento físico real do usuário (IP local `192.168.0.254`, alcançado via túnel WireGuard já existente do servidor até a rede do usuário) — device_id `4409419584545677` cadastrado, Monitor configurado, identificação de teste confirmada chegando em `acessos_facial`.

## Nome e foto do identificado (v2, adicionado depois do teste inicial)

- **Nome**: quando um `device_id` tem `ip_local`/`admin_login`/`admin_senha` cadastrados em `controlid_dispositivos`, `webhook_controlid_dao.php` faz uma chamada de volta *pro próprio equipamento* (não confundir com o Monitor, que é o equipamento chamando a gente) — login em `/login.fcgi`, depois `/load_objects.fcgi` com `{"object":"users","fields":["id","name"],"where":{"users":{"id":user_id}}}` — pra resolver o nome. Implementado em `controlid_helper.php` (`controlid_resolver_nome()`), best-effort (qualquer falha só deixa o nome em branco).
  - Só funciona se o servidor tiver rota até o IP local do equipamento (nesta instalação, via o túnel WireGuard já existente até a rede do usuário). Cada condomínio com equipamento próprio precisaria de uma rota equivalente até a rede dele — não é algo que escala sozinho pra múltiplos condomínios com equipamentos em redes diferentes sem alguma solução de VPN por condomínio.
  - Credenciais do equipamento ficam salvas em `controlid_dispositivos.admin_senha` (banco, mesmo nível de proteção que outras senhas do sistema — não teve pedido de criptografia adicional).
- **Foto**: o Control iD manda a foto como um evento **separado** do `/dao`, em `POST /{path}/access_photo`, com `{"device_id", "time", "user_id", "access_photo": "<jpeg base64>"}` — só quando `enable_photo_upload: "1"` está configurado no Monitor (não tem campo de "habilitar" único; é uma opção dentro do mesmo módulo `monitor`). Implementado em `webhook_controlid_access_photo.php`, decodifica o base64 e salva em `uploads/`.
- **Sem ordem garantida entre `/dao` e `/access_photo`** — testado com equipamento real e confirmado que a foto pode chegar **antes** do evento principal (visto 1s de diferença). Os dois webhooks casam por `controlid_device_id` + `ocorrido_em` (dentro de uma janela de ±5s, não igualdade exata — clock do equipamento pode não bater no segundo com o `time` gravado). Quem chegar primeiro cria uma linha "esqueleto" em `acessos_facial` (sem `evento_codigo` ainda); quem chegar depois completa essa mesma linha em vez de criar uma duplicada.
- Painel `dispositivos_facial.php` virou uma tela de cadastro **e edição** (antes só tinha "criar") — precisa pra poder acrescentar IP local/credenciais num dispositivo já cadastrado sem apagar e recriar.
- **Duas fontes de foto, escolhidas por dispositivo** (`controlid_dispositivos.tipo_foto`, editável no painel): `acesso` (padrão — foto do instante da identificação, via evento `/access_photo` do Monitor, precisa `enable_photo_upload: "1"`) ou `cadastro` (foto de referência já salva no equipamento, buscada direto via `GET /user_get_image.fcgi?user_id=...&session=...` — a mesma foto usada no cadastro facial da pessoa, resolvida de forma síncrona dentro do próprio `/dao`, sem depender do Monitor mandar nada extra). Implementado em `controlid_baixar_foto_cadastro()` (`controlid_helper.php`). Testado com o equipamento real nos dois modos.

## QR Code do app lido direto no leitor físico (exploratório, 2026-08-19)

Teste de ponta a ponta: pegar um passe de visitante gerado pelo app (`visitantes_qr`) e fazer o leitor físico do
Control iD (mesmo equipamento iDFace da seção acima) reconhecer e liberar o acesso lendo o QR na tela do celular.
**Feito manualmente via SSH/curl contra a API do próprio equipamento** (não está automatizado no
`api_qr_criar.php`/`api_qr_cancelar.php` reais — só prova de conceito). Três problemas em sequência, cada um só
descoberto testando com o equipamento físico de verdade:

1. **Modo do QR Code vem "somente numérico" por padrão** — o iDFace aceita QR só com conteúdo numérico de 64 bits
   por padrão (`face_id.qrcode_legacy_mode_enabled: "1"`), e nossos códigos são hex/alfanumérico
   (`visitantes_qr.codigo`, ex: `82C435AECC8233B7`). Sem trocar pra modo alfanumérico, o equipamento nem tenta
   casar o valor contra a tabela `qrcodes` — resultado era a câmera tentando reconhecimento **facial** no próprio
   padrão do QR (por isso "só aparece o óvalo de rosto" na tela, sem opção visível de modo QR). Corrigido via
   `set_configuration.fcgi`: `{"face_id": {"qrcode_legacy_mode_enabled": "0"}}` (valores: `0`=alfanumérico via
   objeto `qrcodes`, `1`=numérico via objeto `cards`, `2`=hexadecimal via `cards`).
2. **Usuário temporário criado sem grupo → identificado mas "não autorizado"** — criar o `users` (`user_type_id: 1`,
   `begin_time`/`end_time`) e o `qrcodes` vinculado não é suficiente pra liberar acesso: o usuário precisa
   pertencer a um `groups` que esteja de fato linkado a um `access_rules` (objeto `group_access_rules`, **não**
   `access_rules_groups`), e esse `access_rules` precisa estar linkado ao `portals` (objeto
   `portal_access_rules`) e a um `time_zones` válido (objeto `access_rule_time_zones`). Sem o
   `group_access_rules`, o equipamento identifica corretamente (mostra o nome) mas nega no portal
   (`access_logs.event = 6`). Resolvido adicionando o usuário ao grupo "Padrão" já usado pelos moradores reais
   (`create_objects.fcgi` em `user_groups`).
3. **Ainda negava mesmo com grupo/regra/portal/horário certos — toggle "Necessita de visita"** — mesmo com todo o
   encadeamento de autorização correto, o tipo de usuário "Visitante" no equipamento tem, na interface web local
   (**não exposto pela API `get_configuration.fcgi`/`load_objects.fcgi`** — não achado por nenhuma combinação de
   nome de objeto/campo testada), uma opção em **Cadastro → Tipo de usuário → Visitantes → "Necessita de visita"**
   que, habilitada (padrão), exige um registro de visita agendada/ativa pra liberar o acesso de qualquer usuário
   `user_type_id: 1`, mesmo já autorizado por grupo/regra. Desabilitada essa opção na interface web
   (`http://192.168.0.254`, login admin), o acesso passou a ser liberado normalmente (`access_logs.event = 7`).
   **Isso afeta TODOS os usuários tipo Visitante do equipamento, não só os de teste** — vale considerar se
   desabilitar isso globalmente é aceitável pro condomínio, ou se no futuro vale criar as visitas via API
   (`visits`, não explorado ainda) em vez de desabilitar a exigência.
   - Código de evento em `access_logs`/`acessos_facial.evento_codigo`: `3` = não identificado, `6` = identificado
     mas não autorizado, `7` = acesso concedido.
   - Objetos de teste ainda no equipamento (não automatizados, não limpos): `users` id=25 ("keven (visitante)"),
     `qrcodes` id=3 (valor do passe id=6 do app).

## Backend (painel PHP + MySQL + Apache)

| # | Item | Status |
|---|---|---|
| 1 | Criar tabelas `controlid_dispositivos` e `acessos_facial` no banco `azcall` | 🟢 Concluído |
| 2 | Editar vhost Apache (`RewriteRule` pra rota do webhook, path aleatório) — com backup e `configtest` antes do reload | 🟢 Concluído |
| 3 | Criar `webhook_controlid_dao.php` (recebe o POST do equipamento, valida `device_id`, grava o evento) | 🟢 Concluído |
| 4 | Testar simulando o POST do equipamento via curl (payload exato da documentação) | 🟢 Concluído — testado device_id não cadastrado (ignorado) e cadastrado (gravou certinho, isolado por `condominio_id`) |
| 5 | Criar painel `dispositivos_facial.php` (cadastrar/editar `device_id` → condomínio, ver a URL/path a configurar no equipamento) | 🟢 Concluído |
| 6 | Adicionar item no menu lateral | 🟢 Concluído |

## Integração com o Histórico de Acessos existente

| # | Item | Status |
|---|---|---|
| 7 | Unificar `api_historico_acessos.php` pra trazer também os eventos de `acessos_facial` (campo `tipo`: `portao_app` / `facial`) | 🟢 Concluído |
| 8 | Atualizar `AcessoPortao`/`HistoricoAcessosScreen` no app pra mostrar os dois tipos (ícone diferente) | 🟢 Concluído |
| 9 | Atualizar `historico_acessos.php` no painel do mesmo jeito | 🟢 Concluído |
| 10 | `dart analyze` + docs (`docs/05`, `docs/06`) | 🟢 Concluído |

## Passo a passo pendente do lado do usuário (fora do meu alcance)

| # | Item | Status |
|---|---|---|
| 11 | Cadastrar o `device_id` real do equipamento em `dispositivos_facial.php` | 🟢 Concluído — `4409419584545677`, condomínio Jardins |
| 12 | Configurar o Monitor no painel do Control iD apontando pra URL/porta/path gerados | 🟢 Concluído — precisou porta 80 (HTTP), não 443 (ver decisões de escopo) |
| 13 | Fazer uma identificação facial de teste no equipamento e conferir se aparece no Histórico de Acessos | 🟢 Concluído — evento gravado em `acessos_facial` em 2026-08-19 |
