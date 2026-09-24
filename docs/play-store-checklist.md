# Publicação na Play Store — ficha, textos e justificativas

Material pronto pra colar no Google Play Console, e o que ainda depende de
decisão/ação humana. Mantido no repositório porque a ficha muda junto com o
app: mexeu em permissão, revise a justificativa aqui antes de enviar.

## Situação atual

| Item | Estado |
|---|---|
| Nome do app | **Vídeo Atende** |
| Pacote (`applicationId`) | `br.com.portcall.portcall_app` — **não muda depois de publicado** |
| Versão | `1.0.0+1` (`pubspec.yaml`) |
| Assinatura | keystore de release em `android/keystore/` (fora do git) |
| Política de privacidade | https://clienteauto.portcallvoip.com.br/privacidade.html |
| Conta Play Console | criada, **aguardando verificação do Google** |

> O nome leva acento — **Vídeo Atende** — para bater com o banner e o
> material de marca do cliente.

> **Conta pessoal vs. organização:** conta pessoal criada após nov/2023 só
> publica em produção depois de um teste fechado com **12 testadores por 14
> dias seguidos**. Conta de organização não tem essa exigência, mas pede
> CNPJ + D-U-N-S Number (gratuito, ~1–2 semanas). Para uma operação com
> condomínios reais, organização compensa.

## Textos da ficha

**Nome (30 caracteres):**
```
Vídeo Atende
```

**Descrição curta (80 caracteres):**
```
Atenda o interfone do seu condomínio pelo celular, com áudio e vídeo.
```

**Descrição completa:**
```
O Vídeo Atende transforma seu celular no interfone do condomínio.

Receba a chamada da portaria onde estiver, veja quem está na entrada pela
câmera e libere o acesso — sem depender do aparelho fixo na parede.

PRINCIPAIS RECURSOS

• Chamadas de áudio e vídeo do interfone direto no celular
• Abertura de portões e portas durante a chamada
• Ligação para outras unidades do condomínio
• Ordem de toque configurável: escolha se toca primeiro o app, o celular
  ou o ramal fixo
• Bloqueio de unidades: escolha quem não pode te ligar
• Mural de avisos, encomendas, documentos e reserva de espaços
• Registro de acessos e alertas de emergência
• Cadastro facial para entrada sem chave (opcional)

COMO FUNCIONA

O aplicativo é fornecido pelo seu condomínio. Use o ramal e a senha que a
administração forneceu, ou aponte a câmera para o QR Code de configuração.

Se o seu condomínio ainda não usa o sistema, fale com a administração.

PRIVACIDADE

As chamadas não são gravadas. O cadastro facial é sempre opcional e pode
ser removido a qualquer momento. Consulte a política de privacidade.
```

**Categoria:** Estilo de vida (alternativa: Ferramentas)
**Tags:** interfone, condomínio, portaria, videoporteiro
**E-mail de contato:** ⬜ definir (o mesmo da política de privacidade)

## Recursos gráficos exigidos

Todos prontos em `play-store/` (pasta fora do git, ver `.gitignore`):

| Recurso | Formato exigido | Arquivo |
|---|---|---|
| Ícone | 512×512 PNG, **sem canal alfa** | `icone-loja-512.png` |
| Gráfico de destaque | 1024×500 PNG | `grafico-destaque-1024x500.png` |
| Screenshots telefone | mín. 2, entre 320 e 3840 px | `01-home.png`, `02-unidades.png`, `03-bloqueios.png` |

O gráfico de destaque veio do banner que o cliente já tinha (`banner
MultVirtual Video Atende.png`, no servidor em `/root/APP VIDEO ATENDE/`),
que já estava exatamente em 1024×500. Ícone e banner foram reconvertidos
para 24 bits sem alfa — a loja recusa ícone com transparência.

## Justificativas de permissão (onde a maioria é reprovada)

O app usa permissões que o Google audita manualmente. Cada uma tem um
formulário próprio no Console; as respostas abaixo descrevem o uso real.

### `USE_FULL_SCREEN_INTENT`
> O aplicativo é um interfone de condomínio. Quando a portaria ou outra
> unidade liga para o morador, a chamada precisa aparecer em tela cheia com
> o aparelho bloqueado, como em qualquer aplicativo de telefonia — caso
> contrário o morador não vê a chamada a tempo de atender o visitante ou
> uma emergência. A intenção de tela cheia é disparada exclusivamente por
> uma chamada recebida em tempo real.

### `FOREGROUND_SERVICE_PHONE_CALL`
> Mantém a conexão SIP com a central telefônica do condomínio ativa para
> receber chamadas quando o aplicativo está em segundo plano. O serviço é
> do tipo `phoneCall` porque existe exclusivamente para tratar chamadas de
> voz e vídeo, e exibe notificação persistente enquanto ativo.

### `RECEIVE_BOOT_COMPLETED`
> Depois de reiniciar o aparelho, o aplicativo precisa restabelecer a
> conexão com a central automaticamente. Sem isso o morador deixaria de
> receber o interfone até abrir o aplicativo manualmente — o que ele não
> tem como saber que precisa fazer.

### `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`
> O aplicativo recebe chamadas em tempo real. As otimizações agressivas de
> bateria encerram a conexão e fazem o morador perder chamadas do
> interfone, inclusive emergências. O aplicativo apenas **solicita** a
> isenção, explicando o motivo; recusar não impede o uso.

### `RECORD_AUDIO` e `CAMERA`
> Áudio e vídeo bidirecionais durante a chamada do interfone, mais leitura
> de QR Code de configuração e cadastro facial opcional. Nada é gravado.

## Declaração de dados (Data safety)

| Pergunta | Resposta |
|---|---|
| Coleta dados? | Sim |
| Dados são criptografados em trânsito? | Sim (HTTPS/WSS) |
| Usuário pode pedir exclusão? | Sim (pela administração/contato) |
| Compartilha com terceiros? | Não vende; usa Firebase só para entregar notificação |

Tipos declarados: **Informações pessoais** (identificador da unidade),
**Áudio/Vídeo** (chamadas, não gravadas), **Fotos** (cadastro facial —
declarar como *dado biométrico*, opcional), **IDs do dispositivo** (token
de notificação).

> Atenção: o cadastro facial é biometria, dado sensível pela LGPD. Declare
> como opcional e garanta que a remoção funcione — o app já tem a tela de
> remoção em `moradores_facial_screen.dart`.

## Passo a passo

1. ✅ Criar conta no Play Console — aguardando verificação do Google
2. ⬜ Trocar o e-mail de contato na política de privacidade (hoje está o
   placeholder `CONTATO@EXEMPLO.COM.BR`, de propósito bem visível)
3. ✅ Gerar o `.aab` assinado (`flutter build appbundle --release`)
4. ✅ Capturar screenshots
5. ✅ Ícone 512 e gráfico de destaque
6. ⬜ Criar o app no Console e preencher ficha + Data safety + classificação
7. ⬜ Responder os formulários de permissão acima
8. ⬜ Subir o `.aab` em **teste interno** primeiro (instala pela loja de
   verdade, sem exposição pública) e só depois promover
9. ⬜ Enviar para revisão

> **Sempre suba primeiro em teste interno.** É a única forma de verificar
> que o app assinado pela Play Store (o Google reassina) funciona no
> aparelho antes de qualquer usuário real ver.
