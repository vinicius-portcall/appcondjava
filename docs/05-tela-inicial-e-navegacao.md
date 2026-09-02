# 5. Tela inicial, discagem e navegação

Arquivos principais: `lib/screens/home_screen.dart`, `lib/screens/dialpad_screen.dart`, `lib/screens/apartamentos_screen.dart`, `lib/screens/cameras_screen.dart`, `lib/screens/mural_screen.dart`, `lib/screens/emergencia_screen.dart`, `lib/screens/manutencoes_screen.dart`, `lib/screens/ouvidoria_screen.dart`, `lib/screens/novo_chamado_screen.dart`, `lib/screens/encomendas_screen.dart`, `lib/screens/documentos_screen.dart`, `lib/screens/historico_acessos_screen.dart`, `lib/models/app_button.dart`, `lib/models/aviso.dart`, `lib/models/manutencao.dart`, `lib/models/chamado.dart`, `lib/models/encomenda.dart`, `lib/models/documento.dart`, `lib/models/acesso_portao.dart`.

## `HomeScreen`: inicialização

Ao entrar (`initState` → `_iniciar()`), a `HomeScreen`, nesta ordem:

1. Solicita permissão de **microfone** (`Permission.microphone.request()`); se negada, mostra um aviso persistente (6s) de que as chamadas não vão funcionar até liberar nas configurações do celular. Segue mesmo assim (não bloqueia o app).
2. Solicita permissão de **câmera** (sem tratar o resultado — usada quando o usuário optar por vídeo).
2b. Inicia o `PushService` (`unawaited`, não bloqueia o resto) — pede permissão de notificação, registra o token FCM no backend e escuta mensagens recebidas com o app em primeiro plano. Ver [`docs/roadmap-central-notificacoes.md`](roadmap-central-notificacoes.md).
3. Busca o **branding** do condomínio via `ApiService.fetchBranding()`.
4. Busca os **botões configurados** e a **lista de apartamentos** via `ApiService.fetchBotoes()` — se falhar, cai para listas vazias (`catchError`) em vez de travar a tela.
4b. Busca os **avisos do mural** via `ApiService.fetchAvisos()` — mesma lógica de tolerância a falha (`catchError` para lista vazia).
5. Inicia o `ForegroundService` (ver [documento 4](04-segundo-plano-e-callkit.md)) e pede para ignorar otimização de bateria — falhas aqui são silenciadas.
6. Conecta o `SipService` ao servidor (`_sip.conectar(widget.conta)`).

## Botão de Emergência

Logo abaixo do chip de status do ramal, sempre visível (independentemente de haver botões/apartamentos/avisos ou não, e mesmo durante o carregamento inicial), há um botão de destaque em vermelho "Emergência" que abre a `EmergenciaScreen`. É posicionado fora da `ListView` condicional de conteúdo de propósito — diferente do Mural/Apartamentos/Câmeras, o acesso à emergência não deveria depender de o condomínio ter configurado outros conteúdos.



Um "chip" colorido logo abaixo da AppBar mostra o estado de registro SIP, atualizado a cada `notifyListeners()` do `SipService`:

| Estado SIP | Texto exibido | Cor |
|---|---|---|
| `REGISTERED` | "Online" | verde |
| `REGISTRATION_FAILED` | "Falha ao conectar" | vermelho |
| `UNREGISTERED` | "Desconectado" | laranja |
| outros (`NONE`, em progresso) | "Conectando…" | laranja |

## Navegação automática para a tela de chamada

`HomeScreen` assina o `SipService` (`_onSipChange`). Sempre que existe `activeCall` e `sip.emChamada` é verdadeiro e a `CallScreen` ainda não está aberta (`_callScreenAberta`), ela é empurrada automaticamente via `Navigator.push`, passando:
- o próprio `SipService`;
- os botões do tipo `dtmf` (filtrados de `_botoes`);
- se a chamada é entrante (`call.session.direction == Direction.incoming`).

A flag `_callScreenAberta` evita empurrar a tela mais de uma vez para a mesma chamada, e é resetada quando a `CallScreen` é fechada (`.then((_) => _callScreenAberta = false)`).

## Grade de conteúdo

O corpo da tela é uma `ListView` com:

