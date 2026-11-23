import 'dart:convert';

import 'package:crypto_exchanges/src/common/exchange_socket.dart';
import 'package:crypto_exchanges/src/common/http_client.dart';
import 'package:crypto_exchanges/src/common/models.dart';
import 'package:crypto_exchanges/src/common/spot_exchange.dart';
import 'package:cryptography/cryptography.dart';

/// OKX Spot (`tdMode=cash`).
///
/// Market data needs no credentials; account and trading calls need the API
/// key, secret and passphrase. [isDemo] targets demo trading: a demo key is
/// refused on production (`50101`) and vice versa.
class OkxClient implements SpotExchange {
  final HttpClient _http;
  final String? _apiKey, _secret, _passphrase;
  final bool isDemo;
  late final ExchangeSocket _market;
  late final ExchangeSocket _account;

  OkxClient({
    String? apiKey,
    String? secret,
    String? passphrase,
    this.isDemo = false,
  }) : _http = HttpClient(exchange: 'okx', baseUrl: 'www.okx.com'),
       _apiKey = apiKey,
       _secret = secret,
       _passphrase = passphrase {
    final host = isDemo ? 'wspap.okx.com' : 'ws.okx.com';
    _market = ExchangeSocket(
      exchange: 'okx',
      // candles live on /business, not /public
      url: Uri.parse('wss://$host:8443/ws/v5/business'),
      subscribeFrame: (topic, subscribe) {
        final [channel, instId] = topic.split(':');
        return {
          'op': subscribe ? 'subscribe' : 'unsubscribe',
          'args': [
            {'channel': channel, 'instId': instId},
          ],
        };
      },
      // acks carry `arg` too but no `data`; routing never depends on order,
      // since a push can arrive before its own subscription's ack
      topicOf: (m) => m['data'] != null && m['arg'] is Map
          ? '${m.obj('arg')['channel']}:${m.obj('arg')['instId']}'
          : null,
      errorOf: _wsError,
      textPing: 'ping',
    );
    _account = ExchangeSocket(
      exchange: 'okx',
      url: Uri.parse('wss://$host:8443/ws/v5/private'),
      onOpen: _login,
      errorOf: _wsError,
      textPing: 'ping',
    );
  }

  @override
  Future<void> close() async {
    _http.close();
    await _market.close();
    await _account.close();
  }

  // --- market data ---

  @override
  Future<List<Instrument>> fetchInstruments() async => [
    for (final i in jsonList(
      await _send('GET', '/api/v5/public/instruments', {'instType': 'SPOT'}),
    ))
      parseInstrument(i),
  ];

  @override
  Future<List<Ticker>> fetchTickers() async => [
    for (final t in jsonList(
      await _send('GET', '/api/v5/market/tickers', {'instType': 'SPOT'}),
    ))
      // an instrument that has never traded has `last: ""`
      if (t['last'] != '')
        Ticker(symbol: t.str('instId'), price: t.num('last')),
  ];

  /// [limit] is capped at 300 by the venue, which truncates silently.
  @override
  Future<List<Candle>> fetchCandles(
    String symbol,
    Timeframe timeframe, {
    DateTime? end,
    int limit = 100,
  }) async {
    final rows = await _send('GET', '/api/v5/market/history-candles', {
      'instId': symbol,
      'bar': bar(timeframe),
      'limit': '$limit',
      // `after` = rows opening strictly before this instant
      if (end != null) 'after': '${end.millisecondsSinceEpoch}',
    });
    // newest first on the wire
    return [
      for (final row in rows.reversed)
        parseCandle(row! as List<Object?>, symbol, timeframe),
    ];
  }

  @override
  Stream<Candle> candleStream(String symbol, Timeframe timeframe) => _market
      .topic('candle${bar(timeframe)}:$symbol')
      .expand(
        (m) => [
          for (final row in m['data'] as List)
            parseCandle(row as List<Object?>, symbol, timeframe),
        ],
      );

  // --- account and trading ---

