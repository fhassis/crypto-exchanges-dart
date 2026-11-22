import 'package:crypto_exchanges/src/binance/binance_client.dart';
import 'package:test/test.dart';

import '../../support/env.dart';

void main() {
  group('BinanceClient (spot)', () {
    late BinanceClient client;

    setUpAll(() {
      client = BinanceClient(
        apiKey: requireEnv('BINANCE_SPOT_API_KEY'),
        privateKeyPem: requireEnv('BINANCE_SPOT_PRIVATE_KEY'),
        // defaults to testnet so tests never hit a real account by accident
        isTestnet: bool.parse(env['BINANCE_SPOT_TESTNET'] ?? 'true'),
      );
    });

    tearDownAll(() => client.close());

    test('fetchServerTime returns data', () async {
      final data = await client.fetchServerTime();
      expect(data, contains('serverTime'));
    });

    test('fetchAccountInfo returns data', () async {
      final data = await client.fetchAccountInfo();
      expect(data, contains('makerCommission'));
    });

    test('createListenKey returns data', () async {
      final data = await client.createListenKey();
      expect(data, contains('listenKey'));
    });
  });
}
