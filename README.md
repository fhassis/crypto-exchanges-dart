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

The tests depend on api key information stored in environment variables:

- Binance Spot:
  - BINANCE_API_KEY (string)
  - BINANCE_API_SECRET (string)
  - BINANCE_TESTNET (`true`)

> ⚠️ An exception will be thrown if these variables are not defined, and the tests will not run.

To execute the test, run the following command: 

```console
dart test --reporter expanded
```
