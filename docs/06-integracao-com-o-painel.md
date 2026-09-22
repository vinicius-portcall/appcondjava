# 6. Integração com o painel (API)

Arquivo principal: `lib/services/api_service.dart`. O backend PHP em si (`api_app_config.php`, `api_botoes.php`, `api_mural.php`, `api_alerta.php`, `api_manutencoes.php`, `api_chamado_criar.php`, `api_chamados.php`, `api_encomendas.php`, `api_encomenda_retirar.php`, `api_documentos.php`, `api_acesso_portao.php`, `api_historico_acessos.php`, `ramal_qrcode.php`) **não faz parte deste repositório** — o app apenas consome essas rotas.

## `ApiService`

Construído com a `painelUrl` salva na sessão (`SipAccount.painelUrl`). Monta URLs concatenando o caminho ao host base (removendo barra final duplicada) e usa um timeout de **8 segundos** em todas as requisições.

### `fetchBranding(ramal, senha)` → `GET api_app_config.php?ramal=&senha=`

Busca a identidade visual do condomínio:

```json
{
  "ok": true,
  "app_nome": "Nome do Condomínio",
  "logo_url": "https://.../logo.png",
  "sip_servidor": "sip.exemplo.com",
  "sip_porta": "5060"
}
```

Mapeado para o modelo `Branding` (`lib/models/branding.dart`). **É tolerante a falhas**: qualquer exceção (rede, timeout, JSON inválido) ou `ok != true` faz o método devolver `Branding.fallback()` (nome fixo "Portcall", sem logo) em vez de propagar o erro — a tela inicial nunca trava por causa do branding.

### `fetchBotoes(ramal, senha)` → `GET api_botoes.php?ramal=&senha=`

Busca os botões de discagem/DTMF configurados para o condomínio e a lista de apartamentos:

```json
{
  "ok": true,
  "botoes": [
    { "nome": "Portaria", "tipo": "discar", "destino": "100", "icone": "🔔", "ordem": 1 },
    { "nome": "Portão social", "tipo": "dtmf", "dtmf_digitos": "1#", "ordem": 2 }
  ],
  "apartamentos": ["101", "102", "201"]
}
```

Diferente de `fetchBranding`, **este método propaga erros** (lança `Exception` se `ok != true`, usando `json['error']` como mensagem, ou se a requisição falhar). Quem chama decide como tratar — a `HomeScreen`, por exemplo, cai para listas vazias via `catchError`.

Os botões são convertidos para `AppButton.fromJson` e ordenados por `ordem` (ascendente) antes de retornar.

### `validarCredenciais(ramal, senha)`

**Não existe endpoint de login dedicado.** Este método reaproveita `fetchBotoes()`: se a chamada tiver sucesso, considera as credenciais válidas (`true`); qualquer exceção é tratada como inválida (`false`), sem distinguir a causa. Usado apenas pela `LoginScreen` no momento do primeiro login — sessões restauradas automaticamente (`SessionService.load()`) **não** passam por essa validação.

### `fetchAvisos(ramal, senha)` → `GET api_mural.php?ramal=&senha=`

Busca os avisos ativos do mural do condomínio, mais recentes primeiro:

```json
{
  "ok": true,
  "avisos": [
    {
      "id": 1,
      "titulo": "Manutenção da caixa d'água",
      "mensagem": "Aviso...",
      "imagem_url": "https://.../uploads/aviso_123.png",
      "criado_por": "Síndico Oswaldo",
      "criado_em": "2026-08-14 14:18:53"
    }
  ]
}
```

Mesmo padrão de `fetchBotoes`: **propaga erros** (lança `Exception` se `ok != true` ou a requisição falhar) — quem chama decide como tratar. A `HomeScreen` trata com `catchError` para lista vazia, igual faz com `fetchBotoes`. Avisos são criados/editados **somente pelo painel administrativo** (`mural.php`/`mural_form.php`); o app é somente leitura.

### `enviarAlerta(ramal, senha, tipo)` → `POST api_alerta.php`

Envia um alerta de emergência (`tipo` é um de `elevador_parado`, `emergencia`, `entrada_assistida`, `socorro_medico`). Diferente dos outros métodos, usa **POST** (é uma mutação, não uma leitura) com corpo `x-www-form-urlencoded`. Propaga erros como `fetchBotoes`/`fetchAvisos` — lança `Exception` com a mensagem do servidor se `ok != true` (ex.: `"Socorro médico fora do horário disponível para este condomínio."` quando o tipo é `socorro_medico` e o condomínio configurou uma janela de horário que não inclui o momento atual). A validação da janela é feita **no servidor**; o app só usa `Branding.socorroMedicoDisponivelAgora` para decidir se mostra o botão, nunca para decidir se o envio vai ser aceito.

