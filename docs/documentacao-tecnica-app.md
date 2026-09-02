# Documentação Técnica de Funcionalidades: Aplicação INOVASEG

## 1. Visão Geral da Arquitetura de Módulos

O aplicativo organiza as suas funcionalidades num painel principal de navegação (*Dashboard*) dividido nos seguintes módulos funcionais:

1. **Gestão de Cadastros**
2. **Histórico de Acessos**
3. **Gestão de Convidados & Visitantes**
4. **Agendamento de Áreas Comuns**
5. **Mural de Avisos & Comunicação**
6. **Pedidos e Manifestações (Ocorrências/Ouvidoria)**
7. **Acionamentos Remotos e Câmeras**
8. **Controlo de Entregas e Encomendas**
9. **Manutenções Prediais**
10. **Gestão Financeira (Boletos)**
11. **Documentos do Condomínio**
12. **Módulo de Emergência / Monitoramento Ativo**

---

## 2. Detalhamento Técnico dos Módulos

### 2.1 Cadastros

Permite a consulta, adição, edição, convite e remoção de registos associados à unidade do morador.

* **Submódulos / Entidades:**
  * **Moradores:** Gestão dos residentes, indicação de responsável e estado da conta da aplicação (*com conta criada / não possui conta criada*).
  * **Visitantes e Familiares:** Registo e autorização de acessos recorrentes ou frequentes.
  * **Prestadores e Funcionários:** Registo com especificação de função (ex: *Eletricista*), definição de regras de liberação por data/horário e geração de QR Code Scanner para validação na portaria.
  * **Veículos:** Cadastro de veículos (Marca, Modelo, Cor, Placa e Foto do Veículo) vinculados à unidade.
  * **Bilhetes para o Porteiro:** Avisos com validade temporal (*Data/Hora Inicial e Data/Hora Final*) direcionados à portaria/administração (ex: *"Estou viajando, não autorizar ninguém a entrar"*).
  * **Documentos:** Anexo e consulta de documentos pessoais ou relativos à unidade.

### 2.2 Histórico de Acessos

Módulo de auditoria e monitorização em tempo real das entradas e saídas no condomínio.

* **Dados Exibidos no Registo:**
  * Nome do utente/visitante/prestador.
  * Fotografia/Avatar de perfil.
  * Tipo de Perfil (*Morador, Prestador de Serviço, Visitante*).
  * Data e Hora exata do evento.
  * Sentido (*Entrada / Saída*).
  * Ponto de Acesso e Unidade Vinculada (ex: *Bloco A - Apartamento 102*).
  * Tipo de Ocorrência (*Acesso manual, Facial, QR Code, etc.*).

### 2.3 Gestão de Convidados

Módulo focado na emissão de autorizações pontuais de acesso para terceiros.

* **Métodos de Convite:**
  1. **Avisar Portaria:** Criação de lista de convidados especificando Unidade, Período (*Data/Hora Início e Fim*) e Acompanhantes.
  2. **Convidar por QR Scanner (QR Code Pass):**
     * Geração de link ou código QR temporário.
     * Gestão do estado do código (*Ativo, Expirado*).
     * Funcionalidade de **Renovar** código expirado ou **Cancelar Convite**.

### 2.4 Agendamentos (Reserva de Espaços Comuns)

Sistema de reserva e agendamento de áreas de lazer do condomínio.

* **Locais Selecionáveis:** Academia, Churrasqueira, Quadra, Salão de Festas, entre outros.
* **Funcionalidades:**
  * Consulta de disponibilidade de horários em grade diária (*Disponível / Horário indisponível*).
  * Visualização dos detalhes do agendamento (Valor da taxa, horário limite para cancelamento e situação da reserva).
  * Associação de lista de convidados específica para o evento agendado.

### 2.5 Mural de Avisos

Central de comunicação unidirecional ou informativa emitida pela administração/síndico para os condóminos.

* **Estrutura do Aviso:** Título, Mensagem de texto, Imagens anexas (ex: foto das caixas d'água em manutenção), Destinatários (*Ex: Todos*) e Identificação do Criador (*Ex: Síndico Oswaldo*) com data/hora da publicação.

### 2.6 Pedidos e Manifestações (Chamados)

Módulo para envio de solicitações, dúvidas ou reclamações à administração do condomínio.

* **Campos do Chamado:** Seleção de Unidade, Assunto, Mensagem detalhada e botão para **Anexar arquivos/fotos**.

### 2.7 Acionamentos Remotos e Câmeras

Módulo de automação residencial/condominial para abertura remota e visualização de dispositivos IoT.

* **Dispositivos Controláveis:**
  * Portão Social, Porta Eclusa, Leitor Facial, Portão de Garagem.
  * Equipamentos de Lazer/Utilitários: Iluminação, Exaustor da Churrasqueira, Porta da Academia/Piscina.
* **Integração de Vídeo:**
  * Visualização de stream/vídeo em tempo real associado ao ponto de acesso (ex: câmara do *Portão Social* ou *Grelha de Câmeras* cobrindo Hall, Garagens e Ruas).
  * Botão de confirmação (*Acionar Portão Social*) diretamente integrado com o feed da câmara.

### 2.8 Gestão de Entregas (Encomendas)

Sistema de rastreio interno de encomendas recebidas na portaria para os moradores.

* **Atributos Registados:**
  * Tipo de Objeto (*Pacote, Carta, Envelope, Remédio, etc.*).
  * Estado (*Não retirada / Retirada por [Nome] em [Data/Hora]*).
  * Código de rastreio interno, informação adicional (*ex: Frágil*) e **Foto do recebimento** tirada pela portaria.
  * Ação do Morador: Confirmação ou agendamento de retirada.

### 2.9 Manutenções Prediais

Exibição do calendário e estado de manutenções programadas dos equipamentos do condomínio (ex: *Alarme de incêndio - Restam 2 meses até a manutenção*).

### 2.10 Boletos e Cobranças

Área financeira para listagem e consulta de boletos de taxa condominial ou taxas extras.

* **Informações:** Data de vencimento, valor e estado de visualização (*Não visualizado / Baixado*).

### 2.11 Documentos

Repositório central para consulta de ficheiros e regulamentos do condomínio.

* **Documentos Típicos:** Balancete Mensal, Regimento Interno, Atas de Assembleia.

### 2.12 Atendimento de Emergência / Monitoramento

Acesso rápido para disparo de alertas com confirmação de segurança enviados à central de monitoramento.

* **Tipos de Eventos de Alerta:**
  * *Elevador Parado*
  * *Emergência*
  * *Entrada Assistida*
  * *Socorro Médico* (disponível por janela de horário configurável).

### 2.13 Central de Notificações

Notificações *Push* em tempo real listando histórico de avisos recebidos, confirmações de agendamento, alertas de chegada de encomendas e registo de acesso de prestadores/visitantes.
