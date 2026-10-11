import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/help/source/js/legado_js_runtime.dart';
import 'package:legado_md3/help/source/rule_pipeline.dart';
import 'package:legado_md3/help/source/source_engine.dart';
import 'package:legado_md3/ui/book/source/source_login_screen.dart';

/// 模拟示例源（大灰狼融合 VIP5.0）各阶段 JS 产出的伪运行时。
/// 仅搜索请求走本地 HTTP，其余 java.ajax 的结果按脚本标记直接返回罐头数据，
/// 用于验证 Dart 侧编排（URL 规则 / data 书址 / 前置<js>+后缀 / mustache）。
class _FakeLegadoJs implements LegadoJs {
  _FakeLegadoJs();
  int evalCount = 0;
  final List<String> actions = [];

  String _dataUri(Map<String, dynamic> m, {String? type}) {
    final b64 = base64Encode(utf8.encode(jsonEncode(m)));
    return type == null
        ? 'data:;base64,$b64'
        : 'data:;base64,$b64,{"type":"$type"}';
  }

  static Map<String, dynamic> get _searchItem => {
        'book_name': '测试书',
        'book_id': 'b1',
        'author': '作者甲',
        'thumb_url': 'https://x/cover.jpg',
        'abstract': '这是简介',
        'status': '完结',
        'score': '9.0',
        'tags': '玄幻',
        'last_chapter_update_time': '2024-01-01',
        'source': '全部',
        'last_chapter_title': '第10章',
        'word_number': '100万字',
        'tab': '小说',
        'toc_url': '',
      };

  @override
  Future<void> loadSource(JsSource source) async {}

