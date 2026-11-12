import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/help/source/js/legado_js_runtime.dart';
import 'package:legado_md3/help/source/rule_pipeline.dart';
import 'package:legado_md3/help/source/source_engine.dart';

/// 回归：yckceo 7632「大灰狼聚合」这类重度 JS 聚合源的 bookUrl 规则是
/// **整块 <js>...</js>**。此前 rule_pipeline 的 _splitPostProcess 会用
/// `<js>(...)</js>$` 把它误判成「尾部 JS」，selector 被清空，引擎随后退化成
/// 把 `item.toString()` 当 result 传给脚本。书源里的
/// `let book_id = result.book_id` 因此恒为 undefined，JSON.stringify 后只剩
/// `{"tab":"小说","url":""}` —— 正是调试页详情/目录源码里看到的那串 hex。
///
/// 本测试全程离线：searchUrl 的 <js> 用 data: 载体带回真实形态的搜索响应，
/// 伪运行时记录每次求值收到的 result，并忠实模拟书源打包 data: 书址的行为。
class _RecordingJs implements LegadoJs {
  final List<dynamic> results = [];

  @override
  Future<void> loadSource(JsSource source) async {}

  @override
  Future<JsEvalResult> eval(JsEvalRequest req) async {
    final s = req.script.trim();
    // 7632 searchUrl 的 <js>：返回内嵌搜索响应的 data: 载体（不经网络）
    if (s.contains('/search?title=')) {
      return JsEvalResult(
          value: 'data:;base64,${base64Encode(utf8.encode(_searchJson))}');
    }
    // 7632 ruleSearch.bookUrl 的整块 <js>：把书籍对象打包成 data: 书址
    if (s.contains('qtdetail')) {
      results.add(req.result);
      final r = req.result;
      final Map<String, dynamic> payload;
      if (r is Map) {
        payload = {
          'book_id': r['book_id'],
          'sources': r['source'],
          'tab': r['tab'] ?? '小说',
          'url': r['toc_url'] ?? '',
        };
      } else {
        // JS 中 result.book_id / result.source 为 undefined 时，
        // JSON.stringify 会丢掉这些字段（书源实际退化行为）。
        payload = {'tab': '小说', 'url': ''};
      }
      return JsEvalResult(
        value: 'data:;base64,${base64Encode(utf8.encode(jsonEncode(payload)))},'
            '{"type":"qingtian"}',
      );
    }
    return JsEvalResult(value: null);
  }

  @override
  Future<void> dispose() async {}
}

/// 用户提供的大灰狼聚合搜索源码（截取前两本，保留全部关键字段）。
const String _searchJson = r'''{
  "code": 0, "msg": "ok", "cache": true,
  "data": [
    {"book_name":"我的26岁女房客","book_id":"NjU2OTk5NzgzOTQzNzQwMTEwMQ",
     "author":"超级大坦克科比","score":"9.7分","status":"已完结",
     "word_number":"205.39 万字","last_chapter_update_time":"2018-07-24 20:30:28",
     "last_chapter_title":"","category":"都市日常","tags":"都市日常,都市",
     "abstract":"酒吧疯狂一夜，被美女讹上。","read_count":"12.00 万人",
     "thumb_url":"https://example.com/c1.jpg","role":"","tab":"小说",
     "source":"番茄","book_url":"","toc_url":""},
    {"book_name":"我的26岁女房客之海岛孤帆","book_id":"NzMxMTczOTAyMDgxMDEyODQxOA",
     "author":"超级大坦克科比","score":"9.3分","status":"连载中",
     "word_number":"18.59 万字","last_chapter_update_time":"2024-08-29 18:56:32",
     "last_chapter_title":"","category":"都市日常","tags":"都市日常,都市",
     "abstract":"爱情到底是什么，又产生何处呢？","read_count":"1.95 万人",
     "thumb_url":"https://example.com/c2.jpg","role":"","tab":"小说",
     "source":"番茄","book_url":"","toc_url":""}
  ]
}''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BookSource source;
  late _RecordingJs fake;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final raw = File('test/fixtures/source_7632.json').readAsStringSync();
    source = BookSource.fromJson(
        (jsonDecode(raw) as Map<String, dynamic>).cast<String, dynamic>());
    fake = _RecordingJs();
    JsRuntimeManager.instance.factoryOverride = (_) => fake;
  });

  tearDown(() => JsRuntimeManager.instance.factoryOverride = null);

  test('整块 <js> 规则不被当作尾部 JS 拆开', () {
    final rule = source.ruleSearch!['bookUrl'].toString();
    expect(rule.trim(), startsWith('<js>'));
    final parts = RulePipeline().parseFieldParts(rule);
    expect(parts.tailJs, isNull,
        reason: '整块 <js> 规则被误判成 tailJs 会导致 selector 为空');
    expect(parts.selector, contains('<js>'));
    expect(parts.ops, isEmpty);
  });

  test('7632 搜索 bookUrl 携带真实 book_id/source（result 必须是节点对象）',
      () async {
    final engine = BookSourceEngine();
    final books = await engine.search(source, '我的26岁女房客');
    expect(books, isNotEmpty, reason: '搜索链路应解析出书籍');

    expect(fake.results, isNotEmpty,
        reason: '应至少执行一次 bookUrl 的 <js> 规则');
    expect(fake.results.first, isA<Map>(),
        reason: 'JS 的 result 必须是完整书籍对象，不能是 item.toString() 字符串');
    final injected = fake.results.first as Map;
    expect(injected['book_id'], 'NjU2OTk5NzgzOTQzNzQwMTEwMQ');
    expect(injected['source'], '番茄');

    final url = books.first.bookUrl!;
    expect(url, startsWith('data:;base64,'));
    final b64 =
        url.substring('data:;base64,'.length).split(',{"type"').first;
    final payload =
        jsonDecode(utf8.decode(base64Decode(b64))) as Map<String, dynamic>;
    expect(payload['book_id'], 'NjU2OTk5NzgzOTQzNzQwMTEwMQ',
        reason: '详情/目录必须拿到 book_id，否则只能产出 {"tab":"小说","url":""}');
    expect(payload['sources'], '番茄');
    expect(payload['tab'], '小说');
  });
}
