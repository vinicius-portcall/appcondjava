import 'package:flutter/material.dart';

import '../models/branding.dart';
import '../services/session_service.dart';
import '../services/api_service.dart';
import '../services/sip_service.dart';
import '../services/theme_service.dart';
import 'qr_scan_screen.dart';
import 'home_screen.dart';

/// Único painel que este app atende — o morador só precisa saber ramal e
/// senha (o "usuário"); servidor/porta SIP são resolvidos automaticamente
/// por condomínio via `api_app_config.php`.
const _painelUrlPadrao = 'https://clienteauto.portcallvoip.com.br';

class LoginScreen extends StatefulWidget {
  final ThemeService themeService;

  /// Mesmo SipService do main() — só repassado adiante pra HomeScreen, que
  /// é quem conecta depois do login.
  final SipService sip;

  const LoginScreen({
    super.key,
    required this.themeService,
    required this.sip,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usuarioCtrl = TextEditingController();
  final _senhaCtrl = TextEditingController();

  bool _carregando = false;
  String? _erro;

  Future<void> _escanearQr() async {
    final resultado = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const QrScanScreen()));
    if (resultado == null) return;

    final campos = SessionService.parseQrText(resultado);
    final ramal = campos['RAMAL'];
    final senha = campos['SENHA'];
    if (ramal == null || senha == null) {
      if (!mounted) return;
      setState(() => _erro = 'QR code não reconhecido.');
      return;
    }

    setState(() {
      _usuarioCtrl.text = ramal;
      _senhaCtrl.text = senha;
    });
    await _entrar();
  }

  Future<void> _entrar() async {
    final usuario = _usuarioCtrl.text.trim();
    final senha = _senhaCtrl.text.trim();

    if (usuario.isEmpty || senha.isEmpty) {
      setState(() => _erro = 'Preencha usuário e senha.');
      return;
    }

    setState(() {
      _carregando = true;
      _erro = null;
    });

    final api = ApiService(_painelUrlPadrao);
    Branding branding;
    try {
      branding = await api.fetchBranding(usuario, senha);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erro = 'Usuário ou senha inválidos, ou painel inacessível.';
      });
      return;
    }

    if (branding.sipServidorPadrao == null ||
        branding.sipServidorPadrao!.isEmpty) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erro = 'Não foi possível obter a configuração SIP do condomínio.';
      });
      return;
    }

    final conta = SipAccount(
      painelUrl: _painelUrlPadrao,
      servidor: branding.sipServidorPadrao!,
      porta: branding.sipPortaPadrao?.isNotEmpty == true
          ? branding.sipPortaPadrao!
          : '5060',
      ramal: usuario,
      senha: senha,
      displayName: usuario,
    );
    await SessionService().save(conta);

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => HomeScreen(
          conta: conta,
          themeService: widget.themeService,
          sip: widget.sip,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Entrar')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                onPressed: _carregando ? null : _escanearQr,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Escanear QR do ramal'),
              ),
              const SizedBox(height: 20),
              Text(
                'Ou entre com usuário e senha:',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _usuarioCtrl,
                decoration: const InputDecoration(labelText: 'Usuário'),
                keyboardType: TextInputType.number,
                enabled: !_carregando,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _senhaCtrl,
                decoration: const InputDecoration(labelText: 'Senha'),
                obscureText: true,
                enabled: !_carregando,
                onSubmitted: (_) => _carregando ? null : _entrar(),
              ),
              const SizedBox(height: 20),
              if (_erro != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _erro!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              FilledButton(
                onPressed: _carregando ? null : _entrar,
                child: _carregando
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Entrar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
