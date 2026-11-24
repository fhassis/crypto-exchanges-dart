# exchanges

A basic client for cryptocurrency exchanges written in Dart.

## Features

Basic REST and Websocket connections with the following exchanges:

- [x] Binance Spot
- [x] OKX Spot

Both implement `SpotExchange`: instruments, tickers, candles (REST and live),
balances, place/cancel/fetch orders, open orders and a raw account event stream.
Market data needs no credentials.

Websocket streams are broadcast and shared: every listener of
`candleStream(symbol, timeframe)` shares one venue subscription, opened on the
first listen and closed after the last cancel, and re-established after a
dropped connection.

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

# OKX (one key for spot, futures and the other products)
OKX_API_KEY='...'
OKX_SECRET_KEY='...'
OKX_PASSPHRASE='...'
OKX_DEMO='true'
```

- Each value must fit in a single line; encode PEM line breaks as literal `\n`.
- Use single quotes so `$` and `#` inside values are kept as-is.
- `BINANCE_SPOT_TESTNET` and `OKX_DEMO` default to `true` when missing.
- The client tests place and cancel a small limit order far below market on the testnet/demo account.

> ⚠️ A test fails with a clear error if a required variable is missing.

To execute the test, run the following command: 

```console
dart test --reporter expanded
```
