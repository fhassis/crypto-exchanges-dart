import 'dart:async';

import 'package:crypto_exchanges/crypto_exchanges.dart';
import 'package:test/test.dart';

/// Live checks every [SpotExchange] must pass. Runs against the venue's
/// testnet/demo: it places (and cancels) a small limit order far below market.
void spotContract(SpotExchange Function() create, {required String symbol}) {
  late SpotExchange client;
  setUpAll(() => client = create());
  tearDownAll(() => client.close());

  test('instruments include $symbol', () async {
    final all = await client.fetchInstruments();
    expect(all.map((i) => i.symbol), contains(symbol));
  });

  test('tickers include $symbol', () async {
    final all = await client.fetchTickers();
    expect(all.firstWhere((t) => t.symbol == symbol).price, greaterThan(0));
  });

  test('candles are oldest first and page backwards', () async {
    final page = await client.fetchCandles(symbol, Timeframe.m1, limit: 5);
    expect(page, hasLength(5));
    expect(page.first.openTime.isBefore(page.last.openTime), isTrue);

    final older = await client.fetchCandles(
      symbol,
      Timeframe.m1,
      end: page.first.openTime,
      limit: 5,
    );
    expect(
      older.last.openTime,
      page.first.openTime.subtract(const Duration(minutes: 1)),
    );
    expect(older.every((c) => c.closed), isTrue);
  });

  test('candle stream fans out to two listeners', () async {
    final stream = client.candleStream(symbol, Timeframe.m1);
    final both = await Future.wait([
      stream.first,
      stream.first,
    ]).timeout(const Duration(seconds: 30));
    expect(
      both.map((c) => c.symbol.toUpperCase().replaceAll('-', '')),
      everyElement(symbol.replaceAll('-', '')),
    );
  });

  test('balances', () async {
    expect(await client.fetchBalances(), isNotEmpty);
  });

  test(
    'place, read, list and cancel a limit order, seen on the account stream',
    () async {
      final events = <Map<String, dynamic>>[];
      final sub = client.accountStream().listen(events.add);
      await Future<void>.delayed(
        const Duration(seconds: 3),
      ); // login + subscribe

      final instrument = (await client.fetchInstruments()).firstWhere(
        (i) => i.symbol == symbol,
      );
      final last = (await client.fetchTickers())
          .firstWhere((t) => t.symbol == symbol)
          .price;
      final price = roundToStep(last * 0.8, instrument.tickSize);
      final clientOrderId = 'ce${DateTime.now().millisecondsSinceEpoch}';

      final orderId = await client.placeOrder(
        OrderRequest(
          symbol: symbol,
          side: OrderSide.buy,
          type: OrderType.limit,
          quantity: '0.0002',
          price: price,
          clientOrderId: clientOrderId,
        ),
      );
      try {
        // Binance may answer -2013 for a moment after placement (propagation)
        final order = await retry(
          () => client.fetchOrder(symbol, clientOrderId: clientOrderId),
        );
        expect(order.orderId, orderId);
        expect(order.status, OrderStatus.open);
        expect(double.parse(order.price!), double.parse(price));

        final open = await client.fetchOpenOrders();
        expect(open.map((o) => o.orderId), contains(orderId));
      } finally {
        await client.cancelOrder(symbol, orderId: orderId);
      }
      final cancelled = await client.fetchOrder(symbol, orderId: orderId);
      expect(cancelled.status, OrderStatus.cancelled);

      await Future<void>.delayed(const Duration(seconds: 3));
      await sub.cancel();
      expect(
        events,
        isNotEmpty,
        reason: 'order events arrive on the account stream',
      );
    },
  );
}

/// [value] floored to [step] (e.g. '0.01000000'), rendered with its decimals.
String roundToStep(double value, String step) {
  final trimmed = step.contains('.')
      ? step.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
      : step;
  final decimals = trimmed.contains('.') ? trimmed.split('.').last.length : 0;
  final s = double.parse(step);
  return ((value / s).floor() * s).toStringAsFixed(decimals);
}

Future<T> retry<T>(Future<T> Function() f) async {
  for (var i = 0; ; i++) {
    try {
      return await f();
    } on ExchangeException {
      if (i == 4) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }
}
