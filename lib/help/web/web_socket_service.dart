import 'dart:convert';
import 'dart:io';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/help/source/source_engine.dart';

/// WebSocket服务 - 支持书籍搜索/书源调试/RSS调试
class WebSocketService {
  HttpServer? _server;
  final DatabaseService _db = DatabaseService();
  final BookSourceEngine _engine = BookSourceEngine();
  final Set<WebSocket> _clients = {};

  /// 启动WebSocket服务
  Future<void> start({int port = 1122}) async {
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      _server!.listen((HttpRequest request) {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          WebSocketTransformer.upgrade(request).then((socket) {
            _clients.add(socket);
            socket.listen(
              (data) => _handleMessage(socket, data),
              onDone: () => _clients.remove(socket),
              onError: (_) => _clients.remove(socket),
            );
          });
        } else {
          request.response.statusCode = HttpStatus.notFound;
          request.response.close();
        }
      });
    } catch (e) {
      // Port already in use or other error
    }
  }

  /// 停止WebSocket服务
  Future<void> stop() async {
    for (final client in _clients) {
      client.close();
    }
    _clients.clear();
    await _server?.close();
    _server = null;
  }

  /// 处理客户端消息
  void _handleMessage(WebSocket socket, dynamic data) {
    try {
      final message = jsonDecode(data.toString());
      final type = message['type'];
      switch (type) {
        case 'search':
          _handleSearch(socket, message);
          break;
        case 'source_debug':
          _handleSourceDebug(socket, message);
          break;
        case 'rss_debug':
          _handleRssDebug(socket, message);
          break;
        case 'ping':
          socket.add(jsonEncode({'type': 'pong', 'time': DateTime.now().millisecondsSinceEpoch}));
          break;
        default:
          socket.add(jsonEncode({'type': 'error', 'message': 'Unknown type: $type'}));
      }
    } catch (e) {
      socket.add(jsonEncode({'type': 'error', 'message': e.toString()}));
    }
  }

  /// 处理书籍搜索
  Future<void> _handleSearch(WebSocket socket, Map message) async {
    final keyword = message['keyword'] ?? '';
    final sourceUrl = message['sourceUrl'];
    try {
      if (sourceUrl != null) {
        final source = await _db.getSource(sourceUrl);
        if (source != null) {
          final results = await _engine.search(source, keyword);
          socket.add(jsonEncode({
            'type': 'search_result',
            'keyword': keyword,
            'source': sourceUrl,
            'results': results.map((r) => r.toJson()).toList(),
          }));
        }
      } else {
        final sources = await _db.getAllSources(enabled: true);
        for (final source in sources) {
          try {
            final results = await _engine.search(source, keyword);
            socket.add(jsonEncode({
              'type': 'search_result',
              'keyword': keyword,
              'source': source.bookSourceUrl,
              'results': results.map((r) => r.toJson()).toList(),
            }));
          } catch (_) {}
        }
        socket.add(jsonEncode({'type': 'search_complete', 'keyword': keyword}));
      }
    } catch (e) {
      socket.add(jsonEncode({'type': 'error', 'message': e.toString()}));
    }
  }

  /// 处理书源调试
  Future<void> _handleSourceDebug(WebSocket socket, Map message) async {
    final sourceUrl = message['sourceUrl'] ?? '';
    final debugType = message['debugType'] ?? 'search'; // search/detail/toc/content
    final keyword = message['keyword'] ?? '';
    final bookUrl = message['bookUrl'] ?? '';
    final chapterUrl = message['chapterUrl'] ?? '';
    try {
      final source = await _db.getSource(sourceUrl);
      if (source == null) {
        socket.add(jsonEncode({'type': 'error', 'message': '书源不存在'}));
        return;
      }
      switch (debugType) {
        case 'search':
          final results = await _engine.search(source, keyword);
          socket.add(jsonEncode({
            'type': 'source_debug_result',
            'debugType': 'search',
            'log': '搜索完成，找到${results.length}个结果',
            'results': results.map((r) => r.toJson()).toList(),
          }));
          break;
        case 'detail':
          final book = await _engine.getBookInfo(source, bookUrl);
          socket.add(jsonEncode({
            'type': 'source_debug_result',
            'debugType': 'detail',
            'log': '详情获取完成',
            'book': book?.toJson(),
          }));
          break;
        case 'toc':
          final chapters = await _engine.getToc(source, bookUrl);
          socket.add(jsonEncode({
            'type': 'source_debug_result',
            'debugType': 'toc',
            'log': '目录获取完成，共${chapters.length}章',
            'chapters': chapters.map((c) => c.toJson()).toList(),
          }));
          break;
        case 'content':
          final content = await _engine.getContent(source, chapterUrl);
          socket.add(jsonEncode({
            'type': 'source_debug_result',
            'debugType': 'content',
            'log': '正文获取完成，共${content?.length ?? 0}字',
            'content': content,
          }));
          break;
      }
    } catch (e) {
      socket.add(jsonEncode({'type': 'source_debug_result', 'debugType': debugType, 'log': '错误: $e', 'error': true}));
    }
  }

  /// 处理RSS调试
  Future<void> _handleRssDebug(WebSocket socket, Map message) async {
    final sourceUrl = message['sourceUrl'] ?? '';
    try {
      socket.add(jsonEncode({
        'type': 'rss_debug_result',
        'log': 'RSS调试功能',
        'sourceUrl': sourceUrl,
      }));
    } catch (e) {
      socket.add(jsonEncode({'type': 'error', 'message': e.toString()}));
    }
  }

  /// 广播消息给所有客户端
  void broadcast(Map<String, dynamic> message) {
    final data = jsonEncode(message);
    for (final client in _clients) {
      client.add(data);
    }
  }

  bool get isRunning => _server != null;
}