### `fetchManutencoes(ramal, senha)` → `GET api_manutencoes.php?ramal=&senha=`

Busca as manutenções prediais ativas do condomínio, ordenadas por `proxima_manutencao` (mais próximas primeiro):

```json
{
  "ok": true,
  "manutencoes": [
    {
      "id": 1,
      "equipamento": "Alarme de incêndio",
      "descricao": "Revisão anual do sistema...",
      "ultima_manutencao": "2026-02-10",
      "proxima_manutencao": "2026-10-10"
    }
  ]
}
```

Mesmo padrão de `fetchBotoes`/`fetchAvisos`: propaga erros (`Exception` se `ok != true`). O "faltam X dias" **não vem do servidor** — é calculado no cliente (`Manutencao.diasRestantes`) a partir de `proxima_manutencao`, pra nunca ficar desatualizado entre o momento da consulta e o momento em que a tela é vista.

### `fetchChamados(ramal, senha)` → `GET api_chamados.php?ramal=&senha=`

Busca os chamados **do próprio ramal logado** — filtrado por `condominio_id` **e** `ramal` no servidor, não só por condomínio como o Mural. Cada morador só vê o que ele mesmo enviou:

```json
{
  "ok": true,
  "chamados": [
    {
      "id": 1,
      "apartamento": "101",
      "assunto": "Barulho no período noturno",
      "mensagem": "...",
      "status": "respondido",
      "resposta": "Obrigado pelo aviso...",
      "respondido_em": "2026-08-17 09:25:03",
      "criado_em": "2026-08-17 09:24:51"
    }
  ]
}
```

`status` é um de `aberto`, `em_andamento`, `respondido`, `fechado` — ver `Chamado.statusLabel` para os rótulos em português.

### `enviarChamado(ramal, senha, {apartamento, assunto, mensagem})` → `POST api_chamado_criar.php`

Cria um novo chamado. Mesmo padrão de `enviarAlerta`: POST com corpo `x-www-form-urlencoded`, propaga erros do servidor como `Exception`. `apartamento` é opcional.

### `fetchEncomendas(ramal, senha)` → `GET api_encomendas.php?ramal=&senha=`

Busca as encomendas da(s) unidade(s) associada(s) ao ramal logado. O servidor resolve o apartamento reaproveitando `rotas_horarios` (mesma tabela usada para discagem de apartamento) — **não existe nenhuma coluna "meu apartamento" no app nem numa tabela dedicada**; um ramal sem rota cadastrada recebe `encomendas: []`, não um erro:

```json
{
  "ok": true,
  "encomendas": [
    {
      "id": 1,
      "apartamento": "101",
      "tipo": "pacote",
      "codigo_rastreio": "BR123456789",
      "info_adicional": "Frágil",
      "foto_url": null,
      "status": "nao_retirada",
      "retirado_por": null,
      "retirado_em": null,
      "criado_em": "2026-08-17 10:32:38"
    }
  ]
}
```

### `confirmarRetirada(ramal, senha, id, retiradoPor)` → `POST api_encomenda_retirar.php`

Confirma a retirada de uma encomenda. O servidor valida que a encomenda pertence a uma das unidades associadas ao ramal (mesma resolução via `rotas_horarios`) antes de aceitar — devolve erro 403 caso contrário, mesmo que o `id` seja válido para outra unidade.

### `fetchDocumentos(ramal, senha)` → `GET api_documentos.php?ramal=&senha=`

Busca os documentos ativos do condomínio, mais recentes primeiro:

```json
{
  "ok": true,
  "documentos": [
    {
      "id": 1,
      "titulo": "Regimento Interno 2026",
      "categoria": "regimento",
      "arquivo_url": "https://.../uploads/documento_....pdf",
      "criado_em": "2026-08-17 11:03:47"
    }
  ]
}
```

Mesmo padrão de `fetchAvisos`/`fetchManutencoes`: propaga erros, e o app não faz upload — só lê e abre externamente. **Limite de upload no painel: 2MB** (o `upload_max_filesize` do PHP no servidor está travado nisso globalmente; ver [documento 8](08-limitacoes-e-proximos-passos.md)).

