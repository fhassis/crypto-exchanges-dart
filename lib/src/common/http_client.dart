import 'dart:convert';

import 'package:http/http.dart';

class HttpClient {
  late final String _baseUrl;
  final _http = Client();

  HttpClient({required String baseUrl}) {
    _baseUrl = baseUrl;
  }

  /// Closes the inner http client.
  void close() {
    _http.close();
  }

  /// Sends the HTTP request to Binance server and handles the response.
  Future<dynamic> sendRequest({
    required String method,
    required String path,
    Map<String, String>? queryParams,
    Map<String, String>? headers,
  }) async {
    // creates the http request object
    final request = Request(method, Uri.https(_baseUrl, path, queryParams));

    // adds http headers if required
    if (headers != null) {
      request.headers.addAll(headers);
    }

    // sends the http request
    final streamedResponse = await request.send();

    // handles the http response
    if (streamedResponse.statusCode == 200) {
      final response = await Response.fromStream(streamedResponse);
      return jsonDecode(response.body);
    } else {
      // TODO: create a custom exception to capture status code and message
      throw Exception(
          "HTTP ${streamedResponse.statusCode}: ${streamedResponse.reasonPhrase}");
    }
  }
}
