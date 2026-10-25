import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/data/model/explore_kind.dart';
import 'package:legado_md3/help/source/js/legado_js_runtime.dart';
import 'package:legado_md3/help/source/source_engine.dart';

/// 针对 7814（📚书山聚合）与 7632（🍅大灰狼聚合 vip 完全版）回归的伪运行时。
///
/// 覆盖两条曾断裂的链路：
/// * 7814：`<js>` 型 searchUrl 产出带 `{{encodeURIComponent(key)}}` 的 URL，
///   需经 legado replaceKeyPageJs 语义把 `{{}}` 按内联 JS 求值；
/// * 7632：`ruleSearch.checkKeyWord` 仅作调试推荐词（不得当输入正则）。
class _FakeJs implements LegadoJs {
  /// 记录每次求值：(script, key, infoMap)
  final List<({String script, String? key, Map<String, String>? infoMap})> calls = [];

  /// exploreKinds 的 `<js>` 求值结果（可被用例改写）
  String exploreKindsResult = _kindsJson;

  /// 置 true 时 exploreKinds 求值返回 error（模拟书源 JS 抛错）
  bool failExploreKinds = false;

  @override
  Future<void> loadSource(JsSource source) async {}

  @override
  Future<JsEvalResult> eval(JsEvalRequest req) async {
    calls.add((script: req.script.trim(), key: req.key, infoMap: req.infoMap));
    final s = req.script.trim();
    // 7814 URL 模板里的内联表达式：忠实求值（对齐浏览器 encodeURIComponent）
    if (s == 'encodeURIComponent(key)') {
      return JsEvalResult(value: Uri.encodeComponent(req.key ?? ''));
    }
    if (s == 'page') {
      return JsEvalResult(value: (req.page ?? 1).toString());
    }
    // 7814 `<js>` searchUrl：产出「带 {{}} 占位的 URL」（书山聚合真实形态），
    // 这里用 data: 载体把罐头响应带回，避免测试网络依赖。
    if (s.contains('qsearch')) {
      return JsEvalResult(value: 'data:;base64,{{b64payload(key)}}');
    }
    if (s == 'b64payload(key)') {
      return JsEvalResult(
          value: base64Encode(utf8.encode(jsonEncode({
                'code': 0,
                'data': [
                  {
                    'book_name': '斗破苍穹',
                    'book_id': '7814',
                    'author': '天蚕土豆',
                    'thumb_url': 'https://x/cover.jpg',
                    'abstract': '三十年河东',
                    'status': '完结',
                    'score': '9.2',
                    'tags': '玄幻',
                    'last_chapter_update_time': '2024-01-01',
                    'source': '全部',
                    'last_chapter_title': '第1000章',
                    'word_number': '500万字',
                  }
                ]
              }))));
    }
    // 显式失败（模拟书源 JS 抛错）：error 非空时引擎记 [JS异常] 并按空值处理
    if (s == 'throwErr') {
      return JsEvalResult(error: 'ReferenceError: xx is not defined');
    }
    // 发现分类：JSON 数组（url/text/button/toggle/select 五种控件）
    if (s.contains('exploreKinds')) {
      if (failExploreKinds) {
        return JsEvalResult(error: 'ReferenceError: xx is not defined');
      }
      return JsEvalResult(value: exploreKindsResult);
    }
    // 控件 viewName 动态求值
    if (s.contains('viewName')) {
      return JsEvalResult(value: '动态按钮文字');
    }
    // 控件动作（text 防抖/button/toggle/select 触发）：无返回值
    if (s.contains('onText') || s.contains('onButton') ||
        s.contains('onToggle') || s.contains('onSelect')) {
      return JsEvalResult(value: null);
    }
    // 7814 intro 前缀内的 {{"\n"+"​"}}：忠实求值（换行 + 零宽空格）
    if (s == '"\\n"+"\u200b"') {
      return JsEvalResult(value: '\n\u200b');
    }
    // 7814 intro 尾部 <js>（简化形态）：脚本内的 {{}} 必须已被引擎预先替换
    // （对齐 legado makeUpRule 对 JS 段同样替换）。
    // 忠实模拟 `result.indexOf(s) >= 0 && d.length > 0 ? "校验通过:"+s+"/"+d : "校验失败"`
    if (s.contains('const s =')) {
      final sv = RegExp(r'const s = "([^"]*)"').firstMatch(s)?.group(1) ?? '';
      final dv = RegExp(r'const d = "([^"]*)"').firstMatch(s)?.group(1) ?? '';
      final r = req.result?.toString() ?? '';
      return JsEvalResult(
          value: r.contains(sv) && dv.isNotEmpty ? '校验通过:$sv/$dv' : '校验失败');
    }
    // 7814 downloadUrls 尾部 @js（经 intro 字段承载）：忠实模拟
    // `let url = java.base64Decode(result); let source = "S".toLowerCase(); url + "|" + source`
    if (s.contains('java.base64Decode')) {
      final sv =
          (RegExp(r'let source = "([^"]*)"').firstMatch(s)?.group(1) ?? '')
              .toLowerCase();
      final url = utf8.decode(base64Decode(req.result.toString()));
      return JsEvalResult(value: '$url|$sv');
    }
    return JsEvalResult(value: null);
  }

