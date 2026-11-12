import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/help/source/source_engine.dart';
import 'package:legado_md3/help/source/js/legado_js_runtime.dart';

/// 「能拿到目录、正文却一直加载不出」的离线回归。
///
/// flutter_test 默认把 dart:io 的 HttpClient 拦成 400，无法走真实 http(s)。
/// 这里临时把 [HttpOverrides.global] 置空，让 Dio 的 `HttpClient()` 拿到真实
/// `_HttpClient`，再把所有请求打到 127.0.0.1 的本地罐头 [HttpServer]，
/// 全程零外网、可复现，覆盖 getToc + getContent 的完整链路。
class _Resp {
  final String body;
  final String contentType;
  const _Resp(this.body,
      {this.contentType = 'text/html; charset=utf-8'});
}

class _CannedHttp {
  final Map<String, _Resp> routes = {};
  final List<String> seen = [];
  HttpServer? _server;
  int get port => _server!.port;
  String get origin => 'http://127.0.0.1:$port';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((req) async {
      seen.add(req.uri.toString());
      final r = routes[req.uri.path];
      req.response.statusCode = r == null ? 404 : 200;
      req.response.headers
          .set('Content-Type', r == null ? 'text/plain' : r.contentType);
      req.response.write(r == null ? 'not found' : r.body);
      await req.response.close();
    });
  }

  Future<void> close() async {
    await _server?.close(force: true);
    _server = null;
  }
}

/// 记录引擎交给 JS 运行时的脚本；只有拿到「完整脚本」才产出正文。
/// 用于直接观察整块 `<js>` 是否被提前截断。
class _ScriptRecorderJs implements LegadoJs {
  final List<String> scripts = [];

  @override
  Future<void> loadSource(JsSource source) async {}

  @override
  Future<JsEvalResult> eval(JsEvalRequest req) async {
    scripts.add(req.script);
    if (req.script.contains('result = "第一章 正文已加载"')) {
      return JsEvalResult(value: '第一章 正文已加载');
    }
    // 截断/不完整的脚本 -> 返回 null（模拟真实 JS 引擎语法失败）
    return JsEvalResult(value: null);
  }

  @override
  Future<void> dispose() async {}
}

BookSource _source({
  required String origin,
  required Map<String, dynamic> ruleContent,
  Map<String, dynamic>? ruleToc,
}) =>
    BookSource.fromJson({
      'bookSourceUrl': origin,
      'bookSourceName': '正文回归测试源',
      'bookSourceGroup': '',
      'bookSourceType': 0,
      'enabled': true,
      if (ruleToc != null) 'ruleToc': ruleToc,
      'ruleContent': ruleContent,
    });

String _data(String raw) =>
    'data:;base64,${base64Encode(utf8.encode(raw))}';

/// 整块 <js> 正文规则，JS 字符串里含 `</js>` 字面量（聚合源打包 HTML 时常见）。
const String _wholeJsWithInnerClose = '<js>\n'
    'var tail = "段内</js>字面量";\n'
    'result = "第一章 正文已加载" + tail;\n'
    'result\n'
    '</js>';

