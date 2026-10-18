import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_chapter.dart';
import 'package:legado_md3/data/model/replace_rule.dart';
import 'package:legado_md3/data/model/rss_source.dart';
import 'package:legado_md3/help/source/source_engine.dart';
import '../../data/local/app_database.dart';

class WebService {
  final DatabaseService _db = DatabaseService();
  final BookSourceEngine _engine = BookSourceEngine();
  HttpServer? _server;
  int port = 1122;
  bool get isRunning => _server != null;

  Future<void> start({int port = 1122}) async {
    if (_server != null) return;
    this.port = port;
    final router = Router();

    // 书源API
    router.get('/getBookSources', _getBookSources);
    router.get('/getBookSource', _getBookSource);
    router.post('/saveBookSource', _saveBookSource);
    router.post('/saveBookSources', _saveBookSources);
    router.post('/deleteBookSources', _deleteBookSources);

    // 书籍API
    router.get('/getBookshelf', _getBookshelf);
    router.get('/getChapterList', _getChapterList);
    router.get('/getBookContent', _getBookContent);
    router.get('/refreshToc', _refreshToc);
    router.post('/saveBook', _saveBook);
    router.post('/deleteBook', _deleteBook);
    router.post('/saveBookProgress', _saveBookProgress);

    // 封面/图片
    router.get('/cover', _getCover);
    router.get('/image', _getImage);

    // 阅读配置
    router.get('/getReadConfig', _getReadConfig);
    router.post('/saveReadConfig', _saveReadConfig);

    // RSS API
    router.get('/getRssSources', _getRssSources);
    router.post('/saveRssSource', _saveRssSource);
    router.post('/deleteRssSources', _deleteRssSources);

    // 替换规则API
    router.get('/getReplaceRules', _getReplaceRules);
    router.post('/saveReplaceRule', _saveReplaceRule);
    router.post('/deleteReplaceRule', _deleteReplaceRule);

    // web-yuedu3 静态前端（Vue 构建产物，位于 assets/web）
    router.get('/', _serveIndex);
    router.get('/index.html', _serveIndex);
    router.get(r'/<asset|.*>', _serveAsset);

    final handler = const Pipeline()
        .addMiddleware(logRequests())
        .addHandler(router);

    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
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

  // === 书源API ===
  Future<Response> _getBookSources(Request request) async {
    final sources = await _db.getAllSources();
    return _jsonResponse(sources.map((s) => s.toJson()).toList());
  }

  Future<Response> _getBookSource(Request request) async {
    final url = request.url.queryParameters['bookSourceUrl'] ?? '';
    final source = await _db.getSource(url);
    if (source == null) return _jsonResponse({'error': 'not found'}, statusCode: 404);
    return _jsonResponse(source.toJson());
  }

  Future<Response> _saveBookSource(Request request) async {
    final body = await request.readAsString();
    final source = BookSource.fromJson(jsonDecode(body));
    final existing = await _db.getSource(source.bookSourceUrl);
    if (existing != null) {
      await _db.updateSource(source);
    } else {
      await _db.insertSource(source);
    }
    return _jsonResponse({'success': true});
  }

  Future<Response> _saveBookSources(Request request) async {
    final body = await request.readAsString();
    final List<dynamic> list = jsonDecode(body);
    int count = 0;
    for (final item in list) {
      final source = BookSource.fromJson(item);
      final existing = await _db.getSource(source.bookSourceUrl);
      if (existing != null) {
        await _db.updateSource(source);
      } else {
        await _db.insertSource(source);
      }
      count++;
    }
    return _jsonResponse({'success': true, 'count': count});
  }

  Future<Response> _deleteBookSources(Request request) async {
    final body = await request.readAsString();
    final List<dynamic> urls = jsonDecode(body);
    for (final url in urls) {
      await _db.deleteSource(url.toString());
    }
    return _jsonResponse({'success': true});
  }

  // === 书籍 API（web-yuedu3 契约：以书源书址 url 标识书籍） ===
  Future<Response> _getBookshelf(Request request) async {
    final books = await _db.getAllBooks();
    final data = books.map((b) {
      final j = b.toJson();
      // web-yuedu3 以 url 作为书籍唯一标识
      j['url'] = b.bookUrl ?? '';
      j['durChapterTitle'] = j['durChapterTitle'] ?? b.lastChapter ?? '';
      return j;
    }).toList();
    return _jsonResponse({'isSuccess': true, 'data': data});
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

  Future<Response> _getChapterList(Request request) async {
    final url = request.url.queryParameters['url'] ??
        request.url.queryParameters['bookUrl'] ??
        '';
    // 兼容旧的 name/author 入参
    final name = request.url.queryParameters['name'] ?? '';
    final author = request.url.queryParameters['author'] ?? '';
    List<BookChapter> chapters;
    Book? book;
    if (url.isNotEmpty) {
      book = await _findBookByUrl(url);
      if (book == null) {
        return _jsonResponse({'isSuccess': false, 'data': <dynamic>[]});
      }
      chapters = await _db.getChapters(book.name, book.author);
      // 本地无目录时，实时用书源抓取并缓存
      if (chapters.isEmpty && book.origin != null && book.noteUrl != null) {
        final source = await _db.getSource(book.origin!);
        if (source != null) {
          try {
            final fresh = await _engine
                .getToc(source, book.noteUrl!, bookInfo: {
              'bookUrl': book.bookUrl,
              'name': book.name,
              'author': book.author,
              'tocUrl': book.noteUrl,
              'durChapterIndex': book.durChapterIndex,
            }).timeout(const Duration(seconds: 25));
            if (fresh.isNotEmpty) {
              chapters = fresh;
              await _db.saveChapters(book.name, book.author, chapters);
            }
          } catch (_) {}
        }
      }
    } else {
      chapters = await _db.getChapters(name, author);
    }
    final data = chapters
        .map((c) => {'index': c.index, 'title': c.title, 'url': c.url})
        .toList();
    return _jsonResponse({'isSuccess': true, 'data': data});
  }

  Future<Response> _getBookContent(Request request) async {
    final url = request.url.queryParameters['url'] ??
        request.url.queryParameters['bookUrl'] ??
        '';
    final index = int.tryParse(request.url.queryParameters['index'] ?? '0') ?? 0;
    final name = request.url.queryParameters['name'] ?? '';
    final author = request.url.queryParameters['author'] ?? '';

    Book? book;
    List<BookChapter> chapters;
    if (url.isNotEmpty) {
      book = await _findBookByUrl(url);
      if (book == null) {
        return _jsonResponse({'isSuccess': false, 'data': ''}, statusCode: 404);
      }
      chapters = await _db.getChapters(book.name, book.author);
    } else {
      chapters = await _db.getChapters(name, author);
    }
    if (index < 0 || index >= chapters.length) {
      return _jsonResponse({'isSuccess': false, 'data': ''}, statusCode: 404);
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
              .timeout(const Duration(seconds: 25));
          if (live != null && live.trim().isNotEmpty) {
            content = live;
            await _db.updateChapterContent(book.name, book.author, index, content);
          }
        } catch (_) {}
      }
    }
    return _jsonResponse({'isSuccess': true, 'data': content});
  }

