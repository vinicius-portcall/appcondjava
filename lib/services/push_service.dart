import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

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
  StreamSubscription<CallEvent?>? _inscricaoVoIP;

  PushService({required this.api, required this.conta});

  /// Token do PushKit, só existe no iPhone. Guardado porque ele e o token do
  /// Firebase chegam em momentos diferentes e os dois vão na mesma linha da
  /// tabela — sem isso, o que chegar depois apagaria o outro.
  String? _voipToken;
  String? _fcmToken;

  Future<void> iniciar({
    void Function(RemoteMessage mensagem)? aoReceberEmPrimeiroPlano,
  }) async {
    final messaging = FirebaseMessaging.instance;

    // No iPhone o token do PushKit é o que importa de verdade: é por ele que
    // a chamada de interfone acorda o app com a tela apagada. Buscado antes
    // do Firebase porque é o único indispensável — se o morador recusar as
    // notificações comuns, o interfone ainda precisa tocar.
    if (Platform.isIOS) {
      await _carregarTokenVoIP();
    }

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

  /// Pega o token do PushKit e já registra.
  ///
  /// O iOS pode demorar a emitir o token (ele vem de um callback do sistema),
  /// então além de perguntar agora também ficamos ouvindo o evento de
  /// atualização — é comum a primeira consulta voltar nula numa instalação
  /// nova e o token chegar segundos depois.
  Future<void> _carregarTokenVoIP() async {
    try {
      _voipToken = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
      if (_voipToken != null && _voipToken!.isNotEmpty) {
        await _registrarToken(_fcmToken ?? '');
      }
    } catch (_) {
      // Sem token VoIP o app ainda funciona em primeiro plano.
    }

    _inscricaoVoIP = FlutterCallkitIncoming.onEvent.listen((evento) {
      if (evento is CallEventActionDidUpdateDevicePushTokenVoip) {
        unawaited(_atualizarTokenVoIP());
      }
    });
  }

  Future<void> _atualizarTokenVoIP() async {
    try {
      final novo = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
      if (novo != null && novo.isNotEmpty && novo != _voipToken) {
        _voipToken = novo;
        await _registrarToken(_fcmToken ?? '');
      }
    } catch (_) {
      // best-effort
    }
  }

  Future<void> _registrarToken(String token) async {
    if (token.isNotEmpty) _fcmToken = token;
    try {
      await api.registrarPushToken(
        conta.ramal,
        conta.senha,
        _fcmToken ?? '',
        voipToken: _voipToken,
        plataforma: Platform.isIOS ? 'ios' : 'android',
      );
    } catch (_) {
      // best-effort — falha no registro não deve incomodar o usuário
    }
  }

  void dispose() {
    _inscricaoPrimeiroPlano?.cancel();
    _inscricaoVoIP?.cancel();
  }
}
