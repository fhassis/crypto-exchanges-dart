import 'package:dotenv/dotenv.dart';

/// Variables from the `.env` file at the project root.
///
/// Platform environment variables (e.g. from CI) take precedence, and a
/// missing `.env` file is not an error.
final env = DotEnv(includePlatformEnvironment: true, quiet: true)..load();

/// Returns the variable [key], failing with a clear message when missing.
String requireEnv(String key) {
  final value = env[key];
  if (value == null || value.isEmpty) {
    throw StateError('Missing environment variable $key (see .env).');
  }
  return value;
}
