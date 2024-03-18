import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:crypto_exchanges/src/binance/websocket_client.dart';
import 'package:crypto_exchanges/src/common/http_client.dart';

class BinanceClient {
  late final HttpClient _httpClient;
  late final BinanceWebsocketClient _wsClient;
  late final Hmac _hmac;
  late final String _apiKey;

  BinanceClient({required apiKey, required apiSecret, isTestnet = false}) {
    _httpClient = HttpClient(
      baseUrl: isTestnet ? 'testnet.binance.vision' : 'api.binance.com',
    );
    _wsClient = BinanceWebsocketClient(
      baseUrl: isTestnet
          ? 'wss://testnet.binance.vision/stream'
          : 'wss://stream.binance.com:9443/stream',
    );
    _hmac = Hmac(sha256, utf8.encode(apiSecret));
    _apiKey = apiKey;
  }

  Future<dynamic> _sendRequest({
    required String method,
    required String path,
    Map<String, String>? params,
    bool isSigned = false,
  }) async {
    // adds more parameters if endpoint is signed
    if (isSigned) {
      params ??= <String, String>{};

      // adds timestamp information required for signed endpoints
      params['timestamp'] =
          DateTime.now().toUtc().millisecondsSinceEpoch.toString();

      // generate the query string based on the original query params
      final queryString = utf8.encode(Uri(queryParameters: params).query);

      // add signature to the query parameters
      params['signature'] = _hmac.convert(queryString).toString();
    }

    // adds request headers
    var headers = {'X-MBX-APIKEY': _apiKey};

    // sends the http request
    return await _httpClient.sendRequest(
      method: method,
      path: path,
      queryParams: params,
      headers: headers,
    );
  }

  /// Fetches the server time.
  Future<Map<String, dynamic>> fetchServerTime() async {
    return await _sendRequest(
      method: 'GET',
      path: '/api/v3/time',
    ) as Map<String, dynamic>;
  }

  /// Fetches the user account information.
  Future<Map<String, dynamic>> fetchAccountInfo() async {
    return await _sendRequest(
      method: 'GET',
      path: '/api/v3/account',
      isSigned: true,
    );
  }

  /// Creates a listen key to be used in user data streams.
  Future<Map<String, dynamic>> createListenKey() async {
    return await _sendRequest(
      method: 'POST',
      path: '/api/v3/userDataStream',
    );
  }

  Stream<Map<String, dynamic>> userDataStream() async* {
    // creates the listenKey
    final rawData = await createListenKey();
    final listenKey = rawData['listenKey'];

    // subscribes to user data
    _wsClient.subscribeToUserData(listenKey);

    // keeps receiving user data stream
    await for (var data in _wsClient.stream()) {
      // TODO: parse stream data before yield
      yield data;
    }

    // TODO: create renew task here
  }
}
