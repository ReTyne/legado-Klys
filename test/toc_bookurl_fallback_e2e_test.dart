import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/help/source/source_engine.dart';
import 'package:legado_md3/help/source/js/legado_js_runtime.dart';

/// 回归「能搜到却无法获取目录、正文」。
///
/// 根因：详情页/阅读页把目录地址绑死在 noteUrl / getBookInfo 成功上，
/// 而 legado 约定是「目录地址 = noteUrl，为空回退 bookUrl」——绝大多数
/// 书源搜索结果给的 bookUrl 本身就是目录页地址，没有独立 ruleBookInfo。
///
/// 本测试用 data: URI 承载搜索/目录/正文三段罐头数据 + 纯 JSONPath 规则书源，
/// 零网络、零 JS 依赖地跑通「搜索 -> noteUrl 回退 bookUrl -> 目录 -> 正文」，
/// 并用源码契约锁住详情页/阅读页的兜底逻辑，防止回归。
String _data(Object obj) =>
    'data:;base64,${base64Encode(utf8.encode(jsonEncode(obj)))}';

String _read(String path) => File(path).readAsStringSync();

BookSource _source(String searchUrl) => BookSource.fromJson({
      'bookSourceUrl': 'https://example.test',
      'bookSourceName': '无详情规则测试源',
      'bookSourceGroup': '',
      'bookSourceType': 0,
      'enabled': true,
      'searchUrl': searchUrl,
      'ruleSearch': {
        'bookList': r'$.data',
        'name': r'$.name',
        'author': r'$.author',
        'bookUrl': r'$.url',
      },
      // 故意不配置 ruleBookInfo：搜索结果直接给目录页地址（最常见形态）。
      'ruleToc': {
        'chapterList': r'$.chapters',
        'chapterName': r'$.title',
        'chapterUrl': r'$.url',
      },
      'ruleContent': {'content': r'$.content'},
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final contentUrl = _data({'content': '第一章 正文内容，用于验证正文获取链路。' * 4});
  final tocUrl = _data({
    'chapters': [
      {'title': '第一章 初遇', 'url': contentUrl},
      {'title': '第二章 进阶', 'url': contentUrl},
    ]
  });
  final searchUrl = _data({
    'data': [
      {'name': '测试之书', 'author': '测试作者', 'url': tocUrl},
    ]
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // 迷你求值器即可：本用例规则全为纯 JSONPath，不依赖 WebView JS 引擎。
    JsRuntimeManager.instance.factoryOverride = (_) => MiniLegadoJs();
  });

  tearDown(() => JsRuntimeManager.instance.factoryOverride = null);

  test('无 ruleBookInfo / noteUrl 为空：用 bookUrl 兜底取目录与正文', () async {
    final engine = BookSourceEngine();
    final source = _source(searchUrl);
    expect(source.ruleBookInfo, anyOf(isNull, isEmpty),
        reason: '用例前提：书源没有独立的详情规则');

    // 1) 搜索
    final books = await engine.search(source, '测试');
    expect(books, isNotEmpty, reason: '搜索应命中');
    final sb = books.first;
    expect(sb.bookUrl, tocUrl, reason: '搜索结果书址应指向目录页');
    expect(sb.noteUrl, isNull, reason: '搜索结果不带 noteUrl（根因前提）');

    // 2) 详情页/阅读页修复后的目录地址决策：noteUrl 为空回退 bookUrl
    final String bookUrl = sb.bookUrl ?? '';
    final String noteUrl =
        (sb.noteUrl ?? '').isNotEmpty ? sb.noteUrl! : bookUrl;
    expect(noteUrl, tocUrl);

    // 3) 目录
    final chapters = await engine.getToc(source, noteUrl);
    expect(chapters.length, 2, reason: 'bookUrl 兜底应拿到完整目录');
    expect(chapters.first.title, '第一章 初遇');
    expect(chapters.first.url, contentUrl);

    // 4) 正文
    final content = await engine.getContent(source, chapters.first.url);
    expect(content, isNotNull, reason: '正文获取失败');
    expect(content, contains('第一章 正文内容'));
    expect(content!.length, greaterThan(20));
  });

  test('详情规则抛错返回 null 时，目录仍可用书址兜底获取', () async {
    final engine = BookSourceEngine();
    final source = _source(searchUrl);
    final books = await engine.search(source, '测试');
    final String bookUrl = books.first.bookUrl ?? '';

    // 畸形 JSON（以 { 开头但不完整）会让 getBookInfo 的 jsonDecode 抛异常
    // -> catch -> 返回 null。旧详情页据此直接放弃目录，修复后不受影响。
    final broken = _dataString('{"incomplete":');
    final info = await engine.getBookInfo(source, broken,
        presetName: '占位', presetAuthor: '占位');
    // 无论详情成功与否，兜底路径都必须能取到目录
    final chapters = await engine.getToc(source, bookUrl);
    expect(chapters, isNotEmpty,
        reason: '详情规则失败不应阻断目录（bookUrl 兜底）');
    // info 允许为 null 或回退 Book，但不得抛异常到这里
    expect(info, anyOf(isNull, isA<Object>()));
  });

  group('UI 兜底逻辑契约（防止回归）', () {
    test('详情页：bookUrl 兜底 + 详情可选 + 二次回退', () {
      final src = _read('lib/ui/book/detail/book_detail_screen.dart');
      expect(src, contains('bookUrl'));
      expect(src, contains(': bookUrl'), reason: 'noteUrl 为空应回退 bookUrl');
      expect(src, contains('getBookInfo'), reason: '详情仅作可选增强');
      expect(src, contains('bookUrl != noteUrl'),
          reason: '独立 tocUrl 取不到章节时应二次回退书址');
      expect(src, contains('widget.book.noteUrl = noteUrl'),
          reason: '最终目录地址应回写供阅读页复用');
    });

    test('阅读页：noteUrl 为空回退 bookUrl + 二次回退 + 无源提示', () {
      final src = _read('lib/ui/book/read/reading_screen.dart');
      expect(src, contains(': bookUrl'), reason: '阅读页补目录也要回退 bookUrl');
      expect(src, contains('bookUrl != noteUrl'));
      expect(src, contains('未找到匹配的书源'),
          reason: 'source 为空时不得再留空白页');
    });

    test('搜索页：结果为网格大封面（不再 50x70 小图）', () {
      final src = _read('lib/ui/book/search/search_screen.dart');
      expect(src, contains('GridView.builder'));
      expect(src, contains('crossAxisCount: 3'));
      expect(src.contains('width: 50,'), isFalse,
          reason: '不应再使用 50x70 的 ListTile 小封面');
    });
  });
}

/// data: URI 直接承载原始字符串（不经过 jsonEncode），用于构造畸形内容。
String _dataString(String raw) =>
    'data:;base64,${base64Encode(utf8.encode(raw))}';