  @override
  Future<JsEvalResult> eval(JsEvalRequest req) async {
    evalCount++;
    final s = req.script;

    // 1) 搜索 URL 规则：返回携带搜索响应的 data URI（等价于 http 抓取，规避测试网络限制）
    if (req.isUrlRule) {
      return JsEvalResult(
          value: _dataUri({
        'code': 0,
        'data': [_searchItem]
      }));
    }
    // 2) 目录 chapterList（返回明文 JSON，后缀 $.data）
    if (s.contains('/catalog?book_id')) {
      return JsEvalResult(
          value: jsonEncode({
        'code': 0,
        'data': [
          {'title': '第一章', 'item_id': 'i1', 'source': '全部', 'tab': '小说'},
          {'title': '第二章', 'item_id': 'i2', 'source': '全部', 'tab': '小说'},
        ]
      }));
    }
    // 3) 正文 content（返回 JSON 字符串，后缀 $.content）
    if (s.contains('online_video')) {
      return JsEvalResult(
          value: jsonEncode({'content': '正文内容第一段\n第二段'}));
    }
    // 4) 详情 init（明文 JSON，后缀 $.data）
    if (s.contains('/detail?book_id')) {
      return JsEvalResult(
          value: jsonEncode({
        'code': 0,
        'data': {
          'book_name': '测试书',
          'author': '作者甲',
          'thumb_url': 'https://x/cover.jpg',
          'abstract': '这是简介',
          'status': '完结',
          'score': '9.0',
          'tags': '玄幻',
          'last_chapter_update_time': '2024-01-01',
          'source': '全部',
          'last_chapter_title': '第10章',
          'word_number': '100万字',
        }
      }));
    }
    // 5) chapterUrl -> qingtian3
    if (s.contains('qingtian3')) {
      return JsEvalResult(
          value: _dataUri(
              {
                'book_id': 'b1',
                'item_id': 'i1',
                'title': '第一章',
                'sources': '全部',
                'tab': '小说',
                'url': ''
              },
              type: 'qingtian3'));
    }
    // 6) tocUrl -> qingtian2
    if (s.contains('qingtian2')) {
      return JsEvalResult(
          value: _dataUri(
              {'book_id': 'b1', 'sources': '全部', 'tab': '小说', 'url': ''},
              type: 'qingtian2'));
    }
    // 7) bookUrl -> qingtian
    if (s.contains('qtdetail')) {
      return JsEvalResult(
          value: _dataUri(
              {'book_id': 'b1', 'sources': '全部', 'tab': '小说', 'url': ''},
              type: 'qingtian'));
    }
    // 8) mustache 内部表达式 $.x（result 为当前节点 Map）
    final r = s.trim();
    if (r.startsWith(r'$.') && req.result is Map) {
      final key = r.substring(2);
      final v = (req.result as Map)[key];
      return JsEvalResult(value: v?.toString());
    }
    return JsEvalResult(value: null);
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  const samplePath =
      '/home/user/Doubao/chats/38441367341963522/sample_source.json';

  group('RulePipeline 字段拆分/后处理', () {
    final p = RulePipeline();
    test('parseFieldParts 单个 ## 为 remove', () {
      final parts = p.parseFieldParts(r'$.book_name##（别名：.*?）');
      expect(parts.selector, r'$.book_name');
      expect(parts.ops.length, 1);
      expect(parts.ops.single.kind, 'remove');
    });
    test('parseFieldParts 识别 replace', () {
      final parts = p.parseFieldParts(r'$.name##张三##李四');
      expect(parts.ops.single.kind, 'replace');
      expect(parts.ops.single.replacement, '李四');
    });
    test('applyFieldOps remove/replace/match', () {
      expect(
          p.applyFieldOps('正文广告结尾', [FieldOp('remove', '广告', null)]),
          '正文结尾');
      expect(
          p.applyFieldOps('张三的书', [FieldOp('replace', '张三', '李四')]),
          '李四的书');
      expect(
          p.applyFieldOps('abc123', [FieldOp('match', r'\d+', null)]), '123');
    });
    test('jsonPathFirst 取对象字段', () {
      expect(
          p.jsonPathFirst({'book_name': 'X'}, r'$.book_name').toString(), 'X');
    });
  });

  group('示例源完整链路编排（伪运行时）', () {
    late _FakeLegadoJs fake;
    late BookSource source;

    setUp(() async {
      fake = _FakeLegadoJs();
      JsRuntimeManager.instance.factoryOverride = (_) => fake;
      final raw = File(samplePath).readAsStringSync();
      source = BookSource.fromJson((jsonDecode(raw) as List).first);
    });

    tearDown(() async {
      JsRuntimeManager.instance.factoryOverride = null;
      await JsRuntimeManager.instance.disposeAll();
    });

    test(r'搜索：URL规则->$.data->字段(含mustache)->data书址', () async {
      final engine = BookSourceEngine();
      final results = await engine.search(source, '测试书');
      expect(results, isNotEmpty);
      final b = results.first;
      expect(b.name, '测试书');
      expect(b.author, '作者甲');
      expect(b.bookUrl!.startsWith('data:'), isTrue);
      // kind mustache: 完结,9.0,玄幻,2024-01-01
      expect(b.kind, '完结,9.0,玄幻,2024-01-01');
      // lastChapter mustache
      expect(b.lastChapter, '全部 第10章');
    });

    test(r'详情：data书址->init(/detail)->$.data->tocUrl(qingtian2)', () async {
      final engine = BookSourceEngine();
      final results = await engine.search(source, '测试书');
      final info = await engine.getBookInfo(source, results.first.bookUrl!,
          presetName: results.first.name, presetAuthor: results.first.author);
      expect(info, isNotNull);
      expect(info!.name, '测试书');
      expect(info.author, '作者甲');
      expect(info.noteUrl!.startsWith('data:'), isTrue);
      expect(info.noteUrl!.contains('qingtian2'), isTrue);
    });

    test(r'目录：data书址->chapterList(/catalog)->$.data->chapterUrl(qingtian3)',
        () async {
      final engine = BookSourceEngine();
      final results = await engine.search(source, '测试书');
      final info = await engine.getBookInfo(source, results.first.bookUrl!);
      final chapters = await engine.getToc(source, info!.noteUrl!,
          bookInfo: info.jsContext());
      expect(chapters.length, 2);
      expect(chapters[0].title, '第一章');
      expect(chapters[1].title, '第二章');
      expect(chapters[0].url.startsWith('data:'), isTrue);
      expect(chapters[0].url.contains('qingtian3'), isTrue);
    });

    test(r'正文：data书址->content->$.content', () async {
      final engine = BookSourceEngine();
      final results = await engine.search(source, '测试书');
      final info = await engine.getBookInfo(source, results.first.bookUrl!);
      final chapters = await engine.getToc(source, info!.noteUrl!,
          bookInfo: info.jsContext());
      final content = await engine.getContent(source, chapters.first.url,
          bookInfo: info.jsContext(),
          chapter: chapters.first.jsContext(info.bookUrl));
      expect(content, isNotNull);
      expect(content!.contains('正文内容第一段'), isTrue);
    });
  });

  group('书源登录页 loginUi 渲染', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      JsRuntimeManager.instance.factoryOverride = (_) => _FakeLegadoJs();
    });
    tearDown(() async {
      JsRuntimeManager.instance.factoryOverride = null;
      await JsRuntimeManager.instance.disposeAll();
    });

    testWidgets('按 loginUi 生成输入框与按钮', (tester) async {
      final source = BookSource.fromJson({
        'bookSourceName': '测试源',
        'bookSourceUrl': 'test-src',
        'loginUrl': '<js>\nfunction login(){}\n</js>',
        'loginUi': jsonEncode([
          {'name': '邮箱', 'type': 'text'},
          {'name': '密码', 'type': 'password'},
          {'name': '登录', 'type': 'button', 'action': 'login(true)'},
          {'name': '注册', 'type': 'button', 'action': 'register()'},
        ]),
      });
      await tester.pumpWidget(MaterialApp(home: SourceLoginScreen(source: source)));
      await tester.pump();
      expect(find.text('邮箱'), findsOneWidget);
      expect(find.text('密码'), findsOneWidget);
      expect(find.text('登录'), findsWidgets);
      expect(find.text('注册'), findsOneWidget);
    });
  });
}
