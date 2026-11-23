/// Candle periods supported by both venues. Daily and longer are UTC-aligned.
enum Timeframe { m1, m5, m15, h1, h4, d1, w1, mo1 }

enum OrderSide { buy, sell }

enum OrderType { limit, market }

enum OrderStatus { open, partiallyFilled, filled, cancelled, unknown }

/// One OHLCV bar. [closed] is false while the period is still forming.
class Candle {
  final String symbol;
  final Timeframe timeframe;
  final DateTime openTime;
  final double open, high, low, close, volume;
  final bool closed;

  const Candle({
    required this.symbol,
    required this.timeframe,
    required this.openTime,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
    required this.closed,
  });

  @override
  String toString() =>
      'Candle($symbol ${timeframe.name} ${openTime.toIso8601String()} '
      'o=$open h=$high l=$low c=$close v=$volume closed=$closed)';
}

class Ticker {
  final String symbol;
  final double price;

  const Ticker({required this.symbol, required this.price});

  @override
  String toString() => 'Ticker($symbol $price)';
}

/// A spot instrument in the venue's own [symbol] spelling (`BTCUSDT`, `BTC-USDT`).
///
/// Increments stay strings so they can be used for rounding without float error.
class Instrument {
  final String symbol, base, quote;
  final String tickSize, stepSize, minQuantity;
  final bool trading;

  const Instrument({
    required this.symbol,
    required this.base,
    required this.quote,
    required this.tickSize,
    required this.stepSize,
    required this.minQuantity,
    required this.trading,
  });

  @override
  String toString() =>
      'Instrument($symbol $base/$quote tick=$tickSize step=$stepSize '
      'min=$minQuantity trading=$trading)';
}

/// Amounts are the venue's decimal strings, never re-rendered through a double.
class Balance {
  final String asset, free, locked;

  const Balance({
    required this.asset,
    required this.free,
    required this.locked,
  });

  @override
  String toString() => 'Balance($asset free=$free locked=$locked)';
}

class Order {
  final String symbol, orderId;
  final String? clientOrderId;
  final OrderSide side;
  final OrderType type;
  final OrderStatus status;

  /// Null for market orders.
  final String? price;
  final String quantity, filledQuantity;
  final DateTime createdAt;

  const Order({
    required this.symbol,
    required this.orderId,
    required this.clientOrderId,
    required this.side,
    required this.type,
    required this.status,
    required this.price,
    required this.quantity,
    required this.filledQuantity,
    required this.createdAt,
  });

  @override
  String toString() =>
      'Order($symbol #$orderId ${side.name} ${type.name} ${status.name} '
      '$filledQuantity/$quantity @ ${price ?? 'market'})';
}

/// A spot order. [quantity] is always in the base asset, and [price] is
/// required for limit orders. Amounts are decimal strings sent unchanged.
class OrderRequest {
  final String symbol;
  final OrderSide side;
  final OrderType type;
  final String quantity;
  final String? price;
  final String? clientOrderId;

  const OrderRequest({
    required this.symbol,
    required this.side,
    required this.type,
    required this.quantity,
    this.price,
    this.clientOrderId,
  }) : assert(
         type == OrderType.market || price != null,
         'a limit order needs a price',
       );
}

DateTime fromMillis(Object? millis) => DateTime.fromMillisecondsSinceEpoch(
  millis is int ? millis : int.parse(millis! as String),
  isUtc: true,
);

typedef Json = Map<String, dynamic>;

/// Typed reads of decoded JSON.
extension JsonRead on Json {
  String str(String key) => this[key] as String;
  double num(String key) => double.parse(this[key] as String);
  Json obj(String key) => this[key] as Json;
  List<Json> objs(String key) => (this[key] as List).cast<Json>();
}

/// `List` of JSON objects, as a REST answer that is an array.
List<Json> jsonList(Object? value) => (value! as List).cast<Json>();

/// Element [i] of a candle row, which venues send as strings.
double rowNum(List<Object?> row, int i) => double.parse(row[i]! as String);
