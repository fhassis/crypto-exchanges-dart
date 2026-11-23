import 'package:crypto_exchanges/src/binance/binance_client.dart';
import 'package:crypto_exchanges/src/binance/ed25519_signer.dart';
import 'package:crypto_exchanges/src/common/models.dart';
import 'package:test/test.dart';

import '../../support/fixture.dart';

void main() {
  test('Ed25519 signature matches the captured vector', () async {
    final v = fixture('binance/private_signature_vector.json') as Json;
    final signer = Ed25519Signer.fromPem(v.str('dummy_secret_pem'));
    expect(await signer.sign(v.str('prehash')), v.str('signature'));
  });

  test('klines: last row is still forming, earlier rows closed', () {
    final rows = (fixture('binance/candles_1h_running_last.json') as List)
        .cast<List<Object?>>();
    final now = (rows.last[0]! as int) + 1000; // inside the last hour
    final candles = [
      for (final r in rows) parseKline(r, 'BTCUSDT', Timeframe.h1, now),
    ];
    expect(candles.first.openTime, DateTime.utc(2026, 9, 18, 20));
    expect(candles.first.open, 81204.77);
    expect(candles.map((c) => c.closed), [true, true, false]);
  });

  test('kline push', () {
    final c = parseWsKline(
      fixture('binance/ws_kline_1w_push.json') as Json,
      Timeframe.w1,
    );
    expect(c.symbol, 'BTCUSDT');
    expect(c.close, 80480.01);
    expect(c.closed, isFalse);
  });

  test('stream names are lower-case with venue intervals', () {
    expect(klineTopic('BTCUSDT', interval(Timeframe.mo1)), 'btcusdt@kline_1M');
    expect(interval(Timeframe.h1), '1h');
  });

  test('instrument reads the filters', () {
    final info = fixture('binance/exchange_info_btcusdt.json') as Json;
    final i = parseInstrument(info.objs('symbols').single);
    expect(i.symbol, 'BTCUSDT');
    expect((i.base, i.quote), ('BTC', 'USDT'));
    expect(i.tickSize, '0.01000000');
    expect(i.trading, isTrue);
  });

  test('order: market price "0" is absent', () {
    final o = parseOrder({
      'symbol': 'BTCUSDT', 'orderId': 7, 'clientOrderId': 'abc', //
      'price': '0.00000000', 'origQty': '1', 'executedQty': '1',
      'status': 'FILLED', 'type': 'MARKET', 'side': 'BUY', 'time': 1,
    });
    expect(o.orderId, '7');
    expect(o.price, isNull);
    expect(o.status, OrderStatus.filled);
    expect(o.type, OrderType.market);
  });
}