/// 对照：同样的规则但不含内部 `</js>`。
const String _wholeJsClean = '<js>\n'
    'result = "第一章 正文已加载";\n'
    'result\n'
    '</js>';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _CannedHttp server;
  HttpOverrides? savedOverride;

  setUp(() async {
    await JsRuntimeManager.instance.disposeAll();
    JsRuntimeManager.instance.factoryOverride = (_) => MiniLegadoJs();
    SharedPreferences.setMockInitialValues({});
    savedOverride = HttpOverrides.current; // global 只有 setter，用 current 读
    HttpOverrides.global = null; // 摘掉 flutter_test 的 400 mock
    server = _CannedHttp();
    await server.start();
  });

  tearDown(() async {
    await server.close();
    HttpOverrides.global = savedOverride;
    JsRuntimeManager.instance.factoryOverride = null;
    await JsRuntimeManager.instance.disposeAll();
  });

  // ==================== (A) 普通书源：http(s) + 选择器 ====================
  group('A 普通书源（@css / JSONPath / 默认规则）', () {
    test('A1 getToc + getContent（@css 正文）能拿到正文', () async {
      server.routes['/toc.html'] = const _Resp(
          '<html><body><div id="list">'
          '<a href="/chapter/1.html">第一章 风雪夜归人</a>'
          '<a href="/chapter/2.html">第二章 长歌行</a>'
          '</div></body></html>');
      server.routes['/chapter/1.html'] = const _Resp(
          '<html><body><div id="content">'
          '<p>第一章 风雪夜归人</p><p>这是正文第一段内容。</p>'
          '<p>这是正文第二段内容。</p>'
          '</div><div id="ads">广告位</div></body></html>');

      final source = _source(
        origin: server.origin,
        ruleToc: {'chapterList': '@css:#list a'},
        ruleContent: {'content': '@css:#content'},
      );
      final engine = BookSourceEngine();

      final chapters =
          await engine.getToc(source, '${server.origin}/toc.html');
      expect(chapters.length, 2, reason: '目录应解析出 2 章');
      expect(chapters.first.url, '${server.origin}/chapter/1.html',
          reason: 'getToc 应把相对章节地址按目录页 _resolveUrl 成绝对地址');

      final content = await engine.getContent(source, chapters.first.url);
      expect(content, isNotNull,
          reason: '普通源正文加载不出（getContent 返回 null）');
      expect(content, contains('这是正文第一段内容'));
      expect(content, isNot(contains('广告位')),
          reason: '@css 选择器应只命中 #content，不该带上页面其它节点');
    });

    test(r'A2 getContent（JSONPath $.content）能拿到正文', () async {
      server.routes['/api/chapter.json'] = const _Resp(
          '{"code":0,"content":"<p>JSON 正文第一段</p><p>JSON 正文第二段</p>"}',
          contentType: 'application/json; charset=utf-8');
      final source = _source(
        origin: '${server.origin}/book', // 书源首页与章节 API 不同路径
        ruleContent: {'content': r'$.content'},
      );
      final content = await BookSourceEngine()
          .getContent(source, '${server.origin}/api/chapter.json');
      expect(content, isNotNull);
      expect(content, contains('JSON 正文第一段'));
    });

    test('A3 getContent（默认 id.x@html 规则）能拿到正文', () async {
      server.routes['/c.html'] = const _Resp(
          '<html><body><div id="content"><p>默认规则正文内容</p></div>'
          '</body></html>');
      final source = _source(
        origin: server.origin,
        ruleContent: {'content': 'id.content@html'},
      );
      final content = await BookSourceEngine()
          .getContent(source, '${server.origin}/c.html');
      expect(content, isNotNull);
      expect(content, contains('默认规则正文内容'));
    });

    test('A4 相对章节地址：正常链路按目录页解析绝对地址；'
        '但直接传相对地址会被拼到书源首页（baseUrl 误用）', () async {
      final home = '${server.origin}/home/';
      final toc = '${server.origin}/novel/42/';
      server.routes['/novel/42/'] = const _Resp(
          '<div id="list"><a href="1.html">第一章</a></div>');
      server.routes['/novel/42/1.html'] = const _Resp(
          '<div id="content">目录页相对章节的正文</div>');
      final source = _source(
        origin: home,
        ruleToc: {'chapterList': '@css:#list a'},
        ruleContent: {'content': '@css:#content'},
      );
      final engine = BookSourceEngine();

      final chapters = await engine.getToc(source, toc);
      expect(chapters.single.url, '${server.origin}/novel/42/1.html',
          reason: 'getToc 用 _resolveUrl(url, currentUrl=目录页) 转绝对，'
              '故正常阅读链路不受 baseUrl 影响');
      final ok = await engine.getContent(source, chapters.single.url);
      expect(ok, contains('目录页相对章节的正文'));
      expect(engine.lastRequestUrl, '${server.origin}/novel/42/1.html');

      // 换源 / 正文调试 / 外部导入等调用点若把「未解析的相对章节地址」直接
      // 交给 getContent，_fetch 的 baseUrl 却是 source.bookSourceUrl（书源
      // 首页）而非章节目录页 -> 请求 /home/1.html -> 404 -> 返回 null。
      final bad = await engine.getContent(source, '1.html');
      expect(bad, isNull);
      expect(server.seen.any((u) => u.contains('/home/1.html')), isTrue,
          reason: 'getContent 的 baseUrl 用了 source.bookSourceUrl，'
              '而不是 BookChapter.baseUrl（目录页）');
    });
  });

  // ==================== (B) 聚合源：整块 <js> ====================
  group('B 整块 <js> 正文规则 / result 注入', () {
    test('B1 整块 <js> 规则下 result 被正确注入为 _fetch 原文', () async {
      final source = _source(
        origin: 'https://agg1.test',
        // 用显式赋值（迷你求值器只认 result = ... 才覆盖 result）
        ruleContent: {'content': '<js>result = result + "｜JS已解析"</js>'},
      );
      const raw = 'RAW-BODY-中文';
      final content =
          await BookSourceEngine().getContent(source, _data(raw));
      expect(content, isNotNull);
      expect(content, contains(raw),
          reason: 'result 应是 _fetch 返回的原文（HTML / hex）');
      expect(content, contains('JS已解析'));
    });

    test('B3 对照：不含内部 </js> 的整块 <js> 规则可正常产出正文', () async {
      final recorder = _ScriptRecorderJs();
      JsRuntimeManager.instance.factoryOverride = (_) => recorder;
      final source = _source(
        origin: 'https://agg3.test',
        ruleContent: {'content': _wholeJsClean},
      );
      final content =
          await BookSourceEngine().getContent(source, _data('RAW'));
      expect(recorder.scripts.single,
          contains('result = "第一章 正文已加载"'));
      expect(content, contains('第一章 正文已加载'));
    });

    test('B2 修复：整块 <js> 内的 </js> 字面量不再截断脚本', () async {
      // 机械事实：贪婪正则会匹配到最后一个 </js>（真实闭合标签），
      // 而不是 JS 字符串里出现的第一个 </js>。
      final greedy = RegExp(r'^\s*<js>([\s\S]*)</js>');
      final lead = greedy.firstMatch(_wholeJsWithInnerClose)!;
      expect(lead.group(1)!, contains('result = "第一章 正文已加载"'),
          reason: '贪婪捕获应取到完整脚本，而不是在内部 </js> 处提前收尾');

      final recorder = _ScriptRecorderJs();
      JsRuntimeManager.instance.factoryOverride = (_) => recorder;
      final source = _source(
        origin: 'https://agg2.test',
        ruleContent: {'content': _wholeJsWithInnerClose},
      );
      final content =
          await BookSourceEngine().getContent(source, _data('RAW'));

      expect(recorder.scripts, isNotEmpty,
          reason: '应把 <js> 脚本交给 JS 运行时');
      final scriptComplete =
          recorder.scripts.first.contains('result = "第一章 正文已加载"');
      expect(scriptComplete, isTrue,
          reason: '修复后：_evalRuleContent 先判 _wholeJs（贪婪），'
              '整块 <js> 不再被 JS 内的 </js> 字面量截断');
      expect(content, contains('第一章 正文已加载'),
          reason: '脚本完整 -> JS 返回正文 -> getContent 拿到正文');
    });
  });

  // ==================== (D) 真机 WebView 求值策略（正文为空真凶） ====================
  group('D 真机 WebView 末尾表达式求值（hasReturn 误判回归）', () {
    test('D1 不再用正则 return 预判顶层 return，改用 eval 优先', () {
      final src = File('lib/help/source/js/parts/web_view_legado_js.dart')
          .readAsStringSync();
      // 旧实现用 hasReturn 正则 `(^|[\s;{}])return\s` 预判，嵌套函数里的
      // return 会被误判成「有顶层 return」，导致末尾裸表达式（如 `data;`）
      // 产出结果的正文脚本返回值丢失 -> 正文空。修复后：
      //   1. 删除 hasReturn 正则预判；
      //   2. 优先 eval（返回末尾表达式值）；
      //   3. 仅当 eval 报「illegal return」等解析期错误才回退为函数体执行。
      expect(src, isNot(contains('hasReturn')),
          reason: '不应再用 hasReturn 正则预判顶层 return');
      expect(src, contains('return eval(scriptArg)'),
          reason: '应优先用 eval 返回末尾表达式值');
      expect(src, contains('illegal return'),
          reason: '仅在 eval 报非法 return 时才回退为函数体');
      expect(src, contains('return statement outside'));
    });
  });

  // ==================== (C) 其余可疑失败点 ====================
  group('C 旁证：fromJson / _cleanHtml / 阅读页查源', () {
    test('C1 BookSource.fromJson 正确解析 ruleContent（Map 与 JSON 字符串）',
        () {
      final a = BookSource.fromJson({
        'bookSourceUrl': 'https://x.test',
        'bookSourceName': 'a',
        'ruleContent': {'content': '@css:#content'},
      });
      expect(a.ruleContent, isNotNull);
      expect(a.contentRule, '@css:#content');

      final b = BookSource.fromJson({
        'bookSourceUrl': 'https://y.test',
        'bookSourceName': 'b',
        'ruleContent': r'{"content":"$.content"}',
      });
      expect(b.ruleContent, isNotNull,
          reason: '落库后 ruleContent 是 JSON 字符串，fromJson/_parseRule 需还原');
      expect(b.contentRule, r'$.content');
    });

    test('C2 _cleanHtml 不会清空合法正文（剥离标签，保留文字）', () async {
      server.routes['/p.html'] = const _Resp(
          '<html><body><div id="content"><p>第一段正文。</p><br>'
          '<p>第二段正文。</p><script>var x=1;</script></div></body></html>');
      final source = _source(
        origin: server.origin,
        ruleContent: {'content': '@css:#content@html'},
      );
      final content = await BookSourceEngine()
          .getContent(source, '${server.origin}/p.html');
      expect(content, isNotNull);
      expect(content, contains('第一段正文'));
      expect(content, contains('第二段正文'));
      expect(content, isNot(contains('var x')));
    });

    test('C3 阅读页按 origin 查源；「未找到匹配的书源」是另一条分支', () {
      final src =
          File('lib/ui/book/read/reading_screen.dart').readAsStringSync();
      expect(src, contains('s.bookSourceUrl == widget.book.origin'));
      expect(src, contains('未找到匹配的书源'));
      expect(src, contains('正文规则未匹配到内容'));
      // 用户报告的是后者（content == null），说明 source 已找到、chapter.url
      // 非空，问题落在 getContent 内部，而不是阅读页的源查找分支。
    });
  });
}
