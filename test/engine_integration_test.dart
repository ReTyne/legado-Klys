import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/help/source/source_engine.dart';

/// 直接调用 App 核心引擎 BookSourceEngine 的公开方法，验证"在软件里能用"。
/// 与 live_response_parse_test（只调 RulePipeline 零散方法 + 预抓 HTML）不同，
/// 这里走引擎完整链路：search() → _resolveUrlRule → _fetch →
/// _extractBookList → _toSearchBooks，返回 SearchBook 列表——即软件里真实执行的代码。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const fixtureDir = 'test/fixtures/community';
  BookSource loadSource(String id) {
    final d = jsonDecode(File('$fixtureDir/source_$id.json').readAsStringSync());
    final m = d is List ? d.first : d;
    return BookSource.fromJson((m as Map).cast<String, dynamic>());
  }

  group('BookSourceEngine 引擎完整链路（软件里真实执行的代码）', () {
    test('8123：引擎 search() 走 data URI 完整链路返回书目', () async {
      final src = loadSource('8123');
      // 把真实抓到的搜索页编码为 data URI 覆盖 searchUrl，
      // 让引擎走完整 search() 链路（含 _fetch 的 DATA 分支 + bookList/字段解析）。
      final html = File('$fixtureDir/real_responses/source_8123_search.html')
          .readAsStringSync();
      final dataUri =
          'data:text/html;base64,${base64.encode(utf8.encode(html))}';
      final patched = BookSource.fromJson(src.toJson()
        ..['searchUrl'] = dataUri);

      final engine = BookSourceEngine();
      final books = await engine.search(patched, '三体');

      expect(books, isNotEmpty,
          reason: '引擎 search() 应从真实搜索页解析出书目');
      expect(books.first.name, isNotNull);
      expect(books.first.name.trim().isNotEmpty, isTrue, reason: '书名非空');
      expect(books.first.bookUrl, isNotNull);
      expect(books.first.bookUrl!.trim().isNotEmpty, isTrue,
          reason: '详情链接非空');
      expect(engine.lastRequestUrl, contains('data:'),
          reason: '引擎 _fetch 应真实执行过');
    });

    test('8108：引擎 search() 完整链路解析真实搜索页', () async {
      final src = loadSource('8108');
      final html = File('$fixtureDir/real_responses/source_8108_search.html')
          .readAsStringSync();
      final dataUri =
          'data:text/html;base64,${base64.encode(utf8.encode(html))}';
      final patched = BookSource.fromJson(src.toJson()
        ..['searchUrl'] = dataUri);

      final books = await BookSourceEngine().search(patched, '三体');
      expect(books, isNotEmpty, reason: '引擎应解析出土豆搜索结果');
      expect(books.first.name.trim().isNotEmpty, isTrue);
    });

    test('引擎联网代码在工作：真实书源 search() 会发起真实 HTTP 请求', () async {
      // 沙箱测试 VM 的 Dart 客户端指纹会被部分站点 WAF 拦为 400，
      // 因此这里只验证"引擎确实构造并发起了对目标站点的请求"，不依赖站点返回成功。
      // 真机 App 使用原生网络栈，不受此测试环境限制。
      final engine = BookSourceEngine();
      await engine.search(loadSource('8123'), '三体');
      final log = engine.debugLog.join('\n');
      expect(log, contains('GET https://book.washai.net/book/bookclass.html'),
          reason: '引擎应真实发起对书源站点的搜索请求');
    });
  });
}
