import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:dio/dio.dart' hide Response;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_chapter.dart';
import 'package:legado_md3/data/model/bookmark.dart';
import 'package:legado_md3/data/model/replace_rule.dart';
import 'package:legado_md3/data/model/rss_source.dart';
import 'package:legado_md3/help/source/source_engine.dart';
import 'package:legado_md3/help/storage/import_book_service.dart';
import '../../data/local/app_database.dart';

/// Web 远程控制服务（对齐 legado-E 的 HttpServer 路由）。
/// 说明：legado-E 的 /bookSourceDebug、/rssSourceDebug、/searchBook 走 WebSocket
/// 推送，本项目没有 web_socket_channel / shelf_web_socket 依赖，降级为
/// Server-Sent Events：GET /debug/stream + WebService.broadcastDebug()。
class WebService {
  final DatabaseService _db = DatabaseService();
  final BookSourceEngine _engine = BookSourceEngine();
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 20),
    followRedirects: true,
    validateStatus: (s) => s != null && s < 500,
  ));
  HttpServer? _server;
  int port = 1122;
  bool get isRunning => _server != null;

  /// 全局单例：磁贴/通知栏等系统入口与 UI 共享同一服务实例。
  static final WebService instance = WebService._internal();

  factory WebService() => instance;

  WebService._internal();

  /// SSE 调试日志广播流（broadcast，支持多个 /debug/stream 连接）
  static final StreamController<String> _debugController =
      StreamController<String>.broadcast();

  /// 推送一条调试日志到所有 SSE 连接。
  /// 未来由 source_debug_screen.dart 的调试回调接线调用。
  static void broadcastDebug(String message) {
    if (_debugController.isClosed) return;
    _debugController.add(message);
  }

  /// 最近若干条调试日志，便于新连接补齐上下文
  static final List<String> _debugHistory = <String>[];
  static const int _debugHistoryMax = 200;

  static void _pushDebug(String message) {
    if (_debugHistory.length >= _debugHistoryMax) {
      _debugHistory.removeAt(0);
    }
    _debugHistory.add(message);
    broadcastDebug(message);
  }

  /// 供外部（如书源调试页）调用的静态入口
  static void logDebug(String message) => _pushDebug(message);

  Future<void> start({int port = 1122}) async {
    if (_server != null) return;
    this.port = port;
    final router = Router();

    // ---- 实时调试推送（WebSocket 降级为 SSE），必须先于静态资源通配路由 ----
    router.get('/debug/stream', _debugStream);
    router.post('/debug/log', _debugLog);
    router.get('/debug/history', _debugHistoryApi);

    // 书源API
    router.get('/getBookSources', _getBookSources);
    router.get('/getBookSource', _getBookSource);
    router.post('/saveBookSource', _saveBookSource);
    router.post('/saveBookSources', _saveBookSources);
    router.post('/deleteBookSources', _deleteBookSources);
    router.post('/setBookSourceOrder', _setBookSourceOrder);

    // 书籍API
    router.get('/getBookshelf', _getBookshelf);
    router.get('/getChapterList', _getChapterList);
    router.get('/getBookContent', _getBookContent);
    router.get('/refreshToc', _refreshToc);
    router.post('/saveBook', _saveBook);
    router.post('/saveBookshelf', _saveBookshelf);
    router.post('/deleteBook', _deleteBook);
    router.post('/saveBookProgress', _saveBookProgress);
    router.get('/analyzeBookUrl', _analyzeBookUrl);

    // 搜索（legado-E 走 WebSocket，此处降级为 HTTP）
    router.get('/searchBook', _searchBook);
    router.post('/searchBook', _searchBook);
    router.get('/searchBookMulti', _searchBookMulti);
    router.post('/searchBookMulti', _searchBookMulti);

    // 书签
    router.get('/getBookmark', _getBookmark);
    router.post('/saveBookmark', _saveBookmark);

    // 本地书籍导入 / 下载
    router.post('/addLocalBook', _addLocalBook);
    router.post('/uploadBook', _addLocalBook);
    router.get('/downloadFile', _downloadFile);
    router.get('/ebookShare', _downloadFile);

    // 封面/图片
    router.get('/cover', _getCover);
    router.get('/image', _getImage);

    // 阅读配置
    router.get('/getReadConfig', _getReadConfig);
    router.post('/saveReadConfig', _saveReadConfig);

    // RSS API
    router.get('/getRssSources', _getRssSources);
    router.get('/getRssSource', _getRssSource);
    router.post('/saveRssSource', _saveRssSource);
    router.post('/saveRssSources', _saveRssSources);
    router.post('/deleteRssSources', _deleteRssSources);

    // 替换规则API
    router.get('/getReplaceRules', _getReplaceRules);
    router.post('/saveReplaceRule', _saveReplaceRule);
    router.post('/deleteReplaceRule', _deleteReplaceRule);
    router.post('/testReplaceRule', _testReplaceRule);

    // web-yuedu3 静态前端（Vue 构建产物，位于 assets/web）
    router.get('/', _serveIndex);
    router.get('/index.html', _serveIndex);
    router.get(r'/<asset|.*>', _serveAsset);

    final handler = const Pipeline()
        .addMiddleware(logRequests())
        .addMiddleware(_corsMiddleware())
        .addMiddleware(_authMiddleware())
        .addHandler(router.call);

    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  }

  /// 访问鉴权中间件：设置了 web_password 时，要求 ?key= 或 Authorization 头匹配
  Middleware _authMiddleware() {
    return (Handler inner) {
      return (Request request) async {
        String pwd = '';
        try {
          final p = await SharedPreferences.getInstance();
          pwd = p.getString('web_password') ?? '';
        } catch (_) {}
        if (pwd.isEmpty) return inner(request); // 未设置密码则放行
        final key = request.url.queryParameters['key'] ?? '';
        final auth = request.headers['authorization'] ?? '';
        final token = auth.startsWith('Bearer ')
            ? auth.substring(7)
            : auth.startsWith('Basic ')
                ? utf8.decode(base64.decode(auth.substring(6))).split(':').last
                : '';
        if (key == pwd || token == pwd) return inner(request);
        return Response.forbidden(jsonEncode({'error': '未授权，请提供正确的访问密码'}),
            headers: {'content-type': 'application/json; charset=utf-8'});
      };
    };
  }

  /// CORS 中间件：web 前端多从其它端口/域名访问，需支持预检与跨域头
  Middleware _corsMiddleware() {
    return (Handler inner) {
      return (Request request) async {
        final origin = request.headers['origin'] ?? '*';
        final cors = <String, String>{
          'Access-Control-Allow-Origin': origin,
          'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
          'Access-Control-Allow-Headers': 'content-type, authorization',
          'Access-Control-Allow-Credentials': 'true',
        };
        if (request.method == 'OPTIONS') {
          return Response.ok('', headers: cors);
        }
        final response = await inner(request);
        final merged = Map<String, Object>.from(response.headers);
        cors.forEach((k, v) {
          if (!merged.containsKey(k)) merged[k] = v;
        });
        return response.change(headers: merged);
      };
    };
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<String> get address async => 'http://${await _getLocalIP()}:$port';

  Future<String> _getLocalIP() async {
    try {
      for (final interface in await NetworkInterface.list()) {
        for (final addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return '127.0.0.1';
  }

  Response _jsonResponse(dynamic data, {int statusCode = 200}) {
    return Response(
      statusCode,
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode(data),
    );
  }

  /// legado-E ReturnData 结构：{isSuccess, errorMsg, data}
  Response _rd(dynamic data) =>
      _jsonResponse({'isSuccess': true, 'errorMsg': '', 'data': data});

  Response _rdError(String msg, {int statusCode = 200}) =>
      _jsonResponse({'isSuccess': false, 'errorMsg': msg, 'data': null},
          statusCode: statusCode);

  /// 依次尝试多个查询参数名，返回第一个非空值
  String _q(Request request, List<String> keys, [String def = '']) {
    for (final k in keys) {
      final v = request.url.queryParameters[k];
      if (v != null && v.isNotEmpty) return v;
    }
    return def;
  }

  Future<Map<String, dynamic>?> _jsonBody(Request request) async {
    try {
      final body = await request.readAsString();
      if (body.trim().isEmpty) return null;
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<List<dynamic>> _jsonListBody(Request request) async {
    try {
      final body = await request.readAsString();
      if (body.trim().isEmpty) return <dynamic>[];
      final decoded = jsonDecode(body);
      if (decoded is List) return decoded;
      if (decoded is Map<String, dynamic>) {
        final inner = decoded['data'] ?? decoded['sources'] ?? decoded['rules'];
        if (inner is List) return inner;
        return <dynamic>[decoded];
      }
      return <dynamic>[decoded];
    } catch (_) {
      return <dynamic>[];
    }
  }

  // === SSE 调试日志（WebSocket 降级） ===
  Response _debugStream(Request request) {
    late final StreamController<List<int>> ctl;
    Timer? heartbeat;
    StreamSubscription<String>? sub;
    ctl = StreamController<List<int>>(
      onListen: () {
        void send(String chunk) {
          if (!ctl.isClosed) ctl.add(utf8.encode(chunk));
        }

        send('retry: 3000\n\n');
        // 断线重连时补齐最近日志
        for (final m in _debugHistory) {
          send('data: ${_sseEncode(m)}\n\n');
        }
        send('data: ${_sseEncode('{"type":"connected"}\n')}\n\n');
        sub = _debugController.stream.listen((msg) {
          send('data: ${_sseEncode(msg)}\n\n');
        });
        heartbeat = Timer.periodic(const Duration(seconds: 15), (_) {
          send(': ping\n\n');
        });
      },
      onCancel: () {
        heartbeat?.cancel();
        sub?.cancel();
      },
    );
    return Response.ok(
      ctl.stream,
      headers: {
        'Content-Type': 'text/event-stream; charset=utf-8',
        'Cache-Control': 'no-cache, no-transform',
        'Connection': 'keep-alive',
        'X-Accel-Buffering': 'no',
      },
      context: {'shelf.io.buffer_output': false},
    );
  }

  /// SSE data 字段不能包含裸换行
  static String _sseEncode(String msg) =>
      msg.replaceAll('\r', ' ').replaceAll('\n', '\\n');

  Future<Response> _debugLog(Request request) async {
    final body = await request.readAsString();
    String msg = body;
    if (body.trim().startsWith('{')) {
      try {
        final m = jsonDecode(body);
        if (m is Map && m['msg'] != null) msg = m['msg'].toString();
        if (m is Map && m['message'] != null) msg = m['message'].toString();
      } catch (_) {}
    }
    final q = _q(request, ['msg', 'message']);
    if (q.isNotEmpty) msg = q;
    if (msg.trim().isEmpty) return _rdError('日志内容不能为空');
    _pushDebug(msg);
    return _rd('');
  }

  Response _debugHistoryApi(Request request) => _rd(_debugHistory.toList());

  // === 书源API ===
  Future<Response> _getBookSources(Request request) async {
    final sources = await _db.getAllSources();
    if (sources.isEmpty) return _rdError('设备源列表为空');
    return _rd(sources.map((s) => s.toJson()).toList());
  }

  Future<Response> _getBookSource(Request request) async {
    final url = _q(request, ['url', 'bookSourceUrl']);
    if (url.isEmpty) return _rdError('参数url不能为空，请指定源地址');
    final source = await _db.getSource(url);
    if (source == null) return _rdError('未找到源，请检查书源地址');
    return _rd(source.toJson());
  }

  Future<Response> _saveBookSource(Request request) async {
    final body = await request.readAsString();
    if (body.trim().isEmpty) return _rdError('数据不能为空');
    BookSource source;
    try {
      source = BookSource.fromJson(jsonDecode(body));
    } catch (_) {
      return _rdError('转换源失败');
    }
    if (source.bookSourceName.trim().isEmpty ||
        source.bookSourceUrl.trim().isEmpty) {
      return _rdError('源名称和URL不能为空');
    }
    final existing = await _db.getSource(source.bookSourceUrl);
    if (existing != null) {
      await _db.updateSource(source);
    } else {
      await _db.insertSource(source);
    }
    return _rd('');
  }

  Future<Response> _saveBookSources(Request request) async {
    final list = await _jsonListBody(request);
    if (list.isEmpty) return _rdError('转换源失败');
    final ok = <Map<String, dynamic>>[];
    for (final item in list) {
      if (item is! Map) continue;
      BookSource source;
      try {
        source = BookSource.fromJson(Map<String, dynamic>.from(item));
      } catch (_) {
        continue;
      }
      if (source.bookSourceName.trim().isEmpty ||
          source.bookSourceUrl.trim().isEmpty) {
        continue;
      }
      final existing = await _db.getSource(source.bookSourceUrl);
      if (existing != null) {
        await _db.updateSource(source);
      } else {
        await _db.insertSource(source);
      }
      ok.add(source.toJson());
    }
    return _rd(ok);
  }

  Future<Response> _deleteBookSources(Request request) async {
    final list = await _jsonListBody(request);
    if (list.isEmpty) return _rdError('没有传递数据');
    for (final item in list) {
      final url = item is String
          ? item
          : (item is Map
              ? (item['bookSourceUrl'] ?? item['url'] ?? '').toString()
              : '');
      if (url.isEmpty) continue;
      await _db.deleteSource(url);
    }
    return _rd('已执行');
  }

  /// 调整书源排序：body 为 [{bookSourceUrl, order}] 或 {url: order}
  Future<Response> _setBookSourceOrder(Request request) async {
    final list = await _jsonListBody(request);
    if (list.isEmpty) return _rdError('没有传递数据');
    int count = 0;
    for (final item in list) {
      if (item is Map) {
        final url = (item['bookSourceUrl'] ?? item['url'] ?? '').toString();
        final order = int.tryParse(
            (item['customOrder'] ?? item['order'] ?? '').toString());
        if (url.isEmpty || order == null) continue;
        final source = await _db.getSource(url);
        if (source == null) continue;
        source.customOrder = order;
        await _db.updateSource(source);
        count++;
      }
    }
    return _rd(count);
  }

  // === 书籍 API（web-yuedu3 契约：以书源书址 url 标识书籍） ===
  Future<Response> _getBookshelf(Request request) async {
    final books = await _db.getAllBooks();
    if (books.isEmpty) return _rdError('还没有添加小说');
    final data = books.map((b) {
      final j = b.toJson();
      // web-yuedu3 以 url 作为书籍唯一标识
      j['url'] = b.bookUrl ?? '';
      j['durChapterTitle'] = j['durChapterTitle'] ?? b.lastChapter ?? '';
      return j;
    }).toList();
    return _rd(data);
  }

  /// 按书址找到书架书籍（bookUrl 或 noteUrl 匹配）。
  Future<Book?> _findBookByUrl(String url) async {
    if (url.isEmpty) return null;
    final books = await _db.getAllBooks();
    for (final b in books) {
      if (b.bookUrl == url) return b;
    }
    for (final b in books) {
      if (b.noteUrl == url) return b;
    }
    return null;
  }

  /// 用书源重新抓取目录（本地书无书源时返回已有目录）
  Future<List<BookChapter>?> _fetchTocFromSource(Book book) async {
    final origin = book.origin;
    final tocUrl = book.noteUrl ?? book.bookUrl;
    if (origin == null || origin.isEmpty || tocUrl == null || tocUrl.isEmpty) {
      return null;
    }
    final source = await _db.getSource(origin);
    if (source == null) return null;
    final fresh = await _engine.getToc(source, tocUrl, bookInfo: {
      'bookUrl': book.bookUrl,
      'name': book.name,
      'author': book.author,
      'tocUrl': tocUrl,
      'durChapterIndex': book.durChapterIndex,
    }).timeout(const Duration(seconds: 30));
    if (fresh.isEmpty) return null;
    await _db.saveChapters(book.name, book.author, fresh);
    return fresh;
  }

  Future<Response> _getChapterList(Request request) async {
    final url = _q(request, ['url', 'bookUrl']);
    // 兼容旧的 name/author 入参
    final name = _q(request, ['name', 'bookName']);
    final author = _q(request, ['author', 'bookAuthor']);
    List<BookChapter> chapters;
    Book? book;
    if (url.isNotEmpty) {
      book = await _findBookByUrl(url);
      if (book == null) return _rdError('未在数据库找到对应书籍，请先添加');
      chapters = await _db.getChapters(book.name, book.author);
      // 本地无目录时，实时用书源抓取并缓存
      if (chapters.isEmpty) {
        chapters = await _fetchTocFromSource(book) ?? <BookChapter>[];
        if (chapters.isEmpty && book.local) {
          // 本地书：目录已随导入写入，仍为空则直接返回空列表
          return _rd(<dynamic>[]);
        }
      }
    } else if (name.isNotEmpty) {
      chapters = await _db.getChapters(name, author);
    } else {
      return _rdError('参数url不能为空，请指定书籍地址');
    }
    final data = chapters
        .map((c) => {'index': c.index, 'title': c.title, 'url': c.url})
        .toList();
    return _rd(data);
  }

  Future<Response> _getBookContent(Request request) async {
    final url = _q(request, ['url', 'bookUrl']);
    final indexRaw = _q(request, ['index']);
    if (url.isEmpty) return _rdError('参数url不能为空，请指定书籍地址');
    if (indexRaw.isEmpty) return _rdError('参数index不能为空, 请指定目录序号');
    final index = int.tryParse(indexRaw);
    if (index == null) return _rdError('参数index必须为数字');
    final name = _q(request, ['name', 'bookName']);
    final author = _q(request, ['author', 'bookAuthor']);

    Book? book;
    List<BookChapter> chapters;
    if (url.isNotEmpty) {
      book = await _findBookByUrl(url);
      if (book == null) return _rdError('未在数据库找到对应书籍，请先添加');
      chapters = await _db.getChapters(book.name, book.author);
      if (chapters.isEmpty) {
        chapters = await _fetchTocFromSource(book) ?? <BookChapter>[];
      }
    } else {
      chapters = await _db.getChapters(name, author);
    }
    if (index < 0 || index >= chapters.length) {
      return _rdError('未找到对应章节（共 ${chapters.length} 章）');
    }
    final chapter = chapters[index];
    var content = chapter.content ?? '';

    // 本地无正文时实时抓取并回写缓存
    if (content.trim().isEmpty &&
        book?.origin != null &&
        chapter.url.isNotEmpty) {
      final source = await _db.getSource(book!.origin!);
      if (source != null) {
        try {
          final live = await _engine
              .getContent(source, chapter.url,
                  bookInfo: {
                    'bookUrl': book.bookUrl,
                    'name': book.name,
                    'author': book.author,
                    'tocUrl': book.noteUrl,
                    'durChapterIndex': index,
                  },
                  chapter: {
                    'index': chapter.index,
                    'title': chapter.title,
                    'url': chapter.url,
                    'bookUrl': book.bookUrl,
                  })
              .timeout(const Duration(seconds: 30));
          if (live != null && live.trim().isNotEmpty) {
            content = live;
            await _db.updateChapterContent(
                book.name, book.author, index, content);
          }
        } catch (_) {}
      }
    }
    return _rd(content);
  }

  /// 强制刷新目录：清库后重新用书源抓取
  Future<Response> _refreshToc(Request request) async {
    final url = _q(request, ['url', 'bookUrl']);
    if (url.isEmpty) return _rdError('参数url不能为空，请指定书籍地址');
    final book = await _findBookByUrl(url);
    if (book == null) return _rdError('未在数据库找到对应书籍，请先添加');
    await _db.deleteChapters(book.name, book.author);
    final chapters = await _fetchTocFromSource(book);
    if (chapters == null || chapters.isEmpty) {
      return _rdError('未找到对应书源或目录为空');
    }
    return _rd(chapters
        .map((c) => {'index': c.index, 'title': c.title, 'url': c.url})
        .toList());
  }

  Future<Response> _saveBook(Request request) async {
    final data = await _jsonBody(request);
    if (data == null) return _rdError('格式不对');
    Book book;
    try {
      book = Book.fromJson(data);
    } catch (_) {
      return _rdError('格式不对');
    }
    if (book.name.isEmpty) return _rdError('书籍名称不能为空');
    final existing = await _db.getBook(book.name, book.author);
    if (existing != null) {
      await _db.updateBook(book);
    } else {
      await _db.insertBook(book);
    }
    return _rd('');
  }

  /// 批量保存书籍（web 端整柜同步），body 为 Book 数组
  Future<Response> _saveBookshelf(Request request) async {
    final list = await _jsonListBody(request);
    if (list.isEmpty) return _rdError('格式不对');
    int count = 0;
    for (final item in list) {
      if (item is! Map) continue;
      Book book;
      try {
        book = Book.fromJson(Map<String, dynamic>.from(item));
      } catch (_) {
        continue;
      }
      if (book.name.isEmpty) continue;
      final existing = await _db.getBook(book.name, book.author);
      if (existing != null) {
        await _db.updateBook(book);
      } else {
        await _db.insertBook(book);
      }
      count++;
    }
    return _rd(count);
  }

  Future<Response> _deleteBook(Request request) async {
    final data = await _jsonBody(request);
    if (data == null) return _rdError('格式不对');
    final name = (data['name'] ?? '').toString();
    final author = (data['author'] ?? '').toString();
    if (name.isEmpty) return _rdError('格式不对');
    await _db.deleteBook(name, author);
    return _rd('');
  }

  Future<Response> _saveBookProgress(Request request) async {
    final data = await _jsonBody(request);
    if (data == null) return _rdError('格式不对');
    final name = (data['name'] ?? '').toString();
    final author = (data['author'] ?? '').toString();
    if (name.isEmpty) return _rdError('格式不对');
    final existing = await _db.getBook(name, author);
    if (existing == null) return _rdError('未在书架找到该书籍');
    final index = int.tryParse(
            (data['durChapterIndex'] ?? data['chapterIndex'] ?? '0')
                .toString()) ??
        0;
    final pos =
        int.tryParse((data['durChapterPos'] ?? data['pagePos'] ?? '0')
            .toString()) ??
            0;
    final chapterTitle = (data['durChapterTitle'] ?? '').toString();
    await _db.updateReadPosition(
      name,
      author,
      index,
      pos,
      int.tryParse((data['durChapterTime'] ?? '').toString()) ??
          DateTime.now().millisecondsSinceEpoch,
    );
    final book = await _db.getBook(name, author);
    if (book != null) {
      if (chapterTitle.isNotEmpty) book.lastChapter = chapterTitle;
      await _db.updateBook(book);
    }
    return _rd('');
  }

  /// 分享链接解析成书：按 bookUrlPattern 匹配书源，抓取详情页信息
  Future<Response> _analyzeBookUrl(Request request) async {
    final url = _q(request, ['url', 'bookUrl']);
    if (url.isEmpty) return _rdError('参数url不能为空');
    final sources = await _db.getAllSources(enabled: true);
    for (final s in sources) {
      if (!_engine.matchBookUrl(s, url)) continue;
      final book = await _engine
          .getBookInfo(s, url)
          .timeout(const Duration(seconds: 30));
      if (book == null) continue;
      book.bookUrl = url;
      book.origin = s.bookSourceUrl;
      book.originName = s.bookSourceName;
      book.noteUrl = book.noteUrl ?? url;
      if (_q(request, ['save']) == '1') {
        final existing = await _db.getBook(book.name, book.author);
        if (existing != null) {
          await _db.updateBook(book);
        } else {
          await _db.insertBook(book);
        }
      }
      return _rd(book.toJson());
    }
    return _rdError('没有书源匹配该链接');
  }

  // === 搜索（legado-E 走 WebSocket /bookSourceDebug、/searchBook，此处降级 HTTP） ===
  Future<List<BookSource>> _targetSources(List<String> urls) async {
    final all = await _db.getAllSources(enabled: true);
    if (urls.isEmpty) return all;
    final wanted = urls.toSet();
    return all.where((s) => wanted.contains(s.bookSourceUrl)).toList();
  }

  Future<Response> _runSearch(String key, List<String> urls) async {
    if (key.isEmpty) return _rdError('参数key不能为空');
    final sources = await _targetSources(urls);
    if (sources.isEmpty) return _rdError('没有可用书源');
    final results = <Map<String, dynamic>>[];
    await Future.wait(sources.map((s) async {
      try {
        final books = await _engine
            .search(s, key)
            .timeout(const Duration(seconds: 30));
        for (final b in books) {
          final j = b.toJson();
          j['originName'] = s.bookSourceName;
          j['origin'] = s.bookSourceUrl;
          results.add(j);
        }
      } catch (_) {}
    }));
    return _rd(results);
  }

  /// 单源搜索：?key=&bookSourceUrl=（不带 bookSourceUrl 时搜索全部启用源）
  Future<Response> _searchBook(Request request) async {
    var key = _q(request, ['key', 'searchKey', 'q']);
    var urls = <String>[];
    if (key.isEmpty) {
      final data = await _jsonBody(request);
      if (data != null) {
        key = (data['key'] ?? data['searchKey'] ?? '').toString();
        final u = data['bookSourceUrl'] ?? data['url'];
        if (u is String && u.isNotEmpty) urls = [u];
      }
    }
    final single = _q(request, ['bookSourceUrl', 'url']);
    if (single.isNotEmpty) urls = [single];
    return _runSearch(key, urls);
  }

  /// 多源搜索：body {key, bookSourceUrls: [...]}；不指定源时搜索全部启用源
  Future<Response> _searchBookMulti(Request request) async {
    var key = _q(request, ['key', 'searchKey', 'q']);
    var urls = <String>[];
    if (key.isEmpty) {
      final data = await _jsonBody(request);
      if (data != null) {
        key = (data['key'] ?? data['searchKey'] ?? '').toString();
        final raw = data['bookSourceUrls'] ?? data['sources'];
        if (raw is List) {
          urls = raw.map((e) => e.toString()).toList();
        }
      }
    }
    return _runSearch(key, urls);
  }

  // === 书签 ===
  Future<Response> _getBookmark(Request request) async {
    final url = _q(request, ['url', 'bookUrl']);
    var name = _q(request, ['name', 'bookName']);
    var author = _q(request, ['author', 'bookAuthor']);
    if (url.isNotEmpty) {
      final book = await _findBookByUrl(url);
      if (book == null) return _rdError('未在数据库找到对应书籍');
      name = book.name;
      author = book.author;
    }
    final marks = name.isEmpty
        ? await _db.getBookmarks()
        : await _db.getBookmarks(name, author);
    return _rd(marks.map((m) => m.toMap()).toList());
  }

  Future<Response> _saveBookmark(Request request) async {
    final data = await _jsonBody(request);
    if (data == null) return _rdError('格式不对');
    final name = (data['bookName'] ?? data['name'] ?? '').toString();
    if (name.isEmpty) return _rdError('bookName 不能为空');
    final author = (data['bookAuthor'] ?? data['author'] ?? '').toString();
    final index = int.tryParse(
            (data['chapterIndex'] ?? data['durChapterIndex'] ?? '0')
                .toString()) ??
        0;
    final mark = Bookmark(
      bookName: name,
      bookAuthor: author,
      chapterIndex: index,
      chapterTitle: (data['chapterTitle'] ?? '').toString(),
      pageIndex:
          int.tryParse((data['pageIndex'] ?? '0').toString()) ?? 0,
      content: data['content']?.toString(),
    );
    await _db.insertBookmark(mark);
    return _rd('');
  }

  // === 本地书籍导入 / 下载 ===
  /// legado-E 用 multipart 上传（/addLocalBook），本项目无 shelf_multipart，
  /// 降级为：query 传 fileName，请求体为文件原始字节。
  Future<Response> _addLocalBook(Request request) async {
    var fileName = _q(request, ['fileName', 'name']);
    if (fileName.isEmpty) return _rdError('fileName 不能为空');
    // 防目录穿越，只保留文件名
    fileName = fileName.split('/').last.split('\\').last;
    final ext = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';
    if (!ImportBookService.supported.contains(ext)) {
      return _rdError('不支持的文件类型：$ext（支持 ${ImportBookService.supported.join('/')}）');
    }
    final bytes = await request
        .read()
        .expand((chunk) => chunk)
        .toList()
        .timeout(const Duration(minutes: 3));
    if (bytes.isEmpty) return _rdError('fileData 不能为空');
    try {
      final dir = await getTemporaryDirectory();
      final target = Directory(p.join(dir.path, 'web_upload'));
      if (!await target.exists()) await target.create(recursive: true);
      final file = File(p.join(target.path,
          '${DateTime.now().millisecondsSinceEpoch}_$fileName'));
      await file.writeAsBytes(bytes);
      final result = await ImportBookService().importPath(file.path);
      return _rd({
        'name': result.book.name,
        'author': result.book.author,
        'chapterCount': result.chapterCount,
        'path': file.path,
      });
    } catch (e) {
      return _rdError('保存书籍错误\n$e');
    }
  }

  /// 把本地书籍文件以流返回：?path= 文件路径，或 ?url= 书架书籍地址
  Future<Response> _downloadFile(Request request) async {
    final path = _q(request, ['path', 'file']);
    var target = path;
    if (target.isEmpty) {
      final url = _q(request, ['url', 'bookUrl']);
      if (url.isEmpty) return _rdError('参数 path 或 url 不能为空');
      final book = await _findBookByUrl(url);
      if (book == null) return _rdError('未在数据库找到对应书籍');
      target = book.bookUrl ?? book.noteUrl ?? '';
      if (target.startsWith('local://')) {
        target = target.substring('local://'.length);
      } else {
        return _rdError('该书籍不是本地书籍，无本地文件可下载');
      }
    }
    final file = await _safeLocalFile(target);
    if (file == null) return _rdError('文件不存在或不允许访问', statusCode: 404);
    final len = await file.length();
    final name = file.path.split('/').last;
    return Response.ok(
      file.openRead(),
      headers: {
        'Content-Type': _mime(name),
        'Content-Length': '$len',
        'Content-Disposition': 'attachment; filename="$name"',
      },
      context: {'shelf.io.buffer_output': false},
    );
  }

  /// 只允许访问应用私有目录内的文件，避免任意路径读取
  Future<File?> _safeLocalFile(String raw) async {
    try {
      final roots = <String>[
        (await getTemporaryDirectory()).path,
        (await getApplicationDocumentsDirectory()).path,
      ];
      try {
        final support = await getApplicationSupportDirectory();
        roots.add(support.path);
      } catch (_) {}
      final file = File(raw.contains('/') ? raw : p.join(roots.first, raw));
      final abs = p.normalize(file.absolute.path);
      for (final r in roots) {
        final root = p.normalize(Directory(r).absolute.path);
        if (abs == root || abs.startsWith('$root/')) {
          if (await File(abs).exists()) return File(abs);
          return null;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // === 封面/图片 ===
  /// legado-E 返回压缩后的 PNG bitmap；此处按 path/url 取真实字节返回，
  /// 取不到时再回退 302 到原图地址。
  Future<Response> _getCover(Request request) async {
    var path = _q(request, ['path', 'url', 'coverUrl']);
    if (path.isEmpty) {
      final book = await _db.getBook(
          _q(request, ['name', 'bookName']), _q(request, ['author']));
      path = book?.coverUrl ?? '';
    }
    if (path.isEmpty) return _rdError('封面地址为空');
    if (path.startsWith('http')) {
      final bytes = await _fetchBytes(path);
      if (bytes != null) {
        return Response.ok(bytes, headers: {'Content-Type': _mime(path)});
      }
      return Response(302, headers: {'Location': path});
    }
    final file = await _safeLocalFile(path);
    if (file != null) {
      return Response.ok(file.readAsBytesSync(),
          headers: {'Content-Type': _mime(file.path)});
    }
    return Response(302, headers: {'Location': path});
  }

  /// 正文图片：?url=书址&path=图片地址&width=宽度
  Future<Response> _getImage(Request request) async {
    final src = _q(request, ['path', 'src', 'url']);
    if (src.isEmpty) return _rdError('图片链接为空');
    if (!src.startsWith('http')) return _rdError('图片链接为空');
    final bytes = await _fetchBytes(src);
    if (bytes == null) return Response(302, headers: {'Location': src});
    return Response.ok(bytes, headers: {'Content-Type': _mime(src)});
  }

  Future<List<int>?> _fetchBytes(String url) async {
    try {
      final resp = await _dio.get<List<int>>(url,
          options: Options(responseType: ResponseType.bytes));
      final data = resp.data;
      if (data == null) return null;
      return data;
    } catch (_) {
      return null;
    }
  }

  // === 阅读配置（legado-E 存 CacheManager，此处落到 SharedPreferences） ===
  Future<Response> _getReadConfig(Request request) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('web_read_config');
    if (raw == null || raw.isEmpty) return _rdError('没有配置');
    return _rd(raw);
  }

  Future<Response> _saveReadConfig(Request request) async {
    final body = await request.readAsString();
    final prefs = await SharedPreferences.getInstance();
    if (body.trim().isEmpty) {
      await prefs.remove('web_read_config');
    } else {
      await prefs.setString('web_read_config', body);
    }
    return _rd('');
  }

  // === RSS API ===
  Future<Response> _getRssSources(Request request) async {
    final sources = await _db.getRssSources();
    if (sources.isEmpty) return _rdError('源列表为空');
    return _rd(sources.map((s) => _rssJson(s)).toList());
  }

  Map<String, dynamic> _rssJson(RssSource s) => {
        'id': s.id,
        'sourceName': s.sourceName,
        'sourceUrl': s.sourceUrl,
        'sourceIcon': s.sourceIcon,
        'sourceGroup': s.sourceGroup,
        'sourceComment': s.sourceComment,
        'enabled': s.enabled ?? true,
        'customOrder': s.customOrder,
      };

  Future<Response> _getRssSource(Request request) async {
    final url = _q(request, ['url', 'sourceUrl']);
    if (url.isEmpty) return _rdError('参数url不能为空，请指定源地址');
    final sources = await _db.getRssSources();
    for (final s in sources) {
      if (s.sourceUrl == url) return _rd(_rssJson(s));
    }
    return _rdError('未找到源，请检查源地址');
  }

  Future<Response> _saveRssSource(Request request) async {
    final data = await _jsonBody(request);
    if (data == null) return _rdError('数据不能为空');
    final name = (data['sourceName'] ?? data['name'] ?? '').toString();
    final url = (data['sourceUrl'] ?? data['url'] ?? '').toString();
    if (name.trim().isEmpty || url.trim().isEmpty) {
      return _rdError('源名称和URL不能为空');
    }
    final source = RssSource(
      sourceName: name,
      sourceUrl: url,
      sourceGroup: data['sourceGroup']?.toString() ?? data['group']?.toString(),
      sourceIcon: data['sourceIcon']?.toString(),
      sourceComment: data['sourceComment']?.toString(),
      enabled: data['enabled'] is bool
          ? data['enabled'] as bool
          : (data['enabled']?.toString() != 'false'),
      customOrder: int.tryParse((data['customOrder'] ?? '').toString()),
    );
    final existing = await _findRssSource(url);
    if (existing != null && existing.id != null) {
      source.id = existing.id;
      await _db.updateRssSource(source);
    } else {
      await _db.insertRssSource(source);
    }
    return _rd('');
  }

  Future<RssSource?> _findRssSource(String url) async {
    final sources = await _db.getRssSources();
    for (final s in sources) {
      if (s.sourceUrl == url) return s;
    }
    return null;
  }

  Future<Response> _saveRssSources(Request request) async {
    final list = await _jsonListBody(request);
    if (list.isEmpty) return _rdError('转换源失败');
    final ok = <Map<String, dynamic>>[];
    for (final item in list) {
      if (item is! Map) continue;
      final name = (item['sourceName'] ?? item['name'] ?? '').toString();
      final url = (item['sourceUrl'] ?? item['url'] ?? '').toString();
      if (name.trim().isEmpty || url.trim().isEmpty) continue;
      final source = RssSource(
        sourceName: name,
        sourceUrl: url,
        sourceGroup: item['sourceGroup']?.toString(),
        sourceIcon: item['sourceIcon']?.toString(),
        sourceComment: item['sourceComment']?.toString(),
        enabled: item['enabled'] is bool ? item['enabled'] as bool : true,
      );
      final existing = await _findRssSource(url);
      if (existing != null && existing.id != null) {
        source.id = existing.id;
        await _db.updateRssSource(source);
      } else {
        await _db.insertRssSource(source);
      }
      ok.add(_rssJson(source));
    }
    return _rd(ok);
  }

  Future<Response> _deleteRssSources(Request request) async {
    final list = await _jsonListBody(request);
    if (list.isEmpty) return _rdError('没有传递数据');
    for (final item in list) {
      if (item is num) {
        await _db.deleteRssSource(item.toInt());
        continue;
      }
      final url = item is String
          ? item
          : (item is Map
              ? (item['sourceUrl'] ?? item['url'] ?? '').toString()
              : '');
      if (url.isEmpty) continue;
      final s = await _findRssSource(url);
      if (s?.id != null) await _db.deleteRssSource(s!.id!);
    }
    return _rd('已执行');
  }

  // === 替换规则API ===
  Future<Response> _getReplaceRules(Request request) async {
    final rules = await _db.getReplaceRules();
    return _rd(rules.map((r) => _ruleJson(r)).toList());
  }

  Map<String, dynamic> _ruleJson(ReplaceRule r) => {
        'id': r.id,
        'replaceSummary': r.replaceSummary,
        'replaceRule': r.replaceRule,
        'replacement': r.replacement,
        'isRegex': r.isRegex,
        'isTitle': r.isTitle,
        'isContent': r.isContent,
        'enable': r.enable ?? true,
        'scope': r.scope,
        'order': r.order,
      };

  Future<Response> _saveReplaceRule(Request request) async {
    final data = await _jsonBody(request);
    if (data == null) return _rdError('数据不能为空');
    final rule = ReplaceRule.fromMap(_normalizeRuleMap(data));
    if (rule.replaceRule.isEmpty) return _rdError('替换规则不能为空');
    if (rule.id != null) {
      await _db.updateReplaceRule(rule);
    } else {
      await _db.insertReplaceRule(rule);
    }
    return _rd('');
  }

  /// legado-E 的 ReplaceRule 用 name/pattern/isEnabled/scopeTitle/scopeContent，
  /// 本项目用 replaceSummary/replaceRule/enable/isTitle/isContent，此处做字段归一。
  Map<String, dynamic> _normalizeRuleMap(Map raw) => <String, dynamic>{
        'id': _asInt(raw['id']),
        'replaceSummary':
            (raw['replaceSummary'] ?? raw['summary'] ?? raw['name'] ?? '')
                .toString(),
        'replaceRule': (raw['replaceRule'] ??
                raw['rule'] ??
                raw['pattern'] ??
                raw['regex'] ??
                '')
            .toString(),
        'replacement': (raw['replacement'] ?? raw['to'] ?? '').toString(),
        'enable': raw['enable'] ?? raw['isEnabled'] ?? raw['enabled'],
        'isRegex': raw['isRegex'],
        'isTitle': raw['isTitle'] ?? raw['scopeTitle'],
        'isContent': raw['isContent'] ?? raw['scopeContent'],
        'scope': raw['scope']?.toString(),
        'order_num': _asInt(raw['order_num'] ?? raw['order'] ?? raw['sortOrder']),
      };

  int? _asInt(dynamic v) =>
      v is int ? v : (v == null ? null : int.tryParse(v.toString()));

  Future<Response> _deleteReplaceRule(Request request) async {
    final data = await _jsonBody(request);
    if (data == null) return _rdError('数据不能为空');
    final id = data['id'] is int
        ? data['id'] as int
        : int.tryParse((data['id'] ?? '').toString());
    if (id == null) return _rdError('格式不对');
    await _db.deleteReplaceRule(id);
    return _rd('');
  }

  /// 测试替换规则：body { rule: ReplaceRule, text: String }
  Future<Response> _testReplaceRule(Request request) async {
    final data = await _jsonBody(request);
    if (data == null) return _rdError('数据不能为空');
    final rawRule = data['rule'] ?? data;
    ReplaceRule? rule;
    try {
      if (rawRule is String) {
        final decoded = jsonDecode(rawRule);
        if (decoded is Map) {
          rule = ReplaceRule.fromMap(_normalizeRuleMap(decoded));
        }
      } else if (rawRule is Map) {
        rule = ReplaceRule.fromMap(_normalizeRuleMap(rawRule));
      }
    } catch (_) {
      rule = null;
    }
    if (rule == null) return _rdError('格式不对');
    if (rule.replaceRule.isEmpty) return _rdError('替换规则不能为空');
    final text = (data['text'] ?? '').toString();
    String content;
    try {
      if (rule.isRegex) {
        content = text.replaceAll(
            RegExp(rule.replaceRule), rule.replacement);
      } else {
        content = text.replaceAll(rule.replaceRule, rule.replacement);
      }
    } catch (e) {
      content = '替换规则执行错误: $e';
    }
    return _rd(content);
  }

  // === web-yuedu3 静态前端 ===
  Future<Response> _serveIndex(Request request) => _serveAsset(request, 'index.html');

  Future<Response> _serveAsset(Request request, String asset) async {
    var path = asset;
    if (path.isEmpty) path = 'index.html';
    // 防目录穿越
    if (path.contains('..')) return Response.forbidden('forbidden');
    final key = 'assets/web/$path';
    try {
      final data = await rootBundle.load(key);
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      return Response.ok(bytes, headers: {
        'Content-Type': _mime(path),
        'Cache-Control': 'no-cache',
        'Access-Control-Allow-Origin': '*',
      });
    } catch (_) {
      // SPA 回退到 index.html（hash 路由下通常用不到）
      if (path != 'index.html') return _serveAsset(request, 'index.html');
      return Response.notFound('web assets not found');
    }
  }

  String _mime(String path) {
    final pth = path.toLowerCase();
    if (pth.endsWith('.html')) return 'text/html; charset=utf-8';
    if (pth.endsWith('.js')) return 'application/javascript; charset=utf-8';
    if (pth.endsWith('.css')) return 'text/css; charset=utf-8';
    if (pth.endsWith('.json')) return 'application/json; charset=utf-8';
    if (pth.endsWith('.png')) return 'image/png';
    if (pth.endsWith('.jpg') || pth.endsWith('.jpeg')) return 'image/jpeg';
    if (pth.endsWith('.gif')) return 'image/gif';
    if (pth.endsWith('.svg')) return 'image/svg+xml';
    if (pth.endsWith('.ico')) return 'image/x-icon';
    if (pth.endsWith('.woff')) return 'font/woff';
    if (pth.endsWith('.woff2')) return 'font/woff2';
    if (pth.endsWith('.ttf')) return 'font/ttf';
    if (pth.endsWith('.txt')) return 'text/plain; charset=utf-8';
    if (pth.endsWith('.epub')) return 'application/epub+zip';
    if (pth.endsWith('.pdf')) return 'application/pdf';
    return 'application/octet-stream';
  }
}
