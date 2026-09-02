import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../logger.dart';
import '../sip_ua_helper.dart';

typedef OnMessageCallback = void Function(dynamic msg);
typedef OnCloseCallback = void Function(int? code, String? reason);
typedef OnOpenCallback = void Function();

class SIPUATcpSocketImpl {
  SIPUATcpSocketImpl(this.messageDelay, this._host, this._port);

  final String _host;
  final String _port;

  Socket? _socket;
  OnOpenCallback? onOpen;
  OnMessageCallback? onData;
  OnCloseCallback? onClose;
  final int messageDelay;

  // ===== PATCH (portcall): reassembly de mensagens SIP sobre TCP =====
  // dart:io Socket entrega bytes crus, sem nenhuma garantia de que um
  // callback de `listen` corresponde a exatamente UMA mensagem SIP — o
  // código original mandava cada pedaço direto pro parser (`onData?.call`),
  // e uma mensagem grande (SDP de chamada com vídeo, cheio de candidato
  // ICE) que chegasse fatiada em dois pacotes de rede quebrava o parser e
  // derrubava a conexão. Aqui acumula os bytes e só entrega mensagens
  // completas (usando Content-Length, como manda o RFC 3261 §7.5 pra
  // transporte orientado a stream) pro resto da pilha.
  final List<int> _pending = <int>[];

  void _feed(List<int> chunk) {
    _pending.addAll(chunk);

    while (true) {
      // Ping de keep-alive: uma ou duas CRLF soltas na frente do buffer.
      if (_pending.length >= 2 && _pending[0] == 0x0D && _pending[1] == 0x0A) {
        final bool isDoubleCrLf = _pending.length >= 4 &&
            _pending[2] == 0x0D &&
            _pending[3] == 0x0A;
        final int pingLen = isDoubleCrLf ? 4 : 2;
        onData?.call('\r\n');
        _pending.removeRange(0, pingLen);
        continue;
      }

      final int headerEnd = _findHeaderEnd(_pending);
      if (headerEnd == -1) {
        // Ainda não chegou o fim dos headers (\r\n\r\n) — espera mais dados.
        break;
      }

      final String headerText =
          utf8.decode(_pending.sublist(0, headerEnd), allowMalformed: true);
      final int contentLength = _extractContentLength(headerText);
      final int totalLength = headerEnd + 4 + contentLength;

      if (_pending.length < totalLength) {
        // Corpo ainda incompleto — espera mais dados.
        break;
      }

      final List<int> messageBytes = _pending.sublist(0, totalLength);
      onData?.call(utf8.decode(messageBytes, allowMalformed: true));
      _pending.removeRange(0, totalLength);
    }
  }

  int _findHeaderEnd(List<int> data) {
    for (int i = 0; i + 3 < data.length; i++) {
      if (data[i] == 0x0D &&
          data[i + 1] == 0x0A &&
          data[i + 2] == 0x0D &&
          data[i + 3] == 0x0A) {
        return i;
      }
    }
    return -1;
  }

  int _extractContentLength(String headerText) {
    for (final String line in headerText.split('\r\n')) {
      final int colon = line.indexOf(':');
      if (colon == -1) continue;
      final String name = line.substring(0, colon).trim().toLowerCase();
      if (name == 'content-length' || name == 'l') {
        return int.tryParse(line.substring(colon + 1).trim()) ?? 0;
      }
    }
    return 0;
  }
  // ===== fim do patch =====

  void connect(
      {Iterable<String>? protocols,
      required TcpSocketSettings tcpSocketSettings}) async {
    handleQueue();
    logger.i('connect $_host:$_port');
    try {
      if (tcpSocketSettings.allowBadCertificate) {
        // /// Allow self-signed certificate, for test only.
        // _socket = await _connectForBadCertificate(_url, tcpSocketSettings);
      } else {
        // used to have these
        //protocols: protocols, headers: webSocketSettings.extraHeaders
        _socket = await Socket.connect(
          _host,
          int.parse(_port),
        );
      }

      onOpen?.call();

      _socket!.listen((dynamic data) {
        _feed(data as List<int>);
      }, onDone: () {
        //  onClose?.call(_socket!., _socket!.closeReason);
      });
    } catch (e) {
      onClose?.call(500, e.toString());
    }
  }

  final StreamController<dynamic> queue = StreamController<dynamic>.broadcast();
  void handleQueue() async {
    queue.stream.asyncMap((dynamic event) async {
      await Future<void>.delayed(Duration(milliseconds: messageDelay));
      return event;
    }).listen((dynamic event) async {
      _socket!.add(event.codeUnits);
      logger.d('send: \n\n$event');
    });
  }

  void send(dynamic data) async {
    if (_socket != null) {
      queue.add(data);
    }
  }

  void close() {
    _socket!.close();
  }
}
