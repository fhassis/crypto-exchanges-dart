import 'package:crypto_exchanges/src/binance/ed25519_signer.dart';
import 'package:crypto_exchanges/src/common/exchange_socket.dart';
import 'package:crypto_exchanges/src/common/http_client.dart';
import 'package:crypto_exchanges/src/common/models.dart';
import 'package:crypto_exchanges/src/common/spot_exchange.dart';

/// Binance Spot.
///
/// Market data needs no credentials. Account and trading calls need an
/// Ed25519 key pair: Binance only accepts Ed25519 for `session.logon`, the
/// sole route to the account event feed (`POST /api/v3/userDataStream`
/// answers 410 Gone).
class BinanceClient implements SpotExchange {
  final HttpClient _http;
  final String? _apiKey;
  final Ed25519Signer? _signer;
  late final ExchangeSocket _market;
  late final ExchangeSocket _account;
  int _requestId = 0;

  /// [privateKeyPem] is the PKCS#8 PEM private key whose public key was
  /// registered on Binance together with [apiKey].
  BinanceClient({String? apiKey, String? privateKeyPem, bool isTestnet = false})
    : _http = HttpClient(
        exchange: 'binance',
        baseUrl: isTestnet ? 'testnet.binance.vision' : 'api.binance.com',
      ),
      _apiKey = apiKey,
      _signer = privateKeyPem == null
          ? null
          : Ed25519Signer.fromPem(privateKeyPem) {
    _market = ExchangeSocket(
      exchange: 'binance',
      url: Uri.parse(
        isTestnet
            ? 'wss://stream.testnet.binance.vision/ws'
            : 'wss://stream.binance.com:9443/ws',
      ),
      subscribeFrame: (topic, subscribe) => {
        'method': subscribe ? 'SUBSCRIBE' : 'UNSUBSCRIBE',
        'params': [topic],
        'id': ++_requestId,
      },
      topicOf: (m) => m['e'] == 'kline'
          ? klineTopic(m.str('s'), m.obj('k').str('i'))
          : null,
      errorOf: _wsError,
    );
    _account = ExchangeSocket(
      exchange: 'binance',
      url: Uri.parse(
        isTestnet
            ? 'wss://ws-api.testnet.binance.vision/ws-api/v3'
            : 'wss://ws-api.binance.com/ws-api/v3',
      ),
      onOpen: _logon,
      errorOf: _wsError,
    );
  }

  @override
  Future<void> close() async {
    _http.close();
    await _market.close();
    await _account.close();
  }

  // --- market data ---

  /// Fetches the server time.
  Future<Map<String, dynamic>> fetchServerTime() async =>
      await _send('GET', '/api/v3/time') as Map<String, dynamic>;

  @override
  Future<List<Instrument>> fetchInstruments() async {
    final info = await _send('GET', '/api/v3/exchangeInfo') as Json;
    return info.objs('symbols').map(parseInstrument).toList();
  }

  @override
  Future<List<Ticker>> fetchTickers() async => [
    for (final t in jsonList(await _send('GET', '/api/v3/ticker/price')))
      Ticker(symbol: t.str('symbol'), price: t.num('price')),
  ];

  @override
  Future<List<Candle>> fetchCandles(
    String symbol,
    Timeframe timeframe, {
    DateTime? end,
    int limit = 100,
  }) async {
    final rows =
        await _send('GET', '/api/v3/klines', {
              'symbol': symbol,
              'interval': interval(timeframe),
              'limit': '$limit',
              // endTime is inclusive on the open time; `end` is exclusive
              if (end != null) 'endTime': '${end.millisecondsSinceEpoch - 1}',
            })
            as List<Object?>;
    final now = DateTime.now().millisecondsSinceEpoch;
    return [
      for (final row in rows)
        parseKline(row! as List<Object?>, symbol, timeframe, now),
    ];
  }

