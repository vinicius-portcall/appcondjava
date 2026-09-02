import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';

import 'api_service.dart';
import 'session_service.dart';

/// Notificações push via Firebase Cloud Messaging — pede permissão, registra
/// o token do dispositivo no backend (`api_push_registrar.php`) e escuta
/// mensagens recebidas com o app em primeiro plano (o FCM não mostra a
/// notificação sozinho nesse caso; em segundo plano/fechado o sistema
/// operacional já cuida disso). Ver docs/roadmap-central-notificacoes.md.
class PushService {
  final ApiService api;
  final SipAccount conta;

  StreamSubscription<RemoteMessage>? _inscricaoPrimeiroPlano;

  PushService({required this.api, required this.conta});

  Future<void> iniciar({
    void Function(RemoteMessage mensagem)? aoReceberEmPrimeiroPlano,
  }) async {
    final messaging = FirebaseMessaging.instance;

    try {
      await messaging.requestPermission();

      final token = await messaging.getToken();
      if (token != null) {
        await _registrarToken(token);
      }
      messaging.onTokenRefresh.listen(_registrarToken);
    } catch (_) {
      // Sem push o app continua funcionando normalmente — não deve travar o login.
    }

    if (aoReceberEmPrimeiroPlano != null) {
      _inscricaoPrimeiroPlano = FirebaseMessaging.onMessage.listen(
        aoReceberEmPrimeiroPlano,
      );
    }
  }

  Future<void> _registrarToken(String token) async {
    try {
      await api.registrarPushToken(conta.ramal, conta.senha, token);
    } catch (_) {
      // best-effort — falha no registro não deve incomodar o usuário
    }
  }

  void dispose() {
    _inscricaoPrimeiroPlano?.cancel();
  }
}