  @override
  Future<List<Balance>> fetchBalances() async {
    final data = await _send(
      'GET',
      '/api/v5/account/balance',
      null,
      null,
      true,
    );
    return [
      for (final d in (data.first! as Json).objs('details'))
        Balance(
          asset: d.str('ccy'),
          free: d.str('availBal'),
          locked: d.str('frozenBal'),
        ),
    ];
  }

  @override
  Future<List<Order>> fetchOpenOrders() async => [
    for (final o in jsonList(
      await _send(
        'GET',
        '/api/v5/trade/orders-pending',
        {'instType': 'SPOT'},
        null,
        true,
      ),
    ))
      parseOrder(o),
  ];

  @override
  Future<Order> fetchOrder(
    String symbol, {
    String? orderId,
    String? clientOrderId,
  }) async => parseOrder(
    (await _send(
          'GET',
          '/api/v5/trade/order',
          _orderRef(symbol, orderId, clientOrderId),
          null,
          true,
        )).first!
        as Json,
  );

  /// OKX client order ids are letters and digits only, at most 32 chars.
  @override
  Future<String> placeOrder(OrderRequest request) async {
    final ack = await _send('POST', '/api/v5/trade/order', null, {
      'instId': request.symbol,
      'tdMode': 'cash',
      'side': request.side.name,
      'ordType': request.type.name,
      'sz': request.quantity,
      if (request.type == OrderType.limit) 'px': request.price,
      // market orders default to quote-denominated size on buys; force base
      if (request.type == OrderType.market) 'tgtCcy': 'base_ccy',
      'clOrdId': ?request.clientOrderId,
    }, true);
    return (ack.first! as Json).str('ordId');
  }

  @override
  Future<void> cancelOrder(
    String symbol, {
    String? orderId,
    String? clientOrderId,
  }) => _send(
    'POST',
    '/api/v5/trade/cancel-order',
    null,
    _orderRef(symbol, orderId, clientOrderId),
    true,
  );

  /// Raw pushes from the `account` and `orders` (SPOT) channels: the whole
  /// frame, with `arg.channel` saying which.
  @override
  Stream<Map<String, dynamic>> accountStream() {
    _credentials();
    return _account.messages.where((m) => m['data'] != null);
  }

  // --- plumbing ---

  (String, String, String) _credentials() {
    final key = _apiKey, secret = _secret, passphrase = _passphrase;
    if (key == null || secret == null || passphrase == null) {
      throw StateError('OKX account calls need apiKey, secret and passphrase');
    }
    return (key, secret, passphrase);
  }

  /// Sends a request and returns the envelope's `data` list.
  Future<List<Object?>> _send(
    String method,
    String path, [
    Map<String, String>? query,
    Map<String, dynamic>? body,
    bool signed = false,
  ]) async {
    final uri = _http.uri(path, query);
    final bodyText = body == null ? null : jsonEncode(body);
    final headers = {if (isDemo) 'x-simulated-trading': '1'};
    if (signed) {
      final (key, secret, passphrase) = _credentials();
      final timestamp = DateTime.fromMillisecondsSinceEpoch(
        DateTime.now().millisecondsSinceEpoch,
        isUtc: true,
      ).toIso8601String();
      final requestPath = uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
      headers.addAll({
        'OK-ACCESS-KEY': key,
        'OK-ACCESS-SIGN': await sign(
          secret,
          '$timestamp$method$requestPath${bodyText ?? ''}',
        ),
        'OK-ACCESS-TIMESTAMP': timestamp,
        'OK-ACCESS-PASSPHRASE': passphrase,
      });
    }

    final json = await _http.send(
      method,
      uri,
      headers: headers,
      body: bodyText,
    );
    return readEnvelope(json as Json);
  }

  Future<void> _login(ExchangeSocket socket) async {
    final (key, secret, passphrase) = _credentials();
    final timestamp = '${DateTime.now().millisecondsSinceEpoch ~/ 1000}';
    await socket.request({
      'op': 'login',
      'args': [
        {
          'apiKey': key,
          'passphrase': passphrase,
          'timestamp': timestamp,
          'sign': await sign(secret, '${timestamp}GET/users/self/verify'),
        },
      ],
    }, (m) => m['event'] == 'login');
    socket.send({
      'op': 'subscribe',
      'args': [
        {'channel': 'account'},
        {'channel': 'orders', 'instType': 'SPOT'},
      ],
    });
  }