### `fetchHistoricoAcessos(ramal, senha)` → `GET api_historico_acessos.php?ramal=&senha=`

Busca o histórico **de todo o condomínio** (não filtrado por ramal — diferente de `fetchChamados`/`fetchEncomendas`), unindo (`UNION ALL`) duas tabelas de origem — `acessos_portao` (botão de portão pelo app) e `acessos_facial` (webhook do leitor facial Control iD) — mais recentes primeiro, limitado a 200 registros:

```json
{
  "ok": true,
  "acessos": [
    { "tipo": "portao_app", "ramal": "5500", "detalhe": "Portao Social", "criado_em": "2026-08-17 11:37:11" },
    { "tipo": "facial", "ramal": null, "detalhe": "42", "criado_em": "2026-08-17 13:20:00" }
  ]
}
```

`detalhe` significa coisas diferentes por `tipo`: nome do botão DTMF para `portao_app`, `user_id` bruto do Control iD (sem nome resolvido) para `facial`. **Ainda sem catraca/QR Code físico** — só essas duas fontes existem de verdade. Ver `HistoricoAcessosScreen` em [documento 5](05-tela-inicial-e-navegacao.md) e [`docs/roadmap-integracao-facial-controlid.md`](roadmap-integracao-facial-controlid.md) para os detalhes da integração Control iD (webhook `webhook_controlid_dao.php`, tabela `controlid_dispositivos` mapeando `device_id` → `condominio_id`).

### `registrarAcessoPortao(ramal, senha, botaoNome)` → `POST api_acesso_portao.php`

Chamado por `CallScreen._abrirPortao()` toda vez que o morador aciona um botão de portão durante uma chamada. Erro aqui é engolido silenciosamente por quem chama (`.catchError((_) {})`) — o portão já foi acionado via DTMF antes dessa chamada, então uma falha só no registro do histórico não deve incomodar o morador.

### `fetchOrdemRota(ramal, senha)` / `salvarOrdemRota(...)` → `api_rota.php`

Lê e grava a ordem de toque da unidade do morador (`RotaScreen`), na coluna `rotas_horarios.ordem_chamada` — a mesma que o síndico edita em `editar_rota.php`. O banco guarda 5 tokens (`ramal`, `ramd1`, `ramd2`, `cel1`, `cel2`), mas o app expõe só **3 blocos** reordenáveis, e a sub-ordem dentro de cada bloco (ex.: `cel1` antes de `cel2`) é preservada como o síndico configurou:

| Bloco (app) | Rótulo na tela | Tokens |
|---|---|---|
| `ramal_analogico` | Ramal Analógico | `ramal` |
| `ramal_digital` | **App Celular** | `ramd1`, `ramd2` |
| `celular` | Celular | `cel1`, `cel2` |

"App Celular" é o próprio Portcall registrado como ramal SIP no aparelho — o rótulo diferencia de "Celular", que é ligação comum pro número de telefone.

```json
{ "ok": true, "disponivel": true, "ordem": ["ramal_analogico", "celular"] }
```

`disponivel: false` quando o ramal não está vinculado a nenhuma unidade com rota ativa. O POST só aceita uma permutação exata dos blocos que já existem na rota — não dá pra adicionar nem remover perna por aqui — e grava **apenas** `ordem_chamada`, nunca números ou tempos.

### `fetchBloqueios(ramal, senha)` / `salvarBloqueio(...)` → `api_bloqueios.php`

Unidades que o morador não quer receber ligação (`BloqueiosScreen`, acessível pelo ícone 🚫 na tela Unidades). Tabela `bloqueios_unidade` (`condominio_id`, `unidade`, `unidade_bloqueada`).

```json
{
  "ok": true, "disponivel": true, "minha_unidade": "102",
  "unidades": ["101", "5000"], "bloqueadas": ["101"]
}
```

**Quem barra a ligação é o servidor, não o app.** `portcall_router.agi` (Asterisk) checa o bloqueio antes de montar a rota: traduz o ramal de quem ligou para a unidade correspondente (via `rotas_horarios`), e se houver bloqueio responde ocupado (`Busy`) e encerra. Por isso nem o ramal, nem o app, nem os celulares da rota chegam a tocar — um bloqueio feito só no app deixaria o celular cadastrado tocando do mesmo jeito.