1. **Ações rápidas** (`GridView.count`, 2 colunas, 8 itens): "Apartamentos" (mostra a contagem e só é clicável se houver unidades), "Câmeras" (sempre acessível, mas leva a uma tela ainda não implementada — ver [documento 8](08-limitacoes-e-proximos-passos.md)), "Mural" (contagem de avisos ativos), "Manutenções" (contagem de manutenções programadas), "Ouvidoria" e "Encomendas" (sempre acessíveis, sem contagem — buscam os próprios dados sob demanda em vez de vir pré-carregadas), "Documentos" (contagem de documentos publicados) e "Acessos" (contagem de acionamentos de portão registrados). Diferente das versões anteriores (uma `Row` fixa por linha), a grade virou `GridView` porque o número de atalhos foi crescendo módulo a módulo — encaixar mais um vira só adicionar um item à lista, sem reorganizar `Row`s manualmente.
2. **Grade de botões "Ramais"**: um card por `AppButton` do tipo `discar` (ordenados pelo campo `ordem` vindo do painel), cada um com dois botões de ação — chamada normal e chamada de vídeo (`_tocarBotao(botao, video: true/false)`).

A antiga mensagem "Nenhum botão configurado para este condomínio" (mostrada quando botões/apartamentos/avisos/manutenções estavam todos vazios) foi removida — como "Câmeras" e "Ouvidoria" são sempre acessíveis independentemente de qualquer configuração do condomínio, a grade nunca fica vazia de fato.

Ao tocar em um botão de discagem: se não houver `destino` configurado, não faz nada; se o SIP ainda não estiver registrado, mostra um aviso com o status atual; caso contrário, chama `sip.ligarPara(destino, video: ...)`. Erros de execução são capturados e exibidos em um `SnackBar`.

Botões do tipo `dtmf` **não aparecem nesta tela** — eles só têm efeito durante uma chamada (mostrados na `CallScreen`); se tocados fora de uma chamada (não deveria ocorrer, já que a grade da Home só lista os do tipo `discar`), mostrariam o aviso "Esse botão só funciona durante uma chamada ativa."

## `DialpadScreen`

Teclado numérico livre (0–9, `*`, `#`) para digitar qualquer número/ramal, com botão de apagar e dois botões de chamada (voz e vídeo). Também verifica `sip.isRegistered` antes de discar, e fecha a própria tela (`Navigator.pop`) assim que a chamada é iniciada.

## `ApartamentosScreen`

Lista todas as unidades retornadas pelo painel (mesma lista de rotas ativas usada na página "Rotas" do painel administrativo), uma por linha, cada uma com botão de chamada normal e de vídeo. Mesma checagem de `isRegistered` antes de ligar.

## `CamerasScreen`

Tela placeholder — exibe apenas um ícone e o texto "Câmeras em breve" / "Essa funcionalidade ainda está sendo configurada para o seu condomínio." Não há integração real com câmeras implementada (ver [documento 8](08-limitacoes-e-proximos-passos.md)).

## `MuralScreen`

Lista somente leitura dos avisos do condomínio (título, imagem opcional, mensagem, autor e data), publicados exclusivamente pelo painel administrativo — o app não tem tela de criação/edição de avisos. Recebe a lista de `Aviso` já carregada pela `HomeScreen` (mesmo padrão de `ApartamentosScreen`: os dados são buscados uma vez em `_iniciar()` e passados via construtor, sem fetch próprio na tela). Se não houver avisos, mostra "Nenhum aviso publicado."; se um aviso tiver imagem, ela é exibida via `Image.network` no topo do card (com `errorBuilder` silencioso caso a URL falhe).

## `EmergenciaScreen`

Lista os 4 tipos de alerta da especificação (Elevador Parado, Emergência, Entrada Assistida, Socorro Médico) como botões grandes em vermelho. Recebe `ApiService`, `SipAccount` (pra autenticar o envio) e `Branding` (pra saber a janela de disponibilidade do Socorro Médico).

- Tocar um botão abre um `AlertDialog` de confirmação antes de enviar — é um alerta, não uma ação reversível, então não há "cancelar depois de enviado".
- Confirmado, chama `ApiService.enviarAlerta(ramal, senha, tipo)`; sucesso/erro aparece em `SnackBar`.
- O botão "Socorro Médico" só aparece na lista se `Branding.socorroMedicoDisponivelAgora` for verdadeiro — getter que replica no cliente (só para efeito de exibição/UX) a mesma lógica de janela de horário que o servidor aplica de verdade em `api_alerta.php`. Suporta janela que cruza a meia-noite (ex: 22:00 às 06:00). Sem janela configurada pelo condomínio (`socorro_medico_inicio`/`fim` nulos), o botão fica sempre disponível.
- **A validação real da janela de horário é sempre no servidor** — a checagem no app é só para não mostrar um botão que o servidor vai rejeitar; nunca confiar no relógio do celular como fonte de verdade.