  @override
  Stream<Candle> candleStream(String symbol, Timeframe timeframe) => _market
      .topic(klineTopic(symbol, interval(timeframe)))
      .map((m) => parseWsKline(m, timeframe));

  // --- account and trading ---

  /// Fetches the raw account information.
  Future<Map<String, dynamic>> fetchAccountInfo() async =>
      await _send('GET', '/api/v3/account', null, true) as Json;

  @override
  Future<List<Balance>> fetchBalances() async {
    final account = await fetchAccountInfo();
    return [
      for (final b in account.objs('balances'))
        if (b.num('free') + b.num('locked') != 0)
          Balance(
            asset: b.str('asset'),
            free: b.str('free'),
            locked: b.str('locked'),
          ),
    ];
  }

  @override
  Future<List<Order>> fetchOpenOrders() async => [
    for (final o in jsonList(
      await _send('GET', '/api/v3/openOrders', null, true),
    ))
      parseOrder(o),
  ];

  @override
  Future<Order> fetchOrder(
    String symbol, {
    String? orderId,
    String? clientOrderId,
  }) async => parseOrder(
    await _send(
          'GET',
          '/api/v3/order',
          _orderRef(symbol, orderId, clientOrderId),
          true,
        )
        as Json,
  );

  @override
  Future<String> placeOrder(OrderRequest request) async {
    final ack =
        await _send('POST', '/api/v3/order', {
              'symbol': request.symbol,
              'side': request.side == OrderSide.buy ? 'BUY' : 'SELL',
              'type': request.type == OrderType.limit ? 'LIMIT' : 'MARKET',
              // always base quantity; quoteOrderQty would differ by the price
              'quantity': request.quantity,
              if (request.type == OrderType.limit) ...{
                'price': request.price!,
                // explicit, so the order rests instead of following a venue default
                'timeInForce': 'GTC',
              },
              if (request.clientOrderId != null)
                'newClientOrderId': request.clientOrderId!,
            }, true)
            as Json;
    return '${ack['orderId']}';
  }

  @override
  Future<void> cancelOrder(
    String symbol, {
    String? orderId,
    String? clientOrderId,
  }) => _send(
    'DELETE',
    '/api/v3/order',
    _orderRef(symbol, orderId, clientOrderId),
    true,
  );

  /// Raw user data events (`executionReport`, `outboundAccountPosition`, ...).
  @override
  Stream<Map<String, dynamic>> accountStream() {
    _credentials();
    return _account.messages
        .where((m) => m['event'] is Map)
        .map((m) => m.obj('event'));
  }

  // --- plumbing ---

  (String, Ed25519Signer) _credentials() {
    final key = _apiKey, signer = _signer;
    if (key == null || signer == null) {
      throw StateError('Binance account calls need apiKey and privateKeyPem');
    }
    return (key, signer);
  }

  Future<dynamic> _send(
    String method,
    String path, [
    Map<String, String>? params,
    bool signed = false,
  ]) async {
    final query = {...?params};
    final headers = <String, String>{};
    if (signed) {
      final (key, signer) = _credentials();
      query['timestamp'] = '${DateTime.now().millisecondsSinceEpoch}';
      // signs the exact query string that is sent (signature appended last)
      query['signature'] = await signer.sign(Uri(queryParameters: query).query);
      headers['X-MBX-APIKEY'] = key;
    }
    return _http.send(method, _http.uri(path, query), headers: headers);
  }

  Future<void> _logon(ExchangeSocket socket) async {
    final (key, signer) = _credentials();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    // the WebSocket API signs its parameters sorted by name
    final signature = await signer.sign('apiKey=$key&timestamp=$timestamp');
    await socket.request({
      'id': 'logon',
      'method': 'session.logon',
      'params': {'apiKey': key, 'signature': signature, 'timestamp': timestamp},
    }, (m) => m['id'] == 'logon');
    await socket.request({
      'id': 'subscribe',
      'method': 'userDataStream.subscribe',
    }, (m) => m['id'] == 'subscribe');
  }

