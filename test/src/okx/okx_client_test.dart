import 'package:crypto_exchanges/crypto_exchanges.dart';
import 'package:test/test.dart';

import '../../support/env.dart';
import '../../support/spot_contract.dart';

void main() {
  group('OkxClient (spot)', () {
    spotContract(
      () => OkxClient(
        apiKey: requireEnv('OKX_SPOT_API_KEY'),
        secret: requireEnv('OKX_SPOT_API_SECRET'),
        passphrase: requireEnv('OKX_SPOT_SECRET_PHRASE'),
        // defaults to demo trading so tests never hit a real account by accident
        isDemo: bool.parse(env['OKX_SPOT_DEMO'] ?? 'true'),
      ),
      symbol: 'BTC-USDT',
    );
  });
}
