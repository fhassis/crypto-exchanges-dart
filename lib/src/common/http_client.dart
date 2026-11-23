import 'dart:convert';

import 'package:http/http.dart';

/// A venue refused a request, or answered something that is not a success.
class ExchangeException implements Exception {
  final String exchange;
  final int? statusCode;

  /// The venue's own error code (`-1013` on Binance, `51000` on OKX).
  final String? code;
  final String message;

  const ExchangeException(
    this.exchange,
    this.message, {
    this.statusCode,
    this.code,
  });

  @override
  String toString() =>
      'ExchangeException($exchange, http=$statusCode, code=$code): $message';
}

class HttpClient {
  final String exchange;
  final String _baseUrl;
  final Client _http = Client();

  HttpClient({required this.exchange, required String baseUrl})
    : _baseUrl = baseUrl;

  /// Closes the inner http client.
  void close() => _http.close();

  /// The exact URL a request goes to. Signers sign from this, so the bytes
  /// signed are the bytes sent.
  Uri uri(String path, [Map<String, String>? queryParams]) => Uri.https(
    _baseUrl,
    path,
    queryParams == null || queryParams.isEmpty ? null : queryParams,
  );

  /// Sends the request and returns the decoded JSON body.
  ///
  /// Non-2xx answers throw [ExchangeException], reading the `code`/`msg` pair
  /// both Binance and OKX put in their error bodies.
  Future<dynamic> send(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    String? body,
  }) async {
    final request = Request(method, uri);
    if (headers != null) request.headers.addAll(headers);
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = body;
    }

    final response = await Response.fromStream(await _http.send(request));
    final ok = response.statusCode >= 200 && response.statusCode < 300;

    dynamic json;
    try {
      json = jsonDecode(response.body);
    } on FormatException {
      throw ExchangeException(
        exchange,
        'non-JSON answer: ${_head(response.body)}',
        statusCode: response.statusCode,
      );
    }
    if (ok) return json;

    throw ExchangeException(
      exchange,
      json is Map ? '${json['msg']}' : _head(response.body),
      statusCode: response.statusCode,
      code: json is Map ? json['code']?.toString() : null,
    );
  }

  static String _head(String body) =>
      body.length > 200 ? '${body.substring(0, 200)}…' : body;
}
