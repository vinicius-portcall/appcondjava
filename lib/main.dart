
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'dart:async';

import 'models/branding.dart';
import 'services/foreground_service.dart';
import 'services/session_service.dart';
import 'services/sip_service.dart';
import 'services/theme_service.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';

/// Roda num isolate separado, sem acesso ao estado do app (SipService etc)
/// — chega mesmo com o app fechado pelo Android. Não dá pra reconectar o SIP
/// daqui diretamente; o mais que dá pra fazer é reacender o serviço de
/// primeiro plano, que é quem mantém o app (e o registro SIP) vivo. Ver
/// docs/roadmap-central-notificacoes.md e home_screen.dart (_mostrarNotificacaoPrimeiroPlano).
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage mensagem) async {
  if (mensagem.data['tipo'] != 'chamada') return;
  try {
    await Firebase.initializeApp();
    final conta = await SessionService().load();
    if (conta != null) {
      await ForegroundService.start(ramal: conta.ramal);
    }
  } catch (_) {
    // Best-effort — se falhar aqui não tem mais nada a fazer neste isolate.
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('[Portcall] main: início');
  MediaKit.ensureInitialized();
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (e) {
    // Sem Firebase o app continua funcionando, só sem notificações push.
    debugPrint('[Portcall] main: Firebase falhou: $e');
  }

  // O SipService nasce aqui, FORA da árvore de widgets, e o registro é
  // disparado antes do runApp() de propósito.
  //
  // Quando o engine sobe sozinho depois de reiniciar o celular
  // (RestartReceiver → PersistentEngineService), não existe Activity nem
  // superfície de desenho — e sem superfície o Flutter não agenda frames.
  // runApp() ainda força um "warm-up frame" (por isso a splash chega a
  // montar), mas nenhum frame novo é agendado depois dele: o
  // Navigator.pushReplacement da splash pra HomeScreen fica pendente pra
  // sempre, initState() nunca roda e, com o SipService criado lá dentro, o
  // ramal ficava sem registrar até alguém abrir o app na mão. Confirmado em
  // teste com log: no boot limpo os logs paravam exatamente em "navegando
  // pra HomeScreen", e nenhum REGISTER chegava no Asterisk.
  final sip = SipService();
  final conta = await SessionService().load();
  debugPrint('[Portcall] main: sessão ${conta == null ? "AUSENTE" : conta.ramal}');
  if (conta != null) {
    unawaited(_registrarRamal(sip, conta));
  }

  debugPrint('[Portcall] main: runApp');
  runApp(PortcallApp(sip: sip));
}

/// Registro SIP + serviço de segundo plano, sem depender de nenhuma tela
/// ter sido construída. Best-effort: falhar aqui não pode impedir o app de
/// abrir normalmente (a HomeScreen tenta de novo quando montar).
Future<void> _registrarRamal(SipService sip, SipAccount conta) async {
  try {
    debugPrint('[Portcall] main: conectando SIP');
    await sip.conectar(conta);
  } catch (e) {
    debugPrint('[Portcall] main: conectar() falhou: $e');
  }
  try {
    await ForegroundService.start(ramal: conta.ramal);
  } catch (e) {
    debugPrint('[Portcall] main: ForegroundService.start falhou: $e');
  }
}

class PortcallApp extends StatefulWidget {
  final SipService sip;

  const PortcallApp({super.key, required this.sip});

  @override
  State<PortcallApp> createState() => _PortcallAppState();
}

class _PortcallAppState extends State<PortcallApp> {
  final _themeService = ThemeService();

  @override
  void initState() {
    super.initState();
    _themeService.addListener(_onThemeChange);
    _themeService.carregar();
  }

  void _onThemeChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _themeService.removeListener(_onThemeChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Portcall',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _themeService.mode,
      home: _SplashRouter(themeService: _themeService, sip: widget.sip),
    );
  }
}

class _SplashRouter extends StatefulWidget {
  final ThemeService themeService;
  final SipService sip;

  const _SplashRouter({required this.themeService, required this.sip});

  @override
  State<_SplashRouter> createState() => _SplashRouterState();
}

class _SplashRouterState extends State<_SplashRouter> {
  Branding? _branding;
  bool _brandingCarregado = false;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    debugPrint('[Portcall] SplashRouter: carregando branding do cache');
    // Carrega o branding em cache ANTES de montar a SplashScreen — se
    // rodasse em paralelo com o delay abaixo, um cache mais lento que 1300ms
    // (aparelho fraco, engine "frio") faria a splash navegar mostrando
    // "Portcall" mesmo já existindo um branding salvo certo.
    final branding = await SessionService().loadBranding();
    if (!mounted) return;
    setState(() {
      _branding = branding;
      _brandingCarregado = true;
    });
    _decidir();
  }

  Future<void> _decidir() async {
    final conta = await SessionService().load();
    debugPrint('[Portcall] SplashRouter: sessão ${conta == null ? "AUSENTE" : "encontrada (${conta.ramal})"}');
    // Tempo mínimo pra animação da SplashScreen (logo + anéis de pulso,
    // ~1300ms) terminar de rodar em vez de ser cortada.
    await Future.delayed(const Duration(milliseconds: 1300));
    if (!mounted) return;
    debugPrint('[Portcall] SplashRouter: navegando pra ${conta != null ? "HomeScreen" : "LoginScreen"}');

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => conta != null
            ? HomeScreen(
                conta: conta,
                themeService: widget.themeService,
                sip: widget.sip,
              )
            : LoginScreen(themeService: widget.themeService, sip: widget.sip),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_brandingCarregado) return const Scaffold();
    return SplashScreen(branding: _branding);
  }
}
