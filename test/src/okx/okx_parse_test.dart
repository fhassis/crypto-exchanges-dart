import 'package:crypto_exchanges/src/common/http_client.dart';
import 'package:crypto_exchanges/src/common/models.dart';
import 'package:crypto_exchanges/src/okx/okx_client.dart';
import 'package:test/test.dart';

import '../../support/fixture.dart';

void main() {
  test('HMAC signature matches the captured vector', () async {
    final v = fixture('okx/private_signature_vector.json') as Json;
    expect(
      await sign(v.str('dummy_secret'), v.str('prehash')),
      v.str('signature'),
    );
  });

  test('candle rows: running bar has confirm 0', () {
    final rows = readEnvelope(
      fixture('okx/candles_1m_walk_page01.json') as Json,
    );
    final first = parseCandle(
      rows.first! as List<Object?>,
      'BTC-USDT',
      Timeframe.m1,
    );
    final second = parseCandle(
      rows[1]! as List<Object?>,
      'BTC-USDT',
      Timeframe.m1,
    );
    expect(first.closed, isFalse);
    expect(second.closed, isTrue);
    expect(
      first.openTime.isAfter(second.openTime),
      isTrue,
      reason: 'newest first',
    );
    expect(first.close, 82633.1);
  });

  test('candle push', () {
    final m = fixture('okx/ws_candle1mutc_push.json') as Json;
    final c = parseCandle(
      (m['data'] as List).first as List<Object?>,
      'BTC-USDT',
      Timeframe.mo1,
    );
    expect(c.openTime, DateTime.utc(2026, 10));
    expect(c.closed, isFalse);
  });

  test('daily and longer bars use the UTC-aligned spellings', () {
    expect(bar(Timeframe.d1), '1Dutc');
    expect(bar(Timeframe.h4), '4H');
  });

  test('instrument', () {
    final i = parseInstrument(
      readEnvelope(fixture('okx/spot_instrument_btc_usdt.json') as Json).single!
          as Json,
    );
    expect(i.symbol, 'BTC-USDT');
    expect(
      (i.tickSize, i.stepSize, i.minQuantity),
      ('0.1', '0.00000001', '0.00001'),
    );
    expect(i.trading, isTrue);
  });

  test('open order: empty clOrdId is absent', () {
    final o = parseOrder(
      readEnvelope(fixture('okx/private_open_orders_live.json') as Json).single!
          as Json,
    );
    expect(o.clientOrderId, isNull);
    expect(
      (o.price, o.quantity, o.status),
      ('20000', '0.001', OrderStatus.open),
    );
  });

  test('accepted order returns its row', () {
    final rows = readEnvelope(
      fixture('okx/trade_place_limit_accepted.json') as Json,
    );
    expect((rows.single! as Json)['ordId'], '3920469632261296128');
  });

  test('rejected order surfaces the row sCode, not the envelope code', () {
    expect(
      () => readEnvelope(
        fixture('okx/trade_place_client_order_id_punctuation.json') as Json,
      ),
      throwsA(
        isA<ExchangeException>()
            .having((e) => e.code, 'code', '51000')
            .having((e) => e.message, 'message', 'Parameter clOrdId error'),
      ),
    );
  });
}
