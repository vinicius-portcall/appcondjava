import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'services/foreground_service.dart';
import 'services/session_service.dart';
import 'services/theme_service.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
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
  MediaKit.ensureInitialized();
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (_) {
    // Sem Firebase o app continua funcionando, só sem notificações push.
  }
  runApp(const PortcallApp());
}

class PortcallApp extends StatefulWidget {
  const PortcallApp({super.key});

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
      home: _SplashRouter(themeService: _themeService),
    );
  }
}

class _SplashRouter extends StatefulWidget {
  final ThemeService themeService;

  const _SplashRouter({required this.themeService});

  @override
  State<_SplashRouter> createState() => _SplashRouterState();
}

class _SplashRouterState extends State<_SplashRouter> {
  @override
  void initState() {
    super.initState();
    _decidir();
  }

  Future<void> _decidir() async {
    final conta = await SessionService().load();
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => conta != null
            ? HomeScreen(conta: conta, themeService: widget.themeService)
            : LoginScreen(themeService: widget.themeService),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