  Future<Response> _refreshToc(Request request) async {
    return _jsonResponse({'success': true, 'message': 'refresh requested'});
  }

  Future<Response> _saveBook(Request request) async {
    final body = await request.readAsString();
    final book = Book.fromJson(jsonDecode(body));
    final existing = await _db.getBook(book.name, book.author);
    if (existing != null) {
      await _db.updateBook(book);
    } else {
      await _db.insertBook(book);
    }
    return _jsonResponse({'success': true});
  }

  Future<Response> _deleteBook(Request request) async {
    final body = await request.readAsString();
    final data = jsonDecode(body);
    await _db.deleteBook(data['name'], data['author']);
    return _jsonResponse({'success': true});
  }

  Future<Response> _saveBookProgress(Request request) async {
    final body = await request.readAsString();
    final data = jsonDecode(body);
    await _db.updateReadPosition(
      data['name'],
      data['author'],
      data['chapterIndex'] ?? 0,
      data['pagePos'] ?? 0,
      DateTime.now().millisecondsSinceEpoch,
    );
    return _jsonResponse({'success': true});
  }

  // === 封面/图片 ===
  Future<Response> _getCover(Request request) async {
    final name = request.url.queryParameters['name'] ?? '';
    final author = request.url.queryParameters['author'] ?? '';
    final book = await _db.getBook(name, author);
    if (book?.coverUrl == null) return _jsonResponse({'error': 'no cover'}, statusCode: 404);
    return Response(302, headers: {'Location': book!.coverUrl!});
  }

