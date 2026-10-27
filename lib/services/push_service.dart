import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import '../versao_app.dart';
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
    unawaited(_diag('push_iniciar', detalhe: 'app $versaoApp'));

    // No iPhone o token do PushKit é o que importa de verdade: é por ele que
    // a chamada de interfone acorda o app com a tela apagada. Buscado antes
    // do Firebase porque é o único indispensável — se o morador recusar as
    // notificações comuns, o interfone ainda precisa tocar.
    if (Platform.isIOS) {
      await _carregarTokenVoIP();
    }

    // TODO o bloco do Firebase vive dentro deste try, inclusive o
    // `FirebaseMessaging.instance`.
    //
    // Essa linha era a PRIMEIRA do método, fora de qualquer proteção. No
    // iPhone o projeto não tem GoogleService-Info.plist, então
    // `Firebase.initializeApp()` falha lá no main.dart (que trata e segue),
    // e qualquer acesso a `FirebaseMessaging.instance` depois disso lança.
    // Como era a primeira instrução, o método inteiro morria antes de tudo:
    // antes do diagnóstico, antes de ler o token do PushKit, antes de
    // registrar qualquer coisa. Nenhuma linha chegava ao painel, em nenhum
    // build — e o sintoma aparecia como "o interfone não toca com a tela
    // apagada", num recurso que sequer usa Firebase.
    //
    // FCM e PushKit são sistemas independentes: um serve para avisos
    // comuns (mural, encomenda), o outro para a chamada. O caminho da
    // chamada não pode depender do outro estar configurado.
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();

      final token = await messaging.getToken();
      unawaited(
        _diag(
          'fcm_token',
          detalhe: token == null ? 'nulo' : '${token.length} caracteres',
        ),
      );
      if (token != null) {
        await _registrarToken(token);
      }
      messaging.onTokenRefresh.listen(_registrarToken);
    } catch (e) {
      unawaited(_diag('fcm_erro', detalhe: e.toString()));
      // Sem push o app continua funcionando normalmente — não deve travar o
      // login. Mas o erro É registrado: engolir calado aqui foi o que deixou
      // o iPhone invisível. Quando o Firebase falha no iOS (acontece se o
      // APNs ainda não entregou o token ao SDK) e o PushKit também não tinha
      // devolvido nada, NENHUM registro era enviado — e o ramal não aparecia
      // na tabela dispositivos_push, sem qualquer pista do motivo.
      debugPrint('[Portcall] Firebase push falhou: $e');
    }

    // Registra a presença de qualquer forma, mesmo sem token nenhum. Sem
    // isto não há como distinguir, do lado do painel, um app que nunca rodou
    // de um app que rodou e não conseguiu token do sistema — e no iPhone,
    // onde os tokens chegam por callback e podem não chegar, essa diferença
    // é tudo o que se tem para diagnosticar. O painel aceita o registro sem
    // token quando a plataforma é iOS (ver api_push_registrar.php).
    //
    // Sem condição nenhuma de propósito. A versão anterior checava
    // `_voipToken == null`, que nunca é verdade: o lado nativo devolve
    // string VAZIA quando não há token (`?? ""` em getDevicePushTokenVoIP),
    // não nulo. O registro de diagnóstico simplesmente nunca rodava, e o
    // ramal continuou invisível — escondendo justamente o que ele existia
    // para revelar. Registrar sempre também não custa nada: quando já há
    // token, manda o token; o painel usa COALESCE e não apaga o que tem.
    if (Platform.isIOS) {
      await _registrarToken('');
    }

    // Também protegido: `FirebaseMessaging.onMessage` lança pelo mesmo
    // motivo quando o Firebase não subiu, e isto roda DEPOIS do registro do
    // token — deixar desprotegido aqui não derrubaria o push, mas jogaria
    // uma exceção não tratada no meio da inicialização da tela.
    if (aoReceberEmPrimeiroPlano != null) {
      try {
        _inscricaoPrimeiroPlano = FirebaseMessaging.onMessage.listen(
          aoReceberEmPrimeiroPlano,
        );
      } catch (e) {
        debugPrint('[Portcall] onMessage indisponível: $e');
      }
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
      unawaited(
        _diag(
          'voip_token_1a_leitura',
          detalhe: (_voipToken == null || _voipToken!.isEmpty)
              ? 'vazio'
              : '${_voipToken!.length} caracteres',
        ),
      );
      if (_voipToken != null && _voipToken!.isNotEmpty) {
        await _registrarToken(_fcmToken ?? '');
      }
    } catch (e) {
      // Sem token VoIP o app ainda funciona em primeiro plano.
      unawaited(_diag('voip_token_erro', detalhe: e.toString()));
    }

    _inscricaoVoIP = FlutterCallkitIncoming.onEvent.listen((evento) {
      if (evento is CallEventActionDidUpdateDevicePushTokenVoip) {
        unawaited(_atualizarTokenVoIP());
      }
    });

    // O evento acima cobre o caso de o token chegar DEPOIS deste listener
    // existir. Mas ele pode chegar antes — o PKPushRegistry é registrado no
    // didFinishLaunching, e o Flutter leva um tempo até montar a tela que
    // cria o PushService. Nessa janela o evento é emitido sem ninguém
    // escutando, e a leitura única lá em cima já tinha voltado vazia: o
    // token existia no aparelho e nunca era mandado ao painel.
    //
    // Reler algumas vezes resolve: o valor fica guardado no UserDefaults do
    // lado nativo, então basta perguntar de novo. Cinco tentativas em ~15s
    // cobrem a emissão do token, que depende de rede.
    if (_voipToken == null || _voipToken!.isEmpty) {
      unawaited(_insistirPeloTokenVoIP());
    }
  }

  Future<void> _insistirPeloTokenVoIP() async {
    for (var tentativa = 1; tentativa <= 5; tentativa++) {
      await Future<void>.delayed(const Duration(seconds: 3));
      if (_voipToken != null && _voipToken!.isNotEmpty) {
        unawaited(_diag('voip_token_chegou', detalhe: 'tentativa $tentativa'));
        return;
      }
      await _atualizarTokenVoIP();
    }
    debugPrint('[Portcall] iOS não devolveu token VoIP após 5 tentativas');
    unawaited(_diag('voip_token_desistiu', detalhe: '5 tentativas em 15s'));
  }

  /// Linha no diário de bordo do painel. Sempre `unawaited` nos chamadores:
  /// diagnóstico não pode atrasar nem derrubar o que está diagnosticando.
  Future<void> _diag(String evento, {String detalhe = ''}) =>
      api.registrarDiagnostico(
        conta.ramal,
        conta.senha,
        evento,
        detalhe: detalhe,
      );

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
