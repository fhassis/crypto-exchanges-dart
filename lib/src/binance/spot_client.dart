import 'package:exchanges/src/binance/http_client.dart';

class BinanceSpotClient {
  late final BinanceHttpClient _httpClient;

  BinanceSpotClient({required apiKey, required apiSecret, isTestnet = false}) {
    _httpClient = BinanceHttpClient(
      apiKey: apiKey,
      apiSecret: apiSecret,
      baseUrl: isTestnet ? 'testnet.binance.vision' : 'api.binance.com',
    );
  }

  /// Fetches the server time.
  Future<Map<String, dynamic>> fetchServerTime() async {
    return await _httpClient.sendRequest(
      method: 'GET',
      path: '/api/v3/time',
    ) as Map<String, dynamic>;
  }

  /// Fetches the user account information.
  Future<Map<String, dynamic>> fetchAccountInfo() async {
    return await _httpClient.sendRequest(
      method: 'GET',
      path: '/api/v3/account',
      isSigned: true,
    );
  }

  /// Creates a listen key to be used in user data streams.
  Future<Map<String, dynamic>> createListenKey() async {
    return await _httpClient.sendRequest(
      method: 'POST',
      path: '/api/v3/userDataStream',
    );
  }
}