Duas salvaguardas, porque um morador isolado da portaria deixa de receber entrega, visita e **aviso de emergência**:

1. Unidades reservadas (`porteiro`, `portaria`, `guarita`, `interfone`, `entrada`, `zeladoria`) nunca entram na lista de bloqueáveis, e o POST as recusa com 403. A comparação é por nome exato de propósito — condomínio horizontal usa "Casa 5", que é unidade legítima e precisa continuar bloqueável.
2. O AGI é **fail-open**: erro de banco, origem que não mapeia pra nenhuma unidade ou origem reservada → a ligação segue normalmente. Deixar passar uma chamada indevida é incomparavelmente menos grave do que barrar uma emergência.

A lista de reservadas existe duplicada (`unidade_reservada()` em `api_bloqueios.php` e no `portcall_router.agi`) — se mudar uma, mudar a outra.

## Modelo `AppButton`

| Campo | Tipo | Descrição |
|---|---|---|
| `nome` | `String` | rótulo exibido |
| `tipo` | `AppButtonType` | `discar` (chamada) ou `dtmf` (tom durante chamada); qualquer valor diferente de `"dtmf"` no JSON vira `discar` |
| `destino` | `String?` | número/ramal a discar, para tipo `discar` |
| `dtmfDigitos` | `String?` | dígitos a enviar, para tipo `dtmf` |
| `icone` | `String?` | emoji/texto exibido no card (fallback `🔘`) |
| `ordem` | `int` | ordem de exibição (parse tolerante: `int.tryParse` com fallback `0`) |

## Modelo `Branding`

| Campo | Tipo | Descrição |
|---|---|---|
| `appNome` | `String` | nome exibido na AppBar; se vier vazio/nulo do painel, usa `"Portcall"` |
| `logoUrl` | `String?` | logo exibido na AppBar (`Image.network`, com `errorBuilder` silencioso se falhar) |
| `sipServidorPadrao` / `sipPortaPadrao` | `String?` | valores default de servidor/porta SIP vindos do painel (hoje não são consumidos automaticamente pela `LoginScreen` — ver [documento 8](08-limitacoes-e-proximos-passos.md)) |
| `socorroMedicoInicio` / `socorroMedicoFim` | `String?` | janela de horário (`HH:mm:ss`) em que o botão de Socorro Médico fica disponível no app; nulos = sempre disponível. Ver getter `socorroMedicoDisponivelAgora` |

## Modelo `Aviso`

| Campo | Tipo | Descrição |
|---|---|---|
| `id` | `int` | identificador do aviso |
| `titulo` | `String` | título exibido no card |
| `mensagem` | `String` | corpo do aviso |
| `imagemUrl` | `String?` | imagem opcional anexada ao aviso |
| `criadoPor` | `String?` | nome de quem publicou (texto livre definido no painel, ex. "Síndico Oswaldo") |
| `criadoEm` | `DateTime?` | data/hora de criação (`DateTime.tryParse` sobre o `criado_em` do JSON) |

## Modelo `Manutencao`

| Campo | Tipo | Descrição |
|---|---|---|
| `id` | `int` | identificador da manutenção |
| `equipamento` | `String` | nome do equipamento (ex.: "Alarme de incêndio") |
| `descricao` | `String?` | detalhes opcionais |
| `ultimaManutencao` | `DateTime?` | data da última manutenção, se informada |
| `proximaManutencao` | `DateTime` | data prevista da próxima manutenção |
| `diasRestantes` (getter) | `int` | dias até `proximaManutencao`, calculado no cliente; negativo = atrasada |

## Modelo `Chamado`

| Campo | Tipo | Descrição |
|---|---|---|
| `id` | `int` | identificador do chamado |
| `apartamento` | `String?` | unidade informada pelo morador (opcional) |
| `assunto` / `mensagem` | `String` | conteúdo do chamado |
| `status` | `String` | `aberto`/`em_andamento`/`respondido`/`fechado` — ver `statusLabel` |
| `resposta` | `String?` | texto da resposta da administração, se houver |
| `respondidoEm` | `DateTime?` | quando a resposta foi salva |
| `criadoEm` | `DateTime?` | quando o chamado foi enviado |

## Modelo `Encomenda`

