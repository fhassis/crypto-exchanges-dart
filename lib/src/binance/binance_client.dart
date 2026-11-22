import 'package:crypto_exchanges/src/binance/ed25519_signer.dart';
import 'package:crypto_exchanges/src/binance/websocket_client.dart';
import 'package:crypto_exchanges/src/common/http_client.dart';

class BinanceClient {
  final HttpClient _httpClient;
  final BinanceWebsocketClient _wsClient;
  final Ed25519Signer _signer;
  final String _apiKey;

  /// Creates a Binance Spot client authenticated with an Ed25519 key pair.
  ///
  /// [privateKeyPem] is the PKCS#8 PEM private key whose public key was
  /// registered on Binance together with [apiKey].
  BinanceClient({
    required String apiKey,
    required String privateKeyPem,
    bool isTestnet = false,
  }) : _httpClient = HttpClient(
         baseUrl: isTestnet ? 'testnet.binance.vision' : 'api.binance.com',
       ),
       _wsClient = BinanceWebsocketClient(
         baseUrl: isTestnet
             ? 'wss://testnet.binance.vision/stream'
             : 'wss://stream.binance.com:9443/stream',
       ),
       _signer = Ed25519Signer.fromPem(privateKeyPem),
       _apiKey = apiKey;

  /// Closes the underlying HTTP client.
  void close() => _httpClient.close();

  Future<Map<String, dynamic>> _sendRequest({
    required String method,
    required String path,
    Map<String, String>? params,
    bool isSigned = false,
  }) async {
    // adds more parameters if endpoint is signed
    if (isSigned) {
      params ??= <String, String>{};

      // adds timestamp information required for signed endpoints
      params['timestamp'] = DateTime.now()
          .toUtc()
          .millisecondsSinceEpoch
          .toString();

      // signs the exact query string that will be sent
      final queryString = Uri(queryParameters: params).query;

      // add signature to the query parameters (URL-encoded when sent)
      params['signature'] = await _signer.sign(queryString);
    }

    // adds request headers
    final headers = {'X-MBX-APIKEY': _apiKey};

    // sends the http request
    final response = await _httpClient.sendRequest(
      method: method,
      path: path,
      queryParams: params,
      headers: headers,
    );
    return response as Map<String, dynamic>;
  }

  /// Fetches the server time.
  Future<Map<String, dynamic>> fetchServerTime() =>
      _sendRequest(method: 'GET', path: '/api/v3/time');

  /// Fetches the user account information.
  Future<Map<String, dynamic>> fetchAccountInfo() =>
      _sendRequest(method: 'GET', path: '/api/v3/account', isSigned: true);

  /// Creates a listen key to be used in user data streams.
  Future<Map<String, dynamic>> createListenKey() =>
      _sendRequest(method: 'POST', path: '/api/v3/userDataStream');

  /// Stream of user data events.
  Stream<Map<String, dynamic>> userDataStream() async* {
    // creates the listenKey
    final rawData = await createListenKey();
    final listenKey = rawData['listenKey'] as String;

    // subscribes to user data
    _wsClient.subscribeToUserData(listenKey);

    // keeps receiving user data stream
    await for (final data in _wsClient.stream()) {
      // TODO: parse stream data before yield
      yield data;
    }

    // TODO: create renew task here
  }
}
