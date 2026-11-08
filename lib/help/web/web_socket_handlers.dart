import 'dart:async';
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// WebSocket 端点（对齐 Sigma `WebSocketServer.kt:11-22` 的 handshake.uri 分派）。
enum WsEndpoint { bookSourceDebug, rssSourceDebug, searchBook }

/// 一条客户端消息触发的真实动作。
///
/// [endpoint] 命中的端点；[message] 为已解析的 JSON 对象；[send] 向该连接
/// 回推一条文本帧（对应 Sigma 三个 socket 的 `send(...)` / `printLog`）；
/// [close] 以 NormalClosure(1000) 结束连接（对应 `close(..., "调试结束")`
/// 与 `close(normalClosure, SEARCH_FINISH, false)`）。
typedef WsMessageHandler = Future<void> Function(
  WsEndpoint endpoint,
  Map<String, dynamic> message,
  void Function(String text) send,
  void Function(String reason) close,
);

/// 3 个真正的 WebSocket 端点承载器。
///
/// 与降级用的 SSE 不同，这里走标准 RFC6455 升级：
/// * [pingInterval] = 30s 协议级 ping 保活，对齐
///   `BookSourceDebugWebSocket/RssSourceDebugWebSocket/BookSearchWebSocket`
///   的 `onOpen() { while(isOpen) { ping("ping"); delay(30000) } }`；
/// * 书源/RSS 调试端点订阅全局调试日志广播，逐条回推（对齐 `printLog`）；
/// * `/searchBook` 由 [onMessage] 逐批推送搜索结果、结束态关闭连接。
///
/// 注意：shelf 的 `request.hijack` 通过**同步抛出** `HijackException` 接管
/// socket，因此 [dispatch] 必须在任何含 `await`/`async` 的中间件之外被同步
/// 调用（见 `WebService.start` 里的 rootHandler 短路）。
class WebSocketHandlers {
  WebSocketHandlers({
    required Stream<String> debugStream,
    required WsMessageHandler onMessage,
  })  : _debugStream = debugStream,
        _onMessage = onMessage;

  final Stream<String> _debugStream;
  final WsMessageHandler _onMessage;

  /// 协议级 ping 间隔，对齐 Sigma 三个 socket 的 `delay(30000)`。
  static const Duration pingInterval = Duration(seconds: 30);

  /// 标准正常关闭码（NanoWSD `CloseCode.NormalClosure`）。
  static const int normalClosure = 1000;

  /// 对齐 `WebSocketServer.openWebSocket` 的 `when (handshake.uri)`。
  static const Map<String, WsEndpoint> routes = {
    '/bookSourceDebug': WsEndpoint.bookSourceDebug,
    '/rssSourceDebug': WsEndpoint.rssSourceDebug,
    '/searchBook': WsEndpoint.searchBook,
  };

  /// 粗判是否为本服务承载的升级请求；完整的握手校验由
  /// `webSocketHandler` 内部完成（版本/Key/Upgrade 头），校验失败会返回
  /// 400/404 普通响应而不会 hijack，安全。
  bool shouldHandle(Request request) {
    if (request.method != 'GET') return false;
    if (request.headers['Upgrade']?.toLowerCase() != 'websocket') return false;
    final connection = request.headers['Connection']?.toLowerCase() ?? '';
    if (!connection.split(',').map((e) => e.trim()).contains('upgrade')) {
      return false;
    }
    return routes.containsKey(_pathOf(request));
  }

  /// 原始请求 URI 的 path 一定带前导 '/'，去掉可能的尾斜杠后与契约表匹配。
  static String _pathOf(Request request) {
    final p = request.requestedUri.path;
    return p.length > 1 && p.endsWith('/') ? p.substring(0, p.length - 1) : p;
  }

  /// 按路径分派；未命中返回 null（调用方应回落到普通 HTTP router）。
  /// 返回类型用 [FutureOr] 与 shelf 的 [Handler] typedef 保持一致；实际
  /// `WebSocketHandler.handle` 为同步函数，hijack 仍会同步抛出完成升级。
  FutureOr<Response>? dispatch(Request request) {
    final endpoint = routes[_pathOf(request)];
    if (endpoint == null) return null;
    return _handlerFor(endpoint)(request);
  }

  Handler _handlerFor(WsEndpoint endpoint) => webSocketHandler(
        (WebSocketChannel channel, String? protocol) =>
            _onConnection(endpoint, channel),
        pingInterval: pingInterval,
      );

  void _onConnection(WsEndpoint endpoint, WebSocketChannel channel) {
    StreamSubscription<String>? debugSub;
    var closed = false;

    void send(String text) {
      if (closed) return;
      try {
        channel.sink.add(text);
      } catch (_) {}
    }

    void close(String reason) {
      if (closed) return;
      closed = true;
      try {
        // 忽略 close() 返回的 Future（连接关闭不需要等待）。
        unawaited(channel.sink.close(normalClosure, reason));
      } catch (_) {}
      final sub = debugSub;
      debugSub = null;
      if (sub != null) unawaited(sub.cancel());
    }

    // 调试类端点订阅全局调试日志广播：WebService.logDebug / 书源调试过程
    // 的每条日志都会实时回推到该连接（对齐 printLog 的 state 分级之外部分）。
    if (endpoint != WsEndpoint.searchBook) {
      debugSub = _debugStream.listen(send, onError: (Object _) {});
    }

    channel.stream.listen(
      (dynamic raw) {
        final String text;
        if (raw is String) {
          text = raw;
        } else if (raw is List<int>) {
          text = utf8.decode(raw);
        } else {
          text = raw.toString();
        }
        // 兼容旧前端的应用层心跳；协议级 ping 由 pingInterval 负责。
        if (text == 'ping') {
          send('pong');
          return;
        }
        Map<String, dynamic> message;
        try {
          final decoded = jsonDecode(text);
          if (decoded is! Map) {
            send('数据必须为Json格式');
            close('调试结束');
            return;
          }
          message = Map<String, dynamic>.from(decoded);
        } catch (_) {
          send('数据必须为Json格式');
          close('调试结束');
          return;
        }
        // 异步触发真实动作（搜索/调试），不阻塞消息循环。
        unawaited(_onMessage(endpoint, message, send, close));
      },
      onError: (Object _) => close('调试结束'),
      onDone: () => close('调试结束'),
    );
  }
}