| Campo | Tipo | Descrição |
|---|---|---|
| `id` | `int` | identificador da encomenda |
| `apartamento` | `String` | unidade destinatária |
| `tipo` | `EncomendaTipo` | `pacote`/`carta`/`envelope`/`remedio`/`outro` — ver `tipoLabel` |
| `codigoRastreio` / `infoAdicional` | `String?` | opcionais |
| `fotoUrl` | `String?` | foto tirada pela portaria no cadastro |
| `retirada` | `bool` | `true` quando `status == 'retirada'` no JSON |
| `retiradoPor` / `retiradoEm` | `String?` / `DateTime?` | preenchidos só após a confirmação de retirada |
| `criadoEm` | `DateTime?` | quando a encomenda foi registrada |

## Modelo `Documento`

| Campo | Tipo | Descrição |
|---|---|---|
| `id` | `int` | identificador do documento |
| `titulo` | `String` | título exibido |
| `categoria` | `DocumentoCategoria` | `balancete`/`regimento`/`ata`/`outro` — ver `categoriaLabel` |
| `arquivoUrl` | `String` | URL pública do arquivo (PDF/JPG/PNG), aberta via `url_launcher` |
| `criadoEm` | `DateTime?` | quando o documento foi publicado |

## Modelo `AcessoPortao`

| Campo | Tipo | Descrição |
|---|---|---|
| `tipo` | `TipoAcesso` | `portaoApp`/`facial`/`qrcode`/`outro` — ver `tipoLabel` |
| `ramal` | `String?` | ramal que acionou o botão ou gerou o passe (`portaoApp`/`qrcode`; nulo em `facial`) |
| `detalhe` | `String?` | nome do botão DTMF (`portaoApp`), `user_id` bruto do Control iD (`facial`) ou nome do visitante (`qrcode`) |
| `nome` | `String?` | só em `facial`: nome resolvido via API do equipamento, quando ele tem credenciais cadastradas (ver [roadmap-integracao-facial-controlid.md](roadmap-integracao-facial-controlid.md)) — se nulo, a tela cai pro `detalhe` (`user_id` bruto) |
| `fotoUrl` | `String?` | só em `facial`: foto do reconhecimento, quando o equipamento tem `enable_photo_upload` habilitado |
| `criadoEm` | `DateTime?` | quando o evento ocorreu |

## Modelo `VisitantePass`

| Campo | Tipo | Descrição |
|---|---|---|
| `id` | `int` | identificador do passe |
| `codigo` | `String` | código aleatório de uso único, conteúdo do QR renderizado |
| `nomeVisitante` | `String` | nome informado pelo morador |
| `observacao` | `String?` | opcional |
| `validadeFim` | `DateTime?` | passe deixa de ser aceito na portaria após esse horário |
| `status` | `StatusPass` | `ativo`/`usado`/`expirado`/`cancelado` — ver `statusLabel` |
| `usadoEm` / `usadoPor` | `DateTime?` / `String?` | preenchidos quando a portaria confirma a entrada em `portaria_qr.php` |
| `criadoEm` | `DateTime?` | quando o passe foi gerado |

## Modelo `ConvidadoLista`

| Campo | Tipo | Descrição |
|---|---|---|
| `id` | `int` | identificador do aviso |
| `nomeConvidado` | `String` | nome informado pelo morador |
| `observacao` | `String?` | opcional |
| `dataInicio` / `dataFim` | `DateTime?` | período esperado |
| `status` | `StatusConvidado` | `aguardando`/`chegou`/`expirado`/`cancelado` — ver `statusLabel` |
| `chegouEm` | `DateTime?` | preenchido quando a portaria marca a chegada em `portaria_convidados.php` |
| `criadoEm` | `DateTime?` | quando o aviso foi cadastrado |

## Modelo `Espaco`

| Campo | Tipo | Descrição |
|---|---|---|
| `id` | `int` | identificador do espaço comum |
| `nome` | `String` | ex.: "Salão de Festas" |
| `taxa` | `double` | valor informativo, sem cobrança real integrada |
| `horarioAbertura` / `horarioFechamento` | `String` | janela do dia em que dá pra reservar (`HH:mm`) |
| `duracaoSlotMinutos` | `int` | tamanho de cada intervalo reservável |
| `antecedenciaCancelamentoHoras` | `int` | quantas horas antes do início ainda dá pra cancelar |

## Modelo `Agendamento`

