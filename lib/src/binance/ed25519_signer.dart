import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// Signs Binance API payloads with an Ed25519 private key.
///
/// See https://developers.binance.com/docs/binance-spot-api-docs/rest-api/endpoint-security-type
class Ed25519Signer {
  /// DER prefix of a PKCS#8 Ed25519 private key; the 32-byte seed follows it.
  static const _pkcs8Prefix = [
    0x30, 0x2e, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06, //
    0x03, 0x2b, 0x65, 0x70, 0x04, 0x22, 0x04, 0x20,
  ];

  static final _algorithm = Ed25519();

  final Future<SimpleKeyPair> _keyPair;

  /// Creates a signer from a PKCS#8 PEM private key.
  ///
  /// Accepts real line breaks or literal `\n` sequences, so the key can be
  /// stored in a single line of a `.env` file.
  Ed25519Signer.fromPem(String pem)
    : _keyPair = _algorithm.newKeyPairFromSeed(_seedFromPem(pem));

  /// Returns the base64-encoded Ed25519 signature of [payload].
  Future<String> sign(String payload) async {
    final signature = await _algorithm.sign(
      utf8.encode(payload),
      keyPair: await _keyPair,
    );
    return base64.encode(signature.bytes);
  }

  static List<int> _seedFromPem(String pem) {
    final body = pem
        .replaceAll(r'\n', '\n')
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('-----'))
        .join();

    final der = base64.decode(body);
    final hasPrefix =
        der.length == _pkcs8Prefix.length + 32 &&
        Iterable<int>.generate(
          _pkcs8Prefix.length,
        ).every((i) => der[i] == _pkcs8Prefix[i]);
    if (!hasPrefix) {
      throw const FormatException('Not a PKCS#8 Ed25519 private key.');
    }
    return der.sublist(_pkcs8Prefix.length);
  }
}