  @override
  Future<void> dispose() async {}

  static const String _kindsJson = '''[
  {"title": "个性推荐", "url": "https://shuyuan.test/rec", "type": "url",
   "style": {"layout_flexGrow": 1, "layout_flexBasisPercent": 0.45}},
  {"title": "☃关键词💭：书名/作者", "type": "text", "default": "",
   "action": "java.onText(key)"},
  {"title": "🌹开关🌹", "type": "toggle", "chars": ["全部", "小说", "漫画"],
   "action": "java.onToggle()"},
  {"title": "筛选", "type": "select", "chars": ["最新", "最热"],
   "action": "java.onSelect()"},
  {"title": "刷新", "type": "button", "action": "java.onButton()"}
]''';
}

/// 7814 形态书源：`<js>` 搜索地址 + checkKeyWord 仅作调试推荐词。
const _source7814Json = {
  'bookSourceName': '📚书山聚合',
  'bookSourceUrl': 'https://www.yckceo.com',
  'bookSourceType': 0,
  'searchUrl': '<js>java.qsearch(src, key)</js>',
  'exploreUrl': '<js>java.exploreKinds()</js>',
  'ruleSearch': {
    'checkKeyWord': '斗破',
    'bookList': r'$.data',
    'name': r'$.book_name',
    'author': r'$.author',
    'bookUrl': r'https://shuyuan.test/book/{{$.book_id}}',
  },
};

/// 7632 形态书源：checkKeyWord 含易误判为输入正则的字符。
const _source7632Json = {
  'bookSourceName': '🍅大灰狼聚合5.9.30 vip完全版',
  'bookSourceUrl': 'https://www.dhl8.cc',
  'bookSourceType': 0,
  'searchUrl': 'https://www.dhl8.cc/search?key={{key}}',
  'ruleSearch': {
    'checkKeyWord': '我的',
    'bookList': r'$.data.list',
    'name': r'$.name',
    'author': r'$.author',
    'bookUrl': r'$.url',
  },
};