| Campo | Tipo | Descrição |
|---|---|---|
| `id` | `int` | identificador da reserva |
| `espacoId` / `espacoNome` | `int` / `String` | espaço reservado |
| `data` | `DateTime?` | dia da reserva |
| `horaInicio` / `horaFim` | `String` | horário do slot reservado (`HH:mm`) |
| `convidados` | `String?` | texto livre, nomes separados por vírgula |
| `status` | `StatusAgendamento` | `confirmada`/`cancelada` |
| `podeCancelar` | `bool` (getter) | calculado a partir de `data`/`horaInicio`/`antecedenciaCancelamentoHoras` — validado de novo no servidor ao cancelar |
| `criadoEm` | `DateTime?` | quando a reserva foi feita |

## Resumo dos endpoints usados

| Rota | Método | Uso |
|---|---|---|
| `api_app_config.php` | GET | branding do condomínio (nome, logo, SIP default) |
| `api_botoes.php` | GET | botões de discagem/DTMF + lista de apartamentos; também usado como checagem de credenciais |
| `api_mural.php` | GET | avisos ativos do mural do condomínio |
| `api_alerta.php` | POST | envia um alerta de emergência (valida a janela de horário do Socorro Médico no servidor) |
| `api_manutencoes.php` | GET | manutenções prediais programadas do condomínio |
| `api_chamados.php` | GET | chamados de ouvidoria do próprio ramal (não do condomínio inteiro) |
| `api_chamado_criar.php` | POST | envia um novo chamado de ouvidoria |
| `api_encomendas.php` | GET | encomendas da(s) unidade(s) do ramal (resolvida via `rotas_horarios`) |
| `api_encomenda_retirar.php` | POST | confirma a retirada de uma encomenda |
| `api_documentos.php` | GET | documentos ativos do condomínio |
| `api_historico_acessos.php` | GET | histórico de acessos do condomínio (`UNION` de acionamentos de portão pelo app + eventos de leitor facial Control iD + passes de QR de visitante usados, campo `tipo` distingue a origem — ver [roadmap-integracao-facial-controlid.md](roadmap-integracao-facial-controlid.md) e [roadmap-qrcode-visitante.md](roadmap-qrcode-visitante.md)) |
| `api_acesso_portao.php` | POST | registra um acionamento de botão de portão |
| `api_qr_criar.php` | POST | gera um passe de visitante em QR Code, devolve o `codigo` de uso único |
| `api_qr_listar.php` | GET | lista os passes de visitante gerados pelo próprio ramal |
| `api_qr_cancelar.php` | POST | cancela um passe de visitante `ativo` |
| `api_espacos.php` | GET | lista os espaços comuns ativos do condomínio (Academia, Salão de Festas etc.) |
| `api_agenda_disponibilidade.php` | GET | slots de horário de um espaço num dia, com status ocupado/livre |
| `api_agendamento_criar.php` | POST | cria uma reserva de espaço comum |
| `api_agendamentos_listar.php` | GET | reservas do próprio ramal |
| `api_agendamento_cancelar.php` | POST | cancela uma reserva (valida antecedência mínima) |
| `api_convidado_criar.php` | POST | avisa a portaria de um convidado esperado (nome, período) |
| `api_convidados_listar.php` | GET | convidados avisados pelo próprio ramal |
| `api_convidado_cancelar.php` | POST | cancela um aviso de convidado ainda `aguardando` |
| `api_push_registrar.php` | POST | salva/atualiza o token FCM do dispositivo do ramal, pra receber notificações push |
| `ramal_qrcode.php` | — | não é chamado pelo app; gera o **texto** do QR code que o app lê via câmera (formato documentado em [02-autenticacao-e-sessao.md](02-autenticacao-e-sessao.md)) |
| `webhook_controlid_dao.php` | POST | não é chamado pelo app; recebe o POST que o próprio equipamento Control iD envia (mecanismo "Monitor") a cada identificação facial, grava em `acessos_facial`. Exposto em `/{path-aleatório}/dao` via `RewriteRule` no vhost (ver [roadmap-integracao-facial-controlid.md](roadmap-integracao-facial-controlid.md)) |
| `fcm_helper.php` | — | não é um endpoint, é uma lib incluída por outros arquivos do painel (`mural_save.php`, `encomenda_save.php`, `api_agendamento_criar.php`/`api_agendamento_cancelar.php`, `portaria_convidados.php`) pra disparar notificações push via FCM HTTP v1. Ver [roadmap-central-notificacoes.md](roadmap-central-notificacoes.md) |
