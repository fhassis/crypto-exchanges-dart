import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart';

class HttpClient {
  late final Hmac _hmac;
  late final String _apiKey;
  late final String _baseUrl;
  final _http = Client();

  HttpClient(
      {required String apiKey,
      required String apiSecret,
      required String baseUrl}) {
    _baseUrl = baseUrl;
    _hmac = Hmac(sha256, utf8.encode(apiSecret));
    _apiKey = apiKey;
  }

  /// Closes the inner http client.
  void close() {
    _http.close();
  }

  /// Sends the HTTP request to Binance server and handles the response.
  Future<dynamic> sendRequest(
      {required String method,
      required String path,
      Map<String, String>? params,
      bool isSigned = false}) async {
    // adds signature if it is a signed request
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

    // creates the http request
    final request = Request(method, Uri.https(_baseUrl, path, params));
    request.headers.addAll({'X-MBX-APIKEY': _apiKey});

    // sends the http request
    final streamedResponse = await request.send();

    // handles the http response
    if (streamedResponse.statusCode == 200) {
      final response = await Response.fromStream(streamedResponse);
      return jsonDecode(response.body);
    } else {
      throw ClientException(
          "HTTP status ${streamedResponse.statusCode}: ${streamedResponse.reasonPhrase}");
    }
  }
}