## `ManutencoesScreen`

Lista as manutenções prediais programadas (equipamento, descrição opcional, datas), também somente leitura e cadastrada só pelo painel. Recebe a lista de `Manutencao` já carregada pela `HomeScreen` — mesmo padrão de dados pré-buscados usado em `ApartamentosScreen`/`MuralScreen`.

`Manutencao.diasRestantes` calcula, no cliente, quantos dias faltam até `proximaManutencao` (negativo = atrasada) — não é um valor vindo do servidor, é recalculado toda vez que a tela é montada, então nunca fica desatualizado. A cor do card muda conforme a urgência: vermelho se atrasada, laranja se faltam 30 dias ou menos, cor neutra caso contrário.

## `OuvidoriaScreen` e `NovoChamadoScreen`

Primeiro par de telas onde o morador **escreve** pelo app, não só lê — pedidos, dúvidas e reclamações endereçados à administração (item "Pedidos e Manifestações" da especificação). Diferente de Mural/Manutenções, os dados **não** vêm pré-carregados da `HomeScreen`: `OuvidoriaScreen` recebe `ApiService`/`SipAccount`/lista de apartamentos via construtor e busca a lista de chamados sozinha (`initState` → `_carregar()`), porque a lista precisa ser recarregada depois que o morador envia um chamado novo — não faria sentido reaproveitar um snapshot buscado no login.

- **Isolamento por morador**: `api_chamados.php` filtra por `condominio_id` **e** `ramal` de quem está logado — cada morador só vê os próprios chamados, diferente do Mural (que é público para todo o condomínio). É uma diferença de modelo de dados no backend, não só de UI.
- Pull-to-refresh (`RefreshIndicator`) além do recarregamento automático ao voltar da tela de novo chamado.
- Cada card mostra assunto, mensagem, unidade/data e um selo de status colorido (aberto = vermelho, em andamento = laranja, respondido = verde, fechado = cinza); se houver `resposta` da administração, aparece destacada em verde dentro do próprio card.
- `NovoChamadoScreen` é um formulário simples (`Form` + `TextFormField`s) com validação local de campos obrigatórios (assunto, mensagem); a unidade é opcional e escolhida a partir da mesma lista de apartamentos que já alimenta `ApartamentosScreen`. Ao enviar com sucesso, faz `Navigator.pop(true)` — é esse `true` que sinaliza a `OuvidoriaScreen` para recarregar a lista.
- **Sem anexo de arquivo/foto nesta versão**, apesar de a especificação original prever isso — o projeto não tem nenhuma dependência de seleção de imagem/arquivo hoje (nem `image_picker` nem `file_picker` estão no `pubspec.yaml`); ver [documento 8](08-limitacoes-e-proximos-passos.md).

## `HistoricoAcessosScreen`

Une três fontes reais de acesso — leia [`docs/roadmap-integracao-facial-controlid.md`](roadmap-integracao-facial-controlid.md) e [`docs/roadmap-qrcode-visitante.md`](roadmap-qrcode-visitante.md) pra entender a evolução do escopo:

1. **Acionamentos de botão de portão (DTMF) pelo app** — gerado automaticamente em `CallScreen._abrirPortao()`.
2. **Eventos de um leitor facial Control iD** — recebidos via webhook (`webhook_controlid_dao.php`) quando o condomínio tem um equipamento cadastrado em Dispositivos Faciais.
3. **Passes de QR Code de visitante validados na portaria** — gerados na `VisitantesQrScreen` e confirmados manualmente em `portaria_qr.php` (sistema próprio, não integrado ao leitor de QR nativo do Control iD).

Ainda **não cobre catraca** (não existe hardware desse tipo integrado) — a tela tem um aviso fixo no topo deixando isso claro.