  Future<Response> _getImage(Request request) async {
    final url = request.url.queryParameters['url'] ?? '';
    if (url.isEmpty) return _jsonResponse({'error': 'no url'}, statusCode: 400);
    return Response(302, headers: {'Location': url});
  }

  // === 阅读配置 ===
  Future<Response> _getReadConfig(Request request) async {
    return _jsonResponse({
      'textSize': 20,
      'bgColor': 0xFFFFF8E1,
      'textColor': 0xFF333333,
      'pageAnim': 0,
    });
  }

  Future<Response> _saveReadConfig(Request request) async {
    return _jsonResponse({'success': true});
  }

  // === RSS API ===
  Future<Response> _getRssSources(Request request) async {
    final sources = await _db.getRssSources();
    return _jsonResponse(sources.map((s) => {'name': s.name, 'url': s.url, 'group': s.group, 'enabled': s.enabled}).toList());
  }

  Future<Response> _saveRssSource(Request request) async {
    final body = await request.readAsString();
    final data = jsonDecode(body); final source = RssSource(sourceName: data['name'] ?? '', sourceUrl: data['url'] ?? '', sourceGroup: data['group'], enabled: data['enabled'] ?? true);
    await _db.insertRssSource(source);
    return _jsonResponse({'success': true});
  }

  Future<Response> _deleteRssSources(Request request) async {
    final body = await request.readAsString();
    final List<dynamic> ids = jsonDecode(body);
    for (final id in ids) {
      await _db.deleteRssSource(id);
    }
    return _jsonResponse({'success': true});
  }

  // === 替换规则API ===
  Future<Response> _getReplaceRules(Request request) async {
    final rules = await _db.getReplaceRules();
    return _jsonResponse(rules.map((r) => {'id': r.id, 'replaceSummary': r.replaceSummary, 'replaceRule': r.replaceRule, 'replacement': r.replacement, 'enable': r.enable}).toList());
  }

  Future<Response> _saveReplaceRule(Request request) async {
    final body = await request.readAsString();
    final data = jsonDecode(body); final rule = ReplaceRule(id: data['id'], replaceSummary: data['replaceSummary'] ?? '', replaceRule: data['replaceRule'] ?? '', replacement: data['replacement'] ?? '', enable: data['enable'] ?? true);
    if (rule.id != null) {
      await _db.updateReplaceRule(rule);
    } else {
      await _db.insertReplaceRule(rule);
    }
    return _jsonResponse({'success': true});
  }

  Future<Response> _deleteReplaceRule(Request request) async {
    final body = await request.readAsString();
    final data = jsonDecode(body);
    await _db.deleteReplaceRule(data['id']);
    return _jsonResponse({'success': true});
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
    final p = path.toLowerCase();
    if (p.endsWith('.html')) return 'text/html; charset=utf-8';
    if (p.endsWith('.js')) return 'application/javascript; charset=utf-8';
    if (p.endsWith('.css')) return 'text/css; charset=utf-8';
    if (p.endsWith('.json')) return 'application/json; charset=utf-8';
    if (p.endsWith('.png')) return 'image/png';
    if (p.endsWith('.jpg') || p.endsWith('.jpeg')) return 'image/jpeg';
    if (p.endsWith('.gif')) return 'image/gif';
    if (p.endsWith('.svg')) return 'image/svg+xml';
    if (p.endsWith('.ico')) return 'image/x-icon';
    if (p.endsWith('.woff')) return 'font/woff';
    if (p.endsWith('.woff2')) return 'font/woff2';
    if (p.endsWith('.ttf')) return 'font/ttf';
    if (p.endsWith('.txt')) return 'text/plain; charset=utf-8';
    return 'application/octet-stream';
  }
}
