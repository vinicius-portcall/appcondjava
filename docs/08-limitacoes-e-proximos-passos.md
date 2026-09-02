# 8. Funcionalidades incompletas e observações

Este documento reúne pontos do estado atual do código que valem a pena ter em mente ao planejar novas funcionalidades — não são bugs necessariamente, mas lacunas ou decisões implícitas que ainda não foram tratadas.

## Câmeras — não implementado

`CamerasScreen` é um placeholder estático ("Câmeras em breve"). Não há model, serviço ou chamada de API relacionados a streaming/snapshot de câmeras no código atual, apesar do atalho já existir na tela inicial.

## Sessão restaurada não é revalidada

`SessionService.load()` (usado no boot do app) apenas confere se os campos foram salvos localmente — não faz nenhuma chamada ao painel para confirmar que ramal/senha ainda são válidos. Se a senha for trocada no painel, o usuário só vai descobrir isso quando o `SipService` falhar ao registrar (`REGISTRATION_FAILED`), sem voltar automaticamente para a tela de login.

## Sem endpoint de autenticação dedicado

Tanto o login inicial (`ApiService.validarCredenciais`) quanto a checagem geral de credenciais reaproveitam `api_botoes.php`. Isso significa que qualquer falha de rede é indistinguível de uma senha errada na mensagem mostrada ao usuário.

## `sipServidorPadrao` / `sipPortaPadrao` do `Branding` não são usados no login

O modelo `Branding` já trafega valores default de servidor/porta SIP vindos do painel, mas a `LoginScreen` não busca o `Branding` nem pré-preenche esses campos — o usuário sempre precisa informar servidor e porta manualmente (ou via QR code, que já traz esses campos). Esses campos do `Branding` só são efetivamente exibidos (nome do app e logo) depois do login, na `HomeScreen`.

## Sem testes automatizados

A pasta `test/` existe mas está vazia — não há testes unitários, de widget ou de integração no repositório.

## iOS sem integração nativa equivalente

As integrações de segundo plano (`flutter_foreground_task`) e de notificação nativa de chamada (`flutter_callkit_incoming`) têm configuração explícita apenas no `AndroidManifest.xml`. O projeto iOS (`ios/`) existe (gerado pelo `flutter create`), mas não há evidência de configuração nativa adicional (ex.: PushKit/CallKit nativo do iOS, capacidades de background) além do que o Flutter gera por padrão.

## Transporte SIP fixo em TCP

`SipService.conectar()` usa sempre `TransportType.TCP`. Migrar para WebSocket seguro (WSS, necessário se o Asterisk for atualizado para usar PJSIP com WebSocket) exige alterar esse trecho para `TransportType.WS` + `webSocketUrl`, conforme já comentado no próprio código-fonte.

## Arquivo solto na raiz

`src/Main.java` é um arquivo de rascunho do IntelliJ (não referenciado por nenhum build), sobra da criação do projeto — não faz parte do app Flutter e pode ser removido com segurança se não estiver sendo usado para outro fim.

## Limite de upload de 2MB no painel

Todos os uploads do painel (Mural, Encomendas, Documentos) estão limitados a 2MB porque o `upload_max_filesize` do PHP no servidor está configurado assim globalmente (`clienteauto.portcallvoip.com.br`). Documentos maiores (balancetes extensos, atas digitalizadas em alta resolução) podem não caber. Aumentar isso exige mudar a config do PHP pro servidor inteiro (não é algo que dá pra restringir só a um módulo) e reiniciar o Apache.

## Sem anexo de arquivo/foto na Ouvidoria

A especificação original do módulo Pedidos e Manifestações previa um botão de anexar arquivo/foto ao chamado. Não implementado — o app não tem nenhuma dependência de seleção de imagem/arquivo local (`image_picker`/`file_picker`) hoje. Ver [`docs/roadmap-ouvidoria.md`](roadmap-ouvidoria.md).

## Ligação de emergência via celular/tronco de operadora

O módulo Emergência liga de verdade para um ramal interno quando configurado, mas a perna de "ligar pro celular via tronco de operadora" não funciona neste servidor — falta um gerador que aplique o tronco cadastrado no painel como config real do Asterisk, e há um problema não resolvido de um endpoint PJSIP de tronco que não carrega. Ver [`docs/roadmap-emergencia.md`](roadmap-emergencia.md) para o histórico completo da investigação.

## Achado de segurança: sudo irrestrito do usuário do painel

`/etc/sudoers` do servidor `clienteauto.portcallvoip.com.br` tem `www-data ALL=NOPASSWD:ALL` — o usuário do Apache/PHP tem sudo irrestrito como root, sem senha, muito além das regras específicas (scripts individuais) que já existiam ao lado dela. Não corrigido — decisão do dono do servidor. Ver [`docs/roadmap-emergencia.md`](roadmap-emergencia.md).