- `AcessoPortao.tipo` (`portaoApp`/`facial`/`qrcode`/`outro`) distingue a origem de cada linha — ícone e texto diferentes por tipo (`_iconePara`/`_titulo`/`_subtitulo`).
- Recebe a lista já carregada pela `HomeScreen` (mesmo padrão pré-buscado de Mural/Manutenções/Documentos) — o backend já entrega os três tipos combinados e ordenados por data em `api_historico_acessos.php` (`UNION ALL` de `acessos_portao` + `acessos_facial` + `visitantes_qr` com `status='usado'`).
- **Visível para todo o condomínio, não filtrado por morador** — diferente de Ouvidoria/Encomendas (privados por unidade), aqui faz mais sentido tratar como um log de segurança compartilhado (mesmo espírito do Mural): todo morador pode ver quando qualquer portão foi aberto ou alguém foi identificado, não só o seu próprio uso.
- **Sem nome do usuário identificado pelo facial** — o Control iD só manda um `user_id` numérico interno do próprio equipamento; resolver isso pra um nome exigiria autenticar de volta no equipamento (fora do escopo atual). A tela mostra "ID reconhecido: N".

## `VisitantesQrScreen`

Visitante esperado, nos dois métodos que a especificação prevê — tela com duas abas, `TabController` próprio (`SingleTickerProviderStateMixin`), FAB muda de ação conforme a aba ativa.

### Aba "QR Code"

Passe de visitante em QR Code, gerado pelo morador — ver [`docs/roadmap-qrcode-visitante.md`](roadmap-qrcode-visitante.md) pro raciocínio completo por trás da decisão de escopo.

- Morador informa nome do visitante, observação opcional e validade (1h a 3 dias); o backend gera um `codigo` aleatório de uso único (`api_qr_criar.php`) que vira o conteúdo do QR renderizado com `qr_flutter` (`QrImageView`).
- Lista os passes já gerados pelo próprio ramal (`api_qr_listar.php`), com status `Ativo`/`Usado`/`Expirado`/`Cancelado`; passes `Ativo` podem ser cancelados (`api_qr_cancelar.php`) ou reabertos pra mostrar o QR de novo.
- **Validação é manual, na portaria** — não há integração com o leitor de QR nativo do equipamento Control iD (decisão explícita do usuário, ver o roadmap). A portaria digita ou escaneia o código em `portaria_qr.php` no painel; ao confirmar, o passe muda pra `usado` e aparece no Histórico de Acessos.

### Aba "Lista (portaria)"

Segundo método, mais informal — ver [`docs/roadmap-convidados-lista.md`](roadmap-convidados-lista.md).

- Morador avisa nome do convidado, observação opcional e período (data/hora início e fim); sem QR, sem código, é só um aviso (`api_convidado_criar.php`).
- **Sem validação de identidade** — a portaria vê a lista de quem está esperado (`portaria_convidados.php`) e deixa entrar por conferência visual/nominal, sem checagem automática. Marcar a chegada é uma ação manual da portaria, separada do Histórico de Acessos (que é sobre abertura de portão/identificação, não sobre aviso de expectativa de visita).
- Convidado `aguardando` pode ser cancelado pelo morador (`api_convidado_cancelar.php`); expira sozinho (`status = 'expirado'`) se o período passar sem chegada registrada.

## `AgendamentosScreen`

Reserva de espaços comuns (Academia, Churrasqueira, Salão de Festas etc.) — ver [`docs/roadmap-agendamentos.md`](roadmap-agendamentos.md) pro raciocínio de escopo.

- Duas abas: **Reservar** (escolher espaço → escolher data → escolher um horário pronto na grade de disponibilidade) e **Minhas reservas** (histórico do próprio ramal, com opção de cancelar).
- **Slots fixos, não hora livre** — cada espaço tem uma janela (`horario_abertura`/`horario_fechamento`) dividida em intervalos de duração fixa (`duracao_slot_minutos`); o morador escolhe um intervalo já pronto (`api_agenda_disponibilidade.php` calcula os slots e marca ocupado/livre comparando com reservas existentes no banco).
- Ao confirmar (`api_agendamento_criar.php`), pode informar uma lista de convidados em texto livre (sem cadastro individual por convidado).
- Cancelamento (`api_agendamento_cancelar.php`) respeita uma antecedência mínima configurada por espaço (`antecedencia_cancelamento_horas`) — o botão de cancelar só aparece quando `Agendamento.podeCancelar` é `true` (calculado no próprio app a partir da data/hora da reserva e da antecedência, mas a validação final é sempre feita de novo no servidor).
- **Sem pagamento real** — a `taxa` do espaço é só informativa, mostrada na hora de confirmar a reserva.

