import 'package:crypto_exchanges/crypto_exchanges.dart';
import 'package:test/test.dart';

import '../../support/env.dart';
import '../../support/spot_contract.dart';

void main() {
  group('BinanceClient (spot)', () {
    spotContract(
      () => BinanceClient(
        apiKey: requireEnv('BINANCE_SPOT_API_KEY'),
        privateKeyPem: requireEnv('BINANCE_SPOT_PRIVATE_KEY'),
        // defaults to testnet so tests never hit a real account by accident
        isTestnet: bool.parse(env['BINANCE_SPOT_TESTNET'] ?? 'true'),
      ),
      symbol: 'BTCUSDT',
    );
  });
}
