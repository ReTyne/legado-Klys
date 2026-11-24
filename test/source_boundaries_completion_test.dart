import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:legado_md3/help/source/rule_data.dart';
import 'package:legado_md3/help/source/rule_pipeline.dart';

/// 书源五项深度边界补齐的行文与行为契约。
///
/// 覆盖：正则列表规则、sourceRegex 语义、变量跨书隔离、重新登录信号 UI 消费、
/// 退出登录清除 WebView 原生 Cookie。防止这五类问题回归。
void main() {
  String src(String rel) => File(rel).readAsStringSync();

  group('边界一：正则列表规则', () {
    test('selectElements 具备 regex 分支', () {
      final s = src('lib/help/source/rule_pipeline.dart');
      expect(s, contains('case RuleMode.regex:'));
      expect(s, contains('_regexElements(scope, core)'));
    });

    test(r'正则列表每个匹配产生带 $N 捕获组属性的元素', () {
      final p = RulePipeline();
      final doc = html_parser.parse(
          '<a href="/book/1.html">甲</a><a href="/book/2.html">乙</a>');
      final items = p.selectElements(
          doc, r':href="(/book/[^\"]+)"[^>]*>([^<]+)');
      expect(items.length, 2);
      // $1 为链接，$2 为标题，均由捕获组属性承载。
      expect(p.fieldFromElement(items[0], r'$1'), '/book/1.html');
      expect(p.fieldFromElement(items[0], r'$2'), '甲');
      expect(p.fieldFromElement(items[1], r'$2'), '乙');
    });

    test('链式正则列表按末段捕获组取列表项', () {
      final p = RulePipeline();
      final doc = html_parser.parse('<div><span id="c1">A</span><span id="c2">B</span></div>');
      final items = p.selectElements(doc, r':<span[^>]*>.*?</span>&&id="([^"]+)"');
      expect(items.length, 2);
      expect(p.fieldFromElement(items[0], r'$1'), 'c1');
      expect(p.fieldFromElement(items[1], r'$1'), 'c2');
    });
  });

  group('边界二：sourceRegex 语义', () {
    test('webJs 渲染把 sourceRegex 传给无头 WebView 嗅探', () {
      final s = src('lib/help/source/source_engine.dart');
      expect(s, contains('sourceRegex: sourceRegex,'));
      expect(s, contains('sourceRegex: contentSourceRegex'));
    });

    test('正文文本截取仅在无 webJs 时兜底', () {
      final s = src('lib/help/source/source_engine.dart');
      expect(s, contains('if (webJs.trim().isEmpty && contentSourceRegex.trim().isNotEmpty)'));
    });
  });

  group('边界三：变量跨书隔离', () {
    test('RuleData 具备仅清书/章节层的能力', () {
      final rd = RuleData()
        ..putInLayer('source', 'token', 'SOURCE_TOKEN')
        ..putInLayer('book', 'bid', 'BOOK_1')
        ..putInLayer('chapter', 'cid', 'CH_1');
      rd.clearBookScope();
      expect(rd.getVariable('token'), 'SOURCE_TOKEN');
      expect(rd.getVariable('bid'), '');
      expect(rd.getVariable('cid'), '');
    });

    test('引擎按书源级键集合筛选，换书清书级变量', () {
      final s = src('lib/help/source/source_engine.dart');
      expect(s, contains('_clearStaleBookVariables'));
      expect(s, contains('removeWhere((k, _) => !_sourceScopedKeys.contains(k))'));
      expect(s, contains('_sourceScopedKeys'));
      // 三个书籍入口都接入换书清理。
      expect(s, contains('await _beginSourceSession(source, bookUrl: bookUrl)'));
      expect(RegExp(r'_clearStaleBookVariables\(seed\[.bookUrl.\]').hasMatch(s), isTrue);
    });
  });

  group('边界四：重新登录信号 UI 消费', () {
    test('主界面监听 reloginSignal 并提供登录入口', () {
      final s = src('lib/ui/main/main_screen.dart');
      expect(s, contains('reloginSignal.addListener(_onReloginSignal)'));
      expect(s, contains('reloginSignal.removeListener(_onReloginSignal)'));
      expect(s, contains('reloginSourceOf(signal)'));
      expect(s, contains('SourceLoginScreen(source: target!)'));
    });
  });

  group('边界五：退出登录清除 WebView 原生 Cookie', () {
    test('清除登录头时删除 WebView 原生 Cookie', () {
      final s = src('lib/ui/book/source/parts/source_login_screen_state.dart');
      expect(s, contains('iw.CookieManager.instance()'));
      expect(s, contains('deleteCookies(url: iw.WebUri(u))'));
    });
  });
}
