import 'models.dart';

/// What every spot connector offers, so callers (e.g. a gRPC server) can be
/// written once for any venue. Symbols use the venue's own spelling.
abstract interface class SpotExchange {
  // --- market data (no credentials needed) ---

  Future<List<Instrument>> fetchInstruments();

  Future<List<Ticker>> fetchTickers();

  /// Up to [limit] most recent bars opening before [end] (default: now),
  /// oldest first. Page backwards by passing the first bar's `openTime` as [end].
  Future<List<Candle>> fetchCandles(
    String symbol,
    Timeframe timeframe, {
    DateTime? end,
    int limit = 100,
  });

  /// Live candle updates. The stream is broadcast and shared: any number of
  /// listeners share one venue subscription, opened on the first listen and
  /// closed when the last one cancels.
  Stream<Candle> candleStream(String symbol, Timeframe timeframe);

  // --- account and trading (credentials required) ---

  Future<List<Balance>> fetchBalances();

  Future<List<Order>> fetchOpenOrders();

  /// Pass exactly one of [orderId] or [clientOrderId].
  Future<Order> fetchOrder(
    String symbol, {
    String? orderId,
    String? clientOrderId,
  });

  /// Returns the venue's order id.
  Future<String> placeOrder(OrderRequest request);

  /// Pass exactly one of [orderId] or [clientOrderId].
  Future<void> cancelOrder(
    String symbol, {
    String? orderId,
    String? clientOrderId,
  });

  /// Raw account events (order updates, balance changes) as the venue sends
  /// them. Broadcast and shared like [candleStream].
  Stream<Map<String, dynamic>> accountStream();

  /// Releases HTTP and websocket resources.
  Future<void> close();
}

void checkOneId(String? orderId, String? clientOrderId) {
  if ((orderId == null) == (clientOrderId == null)) {
    throw ArgumentError('pass exactly one of orderId or clientOrderId');
  }
}
