import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto_exchanges/src/common/exchange_socket.dart';
import 'package:test/test.dart';

/// Fan-out against a local echo server: two listeners share one subscription,
/// and the venue is unsubscribed only after the last one leaves.
void main() {
  test('topics are shared, ref-counted and reconnected', () async {
    final received = <String>[];
    final sockets = <WebSocket>[];
    final server = await HttpServer.bind('localhost', 0);
    server.transform(WebSocketTransformer()).listen((ws) {
      sockets.add(ws);
      ws.listen((frame) {
        final m = jsonDecode(frame as String) as Map<String, dynamic>;
        received.add('${m['op']} ${m['topic']}');
        if (m['op'] == 'sub') ws.add(jsonEncode({'topic': m['topic'], 'v': 1}));
      });
    });

    final socket = ExchangeSocket(
      exchange: 'test',
      url: Uri.parse('ws://localhost:${server.port}'),
      subscribeFrame: (t, sub) => {'op': sub ? 'sub' : 'unsub', 'topic': t},
      topicOf: (m) => m['topic'] as String?,
    );

    final a = socket.topic('x').first;
    final b = socket.topic('x').first;
    expect((await a)['v'], 1);
    expect((await b)['v'], 1);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(received, ['sub x', 'unsub x'], reason: 'one sub for two listeners');

    // a dropped connection is re-established and the topic re-subscribed
    received.clear();
    final values = <int>[];
    final sub = socket.topic('y').listen((m) => values.add(m['v'] as int));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await sockets.last.close();
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    expect(values, [1, 1]);
    expect(received, ['sub y', 'sub y']);

    await sub.cancel();
    await socket.close();
    await server.close(force: true);
  });
}