## `PushService` (Central de Notificações)

Sem tela própria — é um serviço que roda em segundo plano desde que a `HomeScreen` abre. Ver [`docs/roadmap-central-notificacoes.md`](roadmap-central-notificacoes.md) pro raciocínio completo (incluindo por que o backend não usa o Firebase Admin SDK/composer).

- `lib/services/push_service.dart` — pede permissão de notificação (`FirebaseMessaging.requestPermission()`), pega o token do dispositivo e registra via `api_push_registrar.php`; reregistra sozinho se o token mudar (`onTokenRefresh`).
- **Só um token por ramal** — se o morador loga em outro celular, o token antigo é sobrescrito (`ON DUPLICATE KEY UPDATE` na tabela `dispositivos_push`); o dispositivo anterior para de receber push.
- **Mensagens em primeiro plano precisam de tratamento manual** — o FCM não mostra notificação sozinho com o app aberto; a `HomeScreen` escuta `FirebaseMessaging.onMessage` e mostra um `SnackBar` (`_mostrarNotificacaoPrimeiroPlano`). Em segundo plano ou com o app fechado, o Android mostra a notificação nativamente sem nenhum código extra.
- **Eventos que disparam push** (do lado do servidor): novo aviso no mural, nova encomenda registrada, reserva de espaço comum confirmada/cancelada, convidado marcado como chegado na portaria.
- Falha ao pedir permissão, obter token ou registrar não trava o login — é tudo best-effort, com todo `catch` silencioso.

## `EncomendasScreen`

Encomendas recebidas na portaria para a unidade do morador. Assim como `OuvidoriaScreen`, busca os próprios dados sob demanda (`ApiService`/`SipAccount` via construtor, sem lista pré-carregada da `HomeScreen`) — porque o morador precisa ver o estado atualizado ("retirada" ou não) toda vez que abre a tela, não um snapshot do login.

- **De onde vem "minha unidade"**: o app não guarda o apartamento do morador em lugar nenhum. O backend descobre isso reaproveitando a relação que já existe em Rotas (apartamento → ramal): resolve o(s) apartamento(s) associados ao ramal logado e filtra as encomendas por eles. Consequência prática: um ramal sem nenhuma rota cadastrada nunca verá nenhuma encomenda, mesmo que existam encomendas registradas pra outras unidades do mesmo condomínio.
- **A foto é tirada pela portaria**, não pelo morador — cadastrada via upload no painel administrativo (mesmo padrão do Mural: PNG/JPG/WEBP até 2MB). O app só exibe (`Image.network`), nunca envia foto.
- Cada card mostra tipo (ícone diferente por tipo: pacote, carta, envelope, remédio, outro), código de rastreio e informação adicional (ambos opcionais), foto (se houver) e um botão **Confirmar retirada** para as pendentes — abre um diálogo pedindo o nome de quem está retirando (pode não ser o próprio morador: porteiro, familiar etc.), e ao confirmar, recarrega a lista.
- `api_encomenda_retirar.php` valida no servidor que a encomenda pertence a uma das unidades do ramal que está confirmando — não dá pra confirmar retirada de uma encomenda de outro apartamento só sabendo o `id`.

## `DocumentosScreen`

Repositório de documentos do condomínio (balancetes, regimento interno, atas de assembleia) — somente leitura, publicado só pelo painel. Recebe a lista de `Documento` já carregada pela `HomeScreen`, mesmo padrão pré-buscado de `MuralScreen`/`ManutencoesScreen` (diferente de Ouvidoria/Encomendas, que buscam sob demanda).

Tocar num item chama `url_launcher` (`launchUrl(uri, mode: LaunchMode.externalApplication)`) pra abrir o arquivo no navegador/leitor de PDF do próprio celular — o app não tem visualizador de PDF embutido. **Esta é a primeira tela do app que depende de um pacote adicionado especificamente para ela** (`url_launcher`, em `pubspec.yaml`); diferente da decisão de adiar o anexo de arquivo na Ouvidoria, aqui a dependência nova se justificou porque "abrir o documento" é a própria função do módulo, não um extra.
