import 'package:shared_preferences/shared_preferences.dart';

class SipAccount {
  final String painelUrl;
  final String servidor;
  final String porta;
  final String ramal;
  final String senha;
  final String displayName;

  const SipAccount({
    required this.painelUrl,
    required this.servidor,
    required this.porta,
    required this.ramal,
    required this.senha,
    this.displayName = '',
  });
}

class SessionService {
  static const _kPainel = 'painel_url';
  static const _kServidor = 'sip_servidor';
  static const _kPorta = 'sip_porta';
  static const _kRamal = 'sip_ramal';
  static const _kSenha = 'sip_senha';
  static const _kNome = 'display_name';

  Future<void> save(SipAccount account) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPainel, account.painelUrl);
    await prefs.setString(_kServidor, account.servidor);
    await prefs.setString(_kPorta, account.porta);
    await prefs.setString(_kRamal, account.ramal);
    await prefs.setString(_kSenha, account.senha);
    await prefs.setString(_kNome, account.displayName);
  }

  Future<SipAccount?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final painel = prefs.getString(_kPainel);
    final servidor = prefs.getString(_kServidor);
    final ramal = prefs.getString(_kRamal);
    final senha = prefs.getString(_kSenha);

    if (painel == null || servidor == null || ramal == null || senha == null) {
      return null;
    }

    return SipAccount(
      painelUrl: painel,
      servidor: servidor,
      porta: prefs.getString(_kPorta) ?? '5060',
      ramal: ramal,
      senha: senha,
      displayName: prefs.getString(_kNome) ?? '',
    );
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPainel);
    await prefs.remove(_kServidor);
    await prefs.remove(_kPorta);
    await prefs.remove(_kRamal);
    await prefs.remove(_kSenha);
    await prefs.remove(_kNome);
  }

  /// Extrai os campos do texto do QR gerado por ramal_qrcode.php
  /// Formato: "PAINEL: ...\nSERVIDOR: ...\nPORTA: ...\nRAMAL: ...\nSENHA: ..."
  static Map<String, String> parseQrText(String texto) {
    final result = <String, String>{};
    for (final linha in texto.split('\n')) {
      final idx = linha.indexOf(':');
      if (idx <= 0) continue;
      final chave = linha.substring(0, idx).trim().toUpperCase();
      final valor = linha.substring(idx + 1).trim();
      result[chave] = valor;
    }
    return result;
  }
}
