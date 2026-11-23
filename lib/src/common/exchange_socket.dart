import 'dart:async';
import 'dart:convert';
import 'dart:developer' show log;
import 'dart:io';
import 'dart:math' show min;

import 'http_client.dart' show ExchangeException;
import 'models.dart' show Json;

/// A self-healing websocket with fan-out.
///
/// - [messages] and every [topic] stream are broadcast: any number of
///   listeners share one connection and one venue subscription per topic.
/// - The connection opens on the first listener and closes after the last one
///   cancels; a topic is subscribed on its first listener and unsubscribed
///   after its last.
/// - On drop it reconnects with exponential backoff (1s..30s), runs [onOpen]
///   again (login) and re-subscribes every active topic.
class ExchangeSocket {
  final String exchange;
  final Uri url;

  /// Runs after each connect and before topics are re-subscribed, e.g. login.
  /// Throwing aborts that connection attempt (it is retried with backoff).
  final Future<void> Function(ExchangeSocket socket)? onOpen;

  /// The frame that (un)subscribes [topic]. Required to use [topic].
  final Object Function(String topic, bool subscribe)? subscribeFrame;

  /// The topic a pushed message belongs to, or null.
  final String? Function(Json message)? topicOf;

  /// A refusal carried by a message (code, message), or null.
  final (String, String)? Function(Json message)? errorOf;

  /// An application-level keepalive (OKX closes a silent socket after 30s).
  final String? textPing;

  late final StreamController<Json> _messages = StreamController.broadcast(
    onListen: _start,
    onCancel: _stop,
  );
  final _topics = <String, StreamController<Json>>{};
  final _topicSubscriptions = <String, StreamSubscription<Json>>{};
  WebSocket? _ws;
  int _generation = 0;

  ExchangeSocket({
    required this.exchange,
    required this.url,
    this.onOpen,
    this.subscribeFrame,
    this.topicOf,
    this.errorOf,
    this.textPing,
  });

  /// Every JSON object the venue pushes.
  Stream<Json> get messages => _messages.stream;

  /// Messages for one topic (e.g. `btcusdt@kline_1m`).
  Stream<Json> topic(String topic) => _topics.putIfAbsent(topic, () {
    late final StreamController<Json> controller;
    controller = StreamController.broadcast(
      onListen: () {
        _topicSubscriptions[topic] = messages
            .where((m) => topicOf!(m) == topic)
            .listen(controller.add, onError: controller.addError);
        // When the socket is still connecting, the post-connect resubscribe
        // covers this topic.
        if (_isOpen) send(subscribeFrame!(topic, true));
      },
      onCancel: () {
        if (_isOpen) send(subscribeFrame!(topic, false));
        _topicSubscriptions.remove(topic)?.cancel();
        _topics.remove(topic);
        controller.close();
      },
    );
    return controller;
  }).stream;

  bool get _isOpen => _ws?.readyState == WebSocket.open;

  /// Sends [frame] (a String as-is, anything else JSON-encoded).
  void send(Object frame) {
    final ws = _ws;
    if (ws == null || ws.readyState != WebSocket.open) {
      throw StateError('$exchange socket is not connected');
    }
    ws.add(frame is String ? frame : jsonEncode(frame));
  }

  /// Sends [frame] and waits for the first message [isReply] accepts.
  Future<Json> request(
    Object frame,
    bool Function(Json message) isReply, {
    Duration timeout = const Duration(seconds: 10),
  }) {
    final reply = messages.firstWhere(isReply).timeout(timeout);
    send(frame);
    return reply;
  }

  /// Stops the connection and ends every stream.
  Future<void> close() async {
    _stop();
    for (final c in _topics.values.toList()) {
      await c.close();
    }
    await _messages.close();
  }

  void _start() => _run(++_generation);

  void _stop() {
    _generation++;
    _ws?.close();
    _ws = null;
  }

  Future<void> _run(int generation) async {
    var backoff = const Duration(seconds: 1);
    while (generation == _generation) {
      Timer? keepalive;
      var connected = false;
      try {
        final ws = await WebSocket.connect(
          url.toString(),
        ).timeout(const Duration(seconds: 10));
        if (generation != _generation) {
          await ws.close();
          return;
        }
        // control-frame liveness: a dead link closes instead of hanging
        ws.pingInterval = const Duration(seconds: 20);
        _ws = ws;
        connected = true;

        final closed = Completer<void>();
        ws.listen(
          _onData,
          onDone: () => closed.isCompleted ? null : closed.complete(),
          onError: (Object e) => closed.isCompleted ? null : closed.complete(),
          cancelOnError: true,
        );
        if (textPing != null) {
          keepalive = Timer.periodic(const Duration(seconds: 20), (_) {
            if (_isOpen) ws.add(textPing);
          });
        }

        await onOpen?.call(this);
        for (final topic in _topicSubscriptions.keys) {
          send(subscribeFrame!(topic, true));
        }
        log('$exchange connected to $url', name: 'crypto_exchanges');
        backoff = const Duration(seconds: 1);

        await closed.future;
        log(
          '$exchange disconnected (${ws.closeCode} ${ws.closeReason})',
          name: 'crypto_exchanges',
        );
      } catch (e) {
        log('$exchange socket error: $e', name: 'crypto_exchanges');
        // A refused login reaches listeners; network blips only reconnect, so
        // an `await for` over a stream survives them.
        if (connected && generation == _generation) _messages.addError(e);
        await _ws?.close();
      } finally {
        keepalive?.cancel();
        if (generation == _generation) _ws = null;
      }

      if (generation != _generation) return;
      await Future<void>.delayed(backoff);
      backoff = Duration(seconds: min(backoff.inSeconds * 2, 30));
    }
  }

  void _onData(dynamic data) {
    if (data is! String || data == 'pong') return;
    final Object? decoded;
    try {
      decoded = jsonDecode(data);
    } on FormatException {
      log('$exchange sent non-JSON: $data', name: 'crypto_exchanges');
      return;
    }
    if (decoded is! Json) return;

    final error = errorOf?.call(decoded);
    if (error != null) {
      _messages.addError(ExchangeException(exchange, error.$2, code: error.$1));
    } else {
      _messages.add(decoded);
    }
  }
}