void main() {
  group('7814 书山聚合：内联 JS 求值（replaceKeyPageJs 语义）', () {
    late _FakeJs fake;
    late BookSource source;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      fake = _FakeJs();
      JsRuntimeManager.instance.factoryOverride = (_) => fake;
      source = BookSource.fromJson(_source7814Json);
    });

    tearDown(() async {
      JsRuntimeManager.instance.factoryOverride = null;
      await JsRuntimeManager.instance.disposeAll();
    });

    test('URL 模板 {{encodeURIComponent(key)}} 按内联 JS 求值（中文关键词编码）', () async {
      // 纯模板地址（无 <js> 前缀）：127.0.0.1:9 必然拒绝连接，
      // 但求值后的 URL 会先落入 debugLog，可精确断言。
      final engine = BookSourceEngine();
      final plain = BookSource.fromJson({
        ..._source7814Json,
        'searchUrl':
            'http://127.0.0.1:9/api/search?key={{encodeURIComponent(key)}}&page={{page}}',
      });
      final books = await engine.search(plain, '斗破苍穹');
      expect(books, isEmpty); // 连接被拒，但 URL 已求值
      final reqLine = engine.debugLog.firstWhere((l) => l.contains('127.0.0.1:9'));
      expect(reqLine, contains('key=%E6%96%97%E7%A0%B4%E8%8B%8D%E7%A9%B9'));
      expect(reqLine, contains('page=1'));
      // 内联表达式求值时正确传入 key
      expect(
          fake.calls.any((c) =>
              c.script == 'encodeURIComponent(key)' && c.key == '斗破苍穹'),
          isTrue);
    });

    test('<js> searchUrl -> {{}} 内联求值 -> data 响应 -> 书籍列表', () async {
      final engine = BookSourceEngine();
      final books = await engine.search(source, '斗破苍穹');
      expect(books, isNotEmpty);
      final b = books.first;
      expect(b.name, '斗破苍穹');
      expect(b.author, '天蚕土豆');
      expect(b.bookUrl, 'https://shuyuan.test/book/7814');
      // <js> 求值 -> 模板含 {{b64payload(key)}} -> 内联求值带回 base64 响应
      expect(fake.calls.any((c) => c.script.contains('qsearch')), isTrue);
      expect(
          fake.calls
              .any((c) => c.script == 'b64payload(key)' && c.key == '斗破苍穹'),
          isTrue);
    });
  });

  group('7814 书山聚合：字段规则尾部 JS 内的 {{}} 先替换再执行（makeUpRule 语义）', () {
    late _FakeJs fake;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      fake = _FakeJs();
      JsRuntimeManager.instance.factoryOverride = (_) => fake;
    });

    tearDown(() async {
      JsRuntimeManager.instance.factoryOverride = null;
      await JsRuntimeManager.instance.disposeAll();
    });

    test(r'intro 尾部 <js> 内的 {{$.x}} 先替换再执行', () async {
      // 7814 intro 真实形态：字面量 + {{$.source}}/{{"\n"+"​"}}/{{$.desc}} 前缀，
      // 尾部 <js> 脚本内再嵌 {{$.source}}/{{$.desc}}。
      // 对齐 legado SourceRule.makeUpRule：JS 段的 {{}} 也先按 isRule 消歧替换。
      final src = BookSource.fromJson({
        ..._source7814Json,
        'ruleBookInfo': {
          'init': '',
          'name': r'$.title',
          'intro':
              '&nbsp;&nbsp;\n✨ 源站：{{\$.source}}{{"\\n"+"\u200b"}}\n{{\$.desc}}\n<js>\nconst s = "{{\$.source}}";\nconst d = "{{\$.desc}}";\nresult.indexOf(s) >= 0 && d.length > 0 ? "校验通过:" + s + "/" + d : "校验失败";\n</js>',
        },
      });
      final bookUrl = 'data:;base64,${base64Encode(utf8.encode(jsonEncode({
                'title': '斗破苍穹',
                'source': '番茄小说',
                'desc': '这是简介',
                'bookid': '12345',
              })))}';
      final engine = BookSourceEngine();
      final info = await engine.getBookInfo(src, bookUrl);
      expect(info, isNotNull);
      expect(info!.name, '斗破苍穹');
      // 若尾部 <js> 内的 {{$.source}} 未替换，s 为字面量 "{{$.source}}"，
      // indexOf 失败 →「校验失败」
      expect(info.intro, '校验通过:番茄小说/这是简介');
      // 传给 JS 运行时的脚本里 {{}} 已被替换（无残留占位）
      final tailCall = fake.calls.firstWhere((c) => c.script.contains('const s ='));
      expect(tailCall.script, contains('const s = "番茄小说";'));
      expect(tailCall.script, isNot(contains('{{')));
    });

    test(r'{{$.x##ops}} + @js: 尾巴（7814 downloadUrls 形态）', () async {
      // 7814 downloadUrls 真实形态（此处经 intro 字段承载验证同一条解析链）：
      // 头部 {{$.book_url##[|]}} 走 JSONPath + ## 后处理，尾部 @js: 内嵌 {{$.source}}。
      final src = BookSource.fromJson({
        ..._source7814Json,
        'ruleBookInfo': {
          'init': '',
          'name': r'$.title',
          'intro':
              '{{\$.book_url##[|]}}\n@js:\nlet url = java.base64Decode(result);\nlet source = "{{\$.source}}".toLowerCase();\nurl + "|" + source;\n',
        },
      });
      final bookUrl = 'data:;base64,${base64Encode(utf8.encode(jsonEncode({
                'title': '斗破苍穹',
                'source': 'FanQie',
                'book_url': 'aHR0cHM6Ly9leGFtcGxlLmNvbS9ib29rfGZvbw==',
              })))}';
      final engine = BookSourceEngine();
      final info = await engine.getBookInfo(src, bookUrl);
      expect(info, isNotNull);
      // 头部求值出 base64 串，尾部 JS 解码后拼接（{{$.source}} 已替换为 FanQie）
      expect(info!.intro, 'https://example.com/book|foo|fanqie');
      final tailCall =
          fake.calls.firstWhere((c) => c.script.contains('java.base64Decode'));
      expect(tailCall.script, contains('let source = "FanQie"'));
      expect(tailCall.script, isNot(contains('{{')));
    });
  });

  group('7814 发现页：exploreKinds 动态分类与控件', () {
    late _FakeJs fake;
    late BookSource source;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      fake = _FakeJs();
      JsRuntimeManager.instance.factoryOverride = (_) => fake;
      source = BookSource.fromJson(_source7814Json);
    });

    tearDown(() async {
      JsRuntimeManager.instance.factoryOverride = null;
      await JsRuntimeManager.instance.disposeAll();
    });

    test('<js> exploreUrl 求值为 JSON 数组 -> 五种控件类型解析', () async {
      final engine = BookSourceEngine();
      final kinds = await engine.exploreKinds(source);
      expect(kinds.length, 5);
      final url = kinds.firstWhere((k) => k.title == '个性推荐');
      expect(url.isUrl, isTrue);
      expect(url.url, 'https://shuyuan.test/rec');
      expect(url.style!['layout_flexGrow'], 1);
      final text = kinds.firstWhere((k) => k.type == ExploreKind.typeText);
      expect(text.isControl, isTrue);
      expect(text.title, '☃关键词💭：书名/作者');
      expect(text.defaultValue, '');
      expect(text.action, 'java.onText(key)');
      final toggle = kinds.firstWhere((k) => k.type == ExploreKind.typeToggle);
      expect(toggle.chars, ['全部', '小说', '漫画']);
      final select = kinds.firstWhere((k) => k.type == ExploreKind.typeSelect);
      expect(select.chars, ['最新', '最热']);
      final button = kinds.firstWhere((k) => k.type == ExploreKind.typeButton);
      expect(button.action, 'java.onButton()');
      // 求值注入了 infoMap
      expect(fake.calls.any((c) => c.infoMap != null), isTrue);
    });

    test('文本格式 exploreUrl：:: 切分标题与地址', () async {
      final engine = BookSourceEngine();
      final textSrc = BookSource.fromJson({
        ..._source7814Json,
        'exploreUrl': '推荐::https://shuyuan.test/rec\n新书:::https://shuyuan.test/new',
      });
      final kinds = await engine.exploreKinds(textSrc);
      expect(kinds.length, 2);
      expect(kinds[0].title, '推荐');
      expect(kinds[0].url, 'https://shuyuan.test/rec');
      expect(kinds[1].title, '新书');
      expect(kinds[1].url, 'https://shuyuan.test/new');
    });

    test('exploreUrl 求值失败 -> ERROR 占位（UI 可展示详情）', () async {
      fake.failExploreKinds = true;
      final engine = BookSourceEngine();
      final kinds = await engine.exploreKinds(source);
      expect(kinds.length, 1);
      expect(kinds.first.isError, isTrue);
      expect(kinds.first.title.startsWith('ERROR:'), isTrue);
    });

    test('exploreUrl JSON 损坏 -> ERROR 占位', () async {
      fake.exploreKindsResult = '[{"title":}]';
      final engine = BookSourceEngine();
      final kinds = await engine.exploreKinds(source);
      expect(kinds.single.isError, isTrue);
      expect(kinds.single.title, contains('JSON 解析失败'));
    });

    test('控件动作 evalExploreAction 执行动作 JS', () async {
      final engine = BookSourceEngine();
      await engine.evalExploreAction(source, 'java.onText(key)');
      expect(fake.calls.any((c) => c.script == 'java.onText(key)'), isTrue);
      // 空动作直接返回
      await engine.evalExploreAction(source, '   ');
    });

    test('控件 viewName 动态求值', () async {
      final engine = BookSourceEngine();
      expect(await engine.evalExploreViewName(source, 'java.viewName()'), '动态按钮文字');
      expect(await engine.evalExploreViewName(source, ''), '');
    });
  });

  group('infoMap 持久化（对齐 legado InfoMap）', () {
    late BookSource source;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      source = BookSource.fromJson(_source7814Json);
    });

    test('putExploreInfoMap / loadExploreInfoMap 跨会话 round-trip', () async {
      final engine = BookSourceEngine();
      expect(await engine.loadExploreInfoMap(source), isEmpty);
      await engine.putExploreInfoMap(source, '☃关键词💭：书名/作者', '斗破苍穹');
      await engine.putExploreInfoMap(source, '🌹开关🌹', '小说');
      final loaded = await engine.loadExploreInfoMap(source);
      expect(loaded['☃关键词💭：书名/作者'], '斗破苍穹');
      expect(loaded['🌹开关🌹'], '小说');
      // 按书源维度隔离
      final other = BookSource.fromJson(_source7632Json);
      expect(await engine.loadExploreInfoMap(other), isEmpty);
    });
  });

  group('7632 大灰狼：checkKeyWord 仅作调试推荐词', () {
    test('effectiveCheckKeyWord 取 ruleSearch.checkKeyWord', () {
      final s = BookSource.fromJson(_source7632Json);
      expect(s.effectiveCheckKeyWord, '我的');
      final s2 = BookSource.fromJson(_source7814Json);
      expect(s2.effectiveCheckKeyWord, '斗破');
    });

    test('顶层 checkKeyWord 回落', () {
      final s = BookSource.fromJson({
        ..._source7632Json,
        'checkKeyWord': '我的',
        'ruleSearch': {
          'bookList': r'$.data.list',
          'name': r'$.name',
          'author': r'$.author',
          'bookUrl': r'$.url',
        },
      });
      expect(s.effectiveCheckKeyWord, '我的');
    });

    test('无 checkKeyWord 时为 null（调试页回退默认词）', () {
      final s = BookSource.fromJson({
        ..._source7632Json,
        'ruleSearch': {
          'bookList': r'$.data.list',
          'name': r'$.name',
          'author': r'$.author',
          'bookUrl': r'$.url',
        },
      });
      expect(s.effectiveCheckKeyWord, isNull);
    });
  });

  group('getExploreKinds 旧文本解析（兼容旧调用方）', () {
    test('多行 + &&& + ::: 兼容', () {
      final engine = BookSourceEngine();
      final s = BookSource.fromJson({
        ..._source7814Json,
        'exploreUrl': '推荐::https://a.test/1&&&新书:::https://a.test/2\n其他::https://a.test/3',
      });
      final kinds = engine.getExploreKinds(s);
      expect(kinds.length, 3);
      expect(kinds[0]['title'], '推荐');
      expect(kinds[0]['url'], 'https://a.test/1');
      expect(kinds[1]['title'], '新书');
      expect(kinds[1]['url'], 'https://a.test/2');
      expect(kinds[2]['url'], 'https://a.test/3');
    });
  });
}
