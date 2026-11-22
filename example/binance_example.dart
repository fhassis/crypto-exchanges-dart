import 'package:crypto_exchanges/crypto_exchanges.dart';
import 'package:dotenv/dotenv.dart';

void main() async {
  // loads the .env file at the project root (platform variables take precedence)
  final env = DotEnv(includePlatformEnvironment: true, quiet: true)..load();

  // create the binance spot client
  final binanceSpotClient = BinanceClient(
    apiKey: env['BINANCE_SPOT_API_KEY']!,
    privateKeyPem: env['BINANCE_SPOT_PRIVATE_KEY']!,
    isTestnet: bool.parse(env['BINANCE_SPOT_TESTNET'] ?? 'true'),
  );

  // use some rest endpoints
  print(await binanceSpotClient.fetchServerTime());
  print(await binanceSpotClient.fetchAccountInfo());

  // processes user data stream
  await for (final data in binanceSpotClient.userDataStream()) {
    print(data);
  }
}
