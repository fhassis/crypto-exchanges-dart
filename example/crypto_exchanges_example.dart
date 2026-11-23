import 'package:crypto_exchanges/crypto_exchanges.dart';

void main() async {
  // market data needs no credentials
  final SpotExchange binance = BinanceClient();
  final SpotExchange okx = OkxClient();

  print(await binance.fetchCandles('BTCUSDT', Timeframe.h1, limit: 3));
  print(await okx.fetchCandles('BTC-USDT', Timeframe.h1, limit: 3));

  // live candles: any number of listeners share one venue subscription
  final candles = binance.candleStream('BTCUSDT', Timeframe.m1);
  final a = candles.listen((c) => print('A $c'));
  final b = candles.listen((c) => print('B $c'));
  await Future<void>.delayed(const Duration(seconds: 5));
  await a.cancel();
  await b.cancel(); // last listener gone: unsubscribed and disconnected

  await binance.close();
  await okx.close();
}
