# exchanges

A basic client for cryptocurrency exchanges written in Dart.

## Features

Basic REST and Websocket connections with the following exchanges:

- [x] Binance Spot

## Getting started

TODO: List prerequisites and provide or point to information on how to
start using the package.

## Usage

TODO: Include short and useful examples for package users. Add longer examples
to `/example` folder. 

```dart
const like = 'sample';
```

## Testing

The tests read API credentials from a `.env` file at the project root (ignored by git).
Variables already defined in the environment (e.g. in CI) take precedence over the file.

```dotenv
# Binance Spot (Ed25519 key pair)
BINANCE_SPOT_API_KEY='...'
BINANCE_SPOT_PRIVATE_KEY='-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----'
BINANCE_SPOT_TESTNET='true'

# OKX Spot
OKX_SPOT_API_KEY='...'
OKX_SPOT_API_SECRET='...'
OKX_SPOT_SECRET_PHRASE='...'
```

- Each value must fit in a single line; encode PEM line breaks as literal `\n`.
- Use single quotes so `$` and `#` inside values are kept as-is.
- `BINANCE_SPOT_TESTNET` defaults to `true` when missing.

> ⚠️ A test fails with a clear error if a required variable is missing.

To execute the test, run the following command: 

```console
dart test --reporter expanded
```