  static Map<String, String> _orderRef(
    String symbol,
    String? orderId,
    String? clientOrderId,
  ) {
    checkOneId(orderId, clientOrderId);
    return {'instId': symbol, 'ordId': ?orderId, 'clOrdId': ?clientOrderId};
  }

  static (String, String)? _wsError(Json m) =>
      m['event'] == 'error' ? ('${m['code']}', '${m['msg']}') : null;
}

// --- signing and parsing, public for tests ---

final _hmac = Hmac.sha256();

/// Base64 HMAC-SHA256 of [prehash], as OKX signs REST and websocket logins.
Future<String> sign(String secret, String prehash) async {
  final mac = await _hmac.calculateMac(
    utf8.encode(prehash),
    secretKey: SecretKey(utf8.encode(secret)),
  );
  return base64.encode(mac.bytes);
}

/// The `data` of a `{code, msg, data}` envelope, or the refusal it carries.
///
/// A rejected order answers `code: "1"` with the real reason in the row's
/// `sCode`/`sMsg`, so that is preferred when present.
List<Object?> readEnvelope(Json json) {
  final data = json['data'] as List<Object?>? ?? const [];
  final row = data.isNotEmpty && data.first is Json
      ? data.first! as Json
      : null;
  final rowCode = row?['sCode'] as String?;
  if (json['code'] == '0' && (rowCode == null || rowCode == '0')) return data;
  final failed = rowCode != null && rowCode != '0';
  throw ExchangeException(
    'okx',
    failed ? row!.str('sMsg') : json.str('msg'),
    code: failed ? rowCode : json.str('code'),
  );
}

String bar(Timeframe timeframe) => switch (timeframe) {
  Timeframe.m1 => '1m',
  Timeframe.m5 => '5m',
  Timeframe.m15 => '15m',
  Timeframe.h1 => '1H',
  Timeframe.h4 => '4H',
  // plain `1D` opens at 16:00 UTC; the utc spellings are midnight-aligned
  Timeframe.d1 => '1Dutc',
  Timeframe.w1 => '1Wutc',
  Timeframe.mo1 => '1Mutc',
};

/// A candle row, REST or websocket: `[ts, o, h, l, c, vol, ..., confirm]`.
/// A period closes as a repeat of its own timestamp with confirm = "1".
Candle parseCandle(List<Object?> row, String symbol, Timeframe timeframe) =>
    Candle(
      symbol: symbol,
      timeframe: timeframe,
      openTime: fromMillis(row[0]),
      open: rowNum(row, 1),
      high: rowNum(row, 2),
      low: rowNum(row, 3),
      close: rowNum(row, 4),
      volume: rowNum(row, 5),
      closed: row[8] == '1',
    );

Instrument parseInstrument(Json i) => Instrument(
  symbol: i.str('instId'),
  base: i.str('baseCcy'),
  quote: i.str('quoteCcy'),
  tickSize: i.str('tickSz'),
  stepSize: i.str('lotSz'),
  minQuantity: i.str('minSz'),
  trading: i['state'] == 'live',
);

Order parseOrder(Json o) {
  String? orNull(String key) => o[key] == '' ? null : o[key] as String?;
  return Order(
    symbol: o.str('instId'),
    orderId: o.str('ordId'),
    clientOrderId: orNull('clOrdId'),
    side: o['side'] == 'buy' ? OrderSide.buy : OrderSide.sell,
    type: o['ordType'] == 'market' ? OrderType.market : OrderType.limit,
    status: switch (o['state']) {
      'live' => OrderStatus.open,
      'partially_filled' => OrderStatus.partiallyFilled,
      'filled' => OrderStatus.filled,
      'canceled' || 'mmp_canceled' => OrderStatus.cancelled,
      _ => OrderStatus.unknown,
    },
    price: orNull('px'),
    quantity: o.str('sz'),
    filledQuantity: o.str('accFillSz'),
    createdAt: fromMillis(o['cTime']),
  );
}
