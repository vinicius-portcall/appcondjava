# Roadmap — Central de Notificações (Firebase Cloud Messaging)

Notificações push de verdade (chegam mesmo com o app fechado/em segundo plano), pra avisos do mural, encomendas, agendamentos e convidados.

Legenda de status: 🟢 Concluído · 🟡 Em andamento · 🟢 Concluído

Servidor de referência: `clienteauto.portcallvoip.com.br`. Projeto Firebase: `portchat-46646` (compartilhado com outro produto do usuário — o app Android foi cadastrado nesse mesmo projeto Firebase com o pacote `br.com.portcall.portcall_app`, sem mexer no app existente `br.com.portcallvoip.portchat`).

## Decisões de escopo (v1) — leia antes de usar

- **FCM HTTP v1 API, sem SDK/composer** — o backend PHP deste projeto é flat-files sem framework nem composer. Em vez de instalar o Firebase Admin SDK (que puxa uma dependência pesada via composer), implementei a autenticação OAuth2 manualmente: monta um JWT assinado com a chave privada da conta de serviço (`openssl_sign`, RS256), troca por um access token em `oauth2.googleapis.com/token`, e chama `fcm.googleapis.com/v1/projects/portchat-46646/messages:send` via `curl`. Só depende das extensões `openssl`/`curl`/`json`, que o PHP do servidor já tem.
- **Chave de conta de serviço fora do diretório público** — fica em `/etc/portcall/fcm-service-account.json` (fora de `/var/www/html/`), não em lugar nenhum acessível via HTTP, nem que a config do Apache mude amanhã. Só o PHP lê o arquivo direto do disco.
- **Um token por ramal** — tabela `dispositivos_push` guarda o último token FCM de cada ramal (o app registra de novo toda vez que abre; se o token mudar, sobrescreve). Não há suporte a múltiplos dispositivos por ramal nesta v1 — se o morador usa o app em dois celulares, só o mais recente recebe push.
- **Eventos disparadores nesta v1**: novo aviso no Mural, nova encomenda registrada, confirmação/cancelamento de agendamento, convidado marcado como chegou na portaria. Fora do escopo: eventos de histórico de acessos (facial/portão/QR) — vira muito volume de notificação pra pouco valor.
- **Sem tela de "histórico de notificações" no app nesta v1** — o push aparece na bandeja do sistema operacional (com a UI nativa do Android/iOS); não persiste uma lista própria dentro do app. Se um dia isso for pedido, dá pra guardar as notificações enviadas numa tabela e expor via API.

## Backend (MySQL + PHP)

| # | Item | Status |
|---|---|---|
| 1 | Copiar a chave de conta de serviço pra `/etc/portcall/fcm-service-account.json` (fora do webroot) | 🟢 Concluído |
| 2 | Criar tabela `dispositivos_push` no banco `azcall` | 🟢 Concluído |
| 3 | `api_push_registrar.php` (POST, auth ramal+senha) — salva/atualiza o token FCM do ramal | 🟢 Concluído |
| 4 | `fcm_helper.php` — gera access token OAuth2 (JWT assinado) e envia mensagem via FCM HTTP v1 | 🟢 Concluído |
| 5 | Testar o envio via curl/script isolado (confirmar que chega no dispositivo) | 🟢 Concluído |
| 6 | Disparar push em: novo aviso (mural), nova encomenda, agendamento confirmado/cancelado, convidado chegou | 🟢 Concluído |

## App Flutter

| # | Item | Status |
|---|---|---|
| 7 | Adicionar `firebase_core` e `firebase_messaging`; `google-services.json` em `android/app/`; plugin do Gradle | 🟢 Concluído |
| 8 | Pedir permissão de notificação, obter o token e registrar via `api_push_registrar.php` (ao logar/abrir o app) | 🟢 Concluído |
| 9 | Mostrar notificação quando o app está em primeiro plano (FCM não mostra sozinho nesse caso) | 🟢 Concluído |
| 10 | `dart analyze` + build/install/launch no device conectado | 🟢 Concluído |
| 11 | Atualizar `docs/05` e `docs/06` | 🟢 Concluído |
