# 1. Visão geral e arquitetura

## O que é o Portcall

O Portcall é um app Flutter que transforma o celular do morador em um **ramal SIP** de um interfone de condomínio. Ele se conecta a um painel PBX baseado em Asterisk, permitindo:

- Registrar o celular como ramal SIP e manter esse registro ativo mesmo em segundo plano.
- Receber chamadas do interfone (portaria, portão, outras unidades) com áudio ou vídeo, inclusive com tela bloqueada, via integração nativa de chamada (CallKit).
- Fazer chamadas para unidades do condomínio ou para qualquer número/ramal.
- Enviar tons DTMF durante a chamada, usados para abrir portões/portas.
- Personalizar nome e logo do app (branding) conforme o condomínio, vindos do painel.

O domínio e a interface são em português: *ramal* (extensão SIP), *painel* (backend/PBX), *apartamentos* (unidades), *portão* (ação DTMF de abertura).

## Como o app está organizado

```
lib/
├── main.dart              # bootstrap do app, tema, roteamento inicial
├── models/                 # dados vindos do painel (JSON) e da UI
│   ├── app_button.dart     # botão de discagem/DTMF configurado pelo condomínio
│   └── branding.dart       # nome do app, logo, config SIP padrão
├── services/                # toda a lógica de negócio, sem dependência de widgets
│   ├── session_service.dart    # persistência da conta SIP + parser do QR code
│   ├── api_service.dart        # cliente HTTP do painel
│   ├── sip_service.dart        # registro SIP, chamadas, WebRTC, CallKit
│   └── foreground_service.dart # notificação persistente em segundo plano
└── screens/                 # uma tela por arquivo, recebe serviços via construtor
    ├── login_screen.dart
    ├── qr_scan_screen.dart
    ├── home_screen.dart
    ├── call_screen.dart
    ├── apartamentos_screen.dart
    ├── dialpad_screen.dart
    └── cameras_screen.dart
```

Não há gerenciador de estado externo (Provider, Riverpod, Bloc): os serviços que precisam notificar mudança de estado (`SipService`) estendem `ChangeNotifier`, e as telas assinam esse `ChangeNotifier` diretamente com `addListener`/`removeListener`.

## Fluxo geral de navegação

```
main.dart
   │
   ▼
_SplashRouter  ──► SessionService.load()
   │                       │
   │              conta salva?
   │            ┌──────────┴───────────┐
   │           não                     sim
   ▼                                    ▼
LoginScreen                       HomeScreen
   │  (login manual ou QR)              │
   └──────────► HomeScreen ◄────────────┘
                     │
       ┌─────────────┼─────────────────┬───────────────┐
       ▼             ▼                 ▼                ▼
 DialpadScreen  ApartamentosScreen  CamerasScreen   CallScreen
                                                    (aberta automaticamente
                                                     quando há chamada ativa)
```

- `_SplashRouter` (em `main.dart`) decide, na abertura do app, se existe uma sessão salva (`SessionService`) e direciona para `LoginScreen` ou `HomeScreen`.
- `HomeScreen` é o hub: a partir dela o usuário chega ao discador, à lista de apartamentos e (futuramente) às câmeras.
- `CallScreen` não é acessada por um botão de menu — ela é empurrada automaticamente pela `HomeScreen` sempre que o `SipService` indica que existe uma chamada ativa (recebida ou realizada).

## Tema visual

Definido em `main.dart`: `ColorScheme` a partir de uma cor semente azul (`#1565C0`), com um amarelo (`#FFB300`) como cor secundária/de destaque (usado em `FloatingActionButton`, ícones da AppBar e indicadores de progresso).