  static Map<String, String> _orderRef(
    String symbol,
    String? orderId,
    String? clientOrderId,
  ) {
    checkOneId(orderId, clientOrderId);
    return {
      'symbol': symbol,
      'orderId': ?orderId,
      'origClientOrderId': ?clientOrderId,
    };
  }

  static (String, String)? _wsError(Json m) => m['error'] is Map
      ? ('${m.obj('error')['code']}', '${m.obj('error')['msg']}')
      : null;
}

// --- parsing, public for tests ---

String interval(Timeframe timeframe) => switch (timeframe) {
  Timeframe.m1 => '1m',
  Timeframe.m5 => '5m',
  Timeframe.m15 => '15m',
  Timeframe.h1 => '1h',
  Timeframe.h4 => '4h',
  Timeframe.d1 => '1d',
  Timeframe.w1 => '1w',
  Timeframe.mo1 => '1M', // capital M: `1m` is the minute
};

/// Stream names are lower-case; the wrong case is acknowledged and then silent.
String klineTopic(String symbol, String interval) =>
    '${symbol.toLowerCase()}@kline_$interval';

/// A `/api/v3/klines` row. [nowMillis] decides whether the bar has closed.
Candle parseKline(
  List<Object?> row,
  String symbol,
  Timeframe timeframe,
  int nowMillis,
) => Candle(
  symbol: symbol,
  timeframe: timeframe,
  openTime: fromMillis(row[0]),
  open: rowNum(row, 1),
  high: rowNum(row, 2),
  low: rowNum(row, 3),
  close: rowNum(row, 4),
  volume: rowNum(row, 5),
  closed: (row[6]! as int) < nowMillis,
);

/// A `kline` push from the market stream.
Candle parseWsKline(Json m, Timeframe timeframe) {
  final k = m.obj('k');
  return Candle(
    symbol: k.str('s'),
    timeframe: timeframe,
    openTime: fromMillis(k['t']),
    open: k.num('o'),
    high: k.num('h'),
    low: k.num('l'),
    close: k.num('c'),
    volume: k.num('v'),
    closed: k['x'] as bool,
  );
}

Instrument parseInstrument(Json s) {
  final filters = {for (final f in s.objs('filters')) f.str('filterType'): f};
  return Instrument(
    symbol: s.str('symbol'),
    base: s.str('baseAsset'),
    quote: s.str('quoteAsset'),
    tickSize: filters['PRICE_FILTER']?['tickSize'] as String? ?? '0',
    stepSize: filters['LOT_SIZE']?['stepSize'] as String? ?? '0',
    minQuantity: filters['LOT_SIZE']?['minQty'] as String? ?? '0',
    trading: s['status'] == 'TRADING',
  );
}

Order parseOrder(Json o) => Order(
  symbol: o.str('symbol'),
  orderId: '${o['orderId']}',
  clientOrderId: o['clientOrderId'] as String?,
  side: o['side'] == 'BUY' ? OrderSide.buy : OrderSide.sell,
  type: o['type'] == 'MARKET' ? OrderType.market : OrderType.limit,
  status: switch (o['status']) {
    'NEW' || 'PENDING_NEW' => OrderStatus.open,
    'PARTIALLY_FILLED' => OrderStatus.partiallyFilled,
    'FILLED' => OrderStatus.filled,
    'CANCELED' ||
    'EXPIRED' ||
    'EXPIRED_IN_MATCH' ||
    'REJECTED' => OrderStatus.cancelled,
    _ => OrderStatus.unknown,
  },
  // a market order is spelled "0.00000000", which is absent, not zero
  price: o.num('price') == 0 ? null : o.str('price'),
  quantity: o.str('origQty'),
  filledQuantity: o.str('executedQty'),
  createdAt: fromMillis(o['time']),
);
