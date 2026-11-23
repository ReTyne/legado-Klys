import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/help/source/js/legado_js_runtime.dart';

/// 登录按钮 action 调用的辅助函数定义在 loginUrl 的 @js: 脚本里。
/// 若注入时不剥离 @js: 前缀，脚本顶层 `@` 触发 SyntaxError，
/// 导致所有函数在按钮 action 执行时 is not defined。
void main() {
  group('stripJsRulePrefix', () {
    test('剥离 @js: 前缀', () {
      expect(stripJsRulePrefix('@js:\nfunction a(){}'), '\nfunction a(){}');
    });

    test('剥离 <js>...</js> 包裹', () {
      expect(stripJsRulePrefix('<js>function a(){}</js>'), 'function a(){}');
    });

    test('纯 JS 原样返回', () {
      expect(stripJsRulePrefix(' function a(){} '), 'function a(){}');
    });

    test('@js: 剥离后不再含非法 @ 前缀', () {
      final out = stripJsRulePrefix('@js:\nvar x=1;');
      expect(out.startsWith('@'), isFalse);
    });
  });

  group('真实微博书源登录脚本', () {
    late Map<String, dynamic> source;
    setUpAll(() {
      final file = File('test/fixtures/source_weibo_login.json');
      final list = jsonDecode(file.readAsStringSync()) as List<dynamic>;
      source = list.first as Map<String, dynamic>;
    });

    test('loginUrl 以 @js: 开头且剥离后函数定义完整', () {
      final raw = (source['loginUrl'] as String).trim();
      expect(raw.startsWith('@js:'), isTrue);
      final code = stripJsRulePrefix(raw);
      expect(code.startsWith('@'), isFalse);
      for (final fn in [
        '_wbCheck',
        '_wbToggleCmt',
        '_wbCands',
        '_wbApply',
        '_wbVal',
        '_wbExport',
      ]) {
        expect(code, contains('function $fn('));
      }
    });

    test('loginUi 按钮 action 调用的函数都在 loginUrl 中定义', () {
      final raw = (source['loginUrl'] as String).trim();
      final code = stripJsRulePrefix(raw);
      final ui = jsonDecode(source['loginUi'] as String) as List<dynamic>;
      final actions = ui
          .whereType<Map<String, dynamic>>()
          .map((e) => e['action']?.toString() ?? '')
          .where((a) => a.isNotEmpty && !a.startsWith('http'));
      for (final action in actions) {
        final m = RegExp(r'\b(_wb[A-Za-z]+)\s*\(').firstMatch(action);
        if (m != null) {
          expect(code, contains('function ${m.group(1)}('),
              reason: '按钮 action "$action" 调用的函数应在 loginUrl 中定义');
        }
      }
    });
  });

  group('注入与执行的防回归契约', () {
    test('WebView loadSource 注入 loginUrl 前调用剥离', () {
      final src = File('lib/help/source/js/parts/web_view_legado_js.dart')
          .readAsStringSync();
      expect(src, contains('stripJsRulePrefix(loginRaw)'));
    });

    test('登录页按钮 action 拼接剥离后的 loginJS', () {
      final src = File('lib/ui/book/source/parts/source_login_screen_state.dart')
          .readAsStringSync();
      expect(src, contains("stripJsRulePrefix((source.loginUrl ?? '').trim())"));
      expect(src, contains(r"'$loginJs\n$act'"));
    });

    test('loginCheckJs 求值前剥离前缀', () {
      final src = File('lib/help/source/source_engine.dart').readAsStringSync();
      // checkLogin 与 evaluateLoginCheck 两处都对 loginCheckJs 剥前缀
      final hits = 'stripJsRulePrefix(jsRaw)'.allMatches(src).length;
      expect(hits, greaterThanOrEqualTo(2));
    });

    test('动态 loginUi 用剥离后的 loginJS 作前导', () {
      final src =
          File('lib/help/source/js/bridge/legado_bridge_js_06.dart')
              .readAsStringSync();
      expect(src, contains('try { loginJs = source.getLoginJs() || ""; }'));
    });

    test('RSS 登录按钮 action 拼接剥离后的 loginJS', () {
      final src = File('lib/ui/rss/rss_source_login_screen.dart')
          .readAsStringSync();
      expect(src, contains('stripJsRulePrefix((source.loginUrl ?? \'\').trim())'));
      expect(src, contains(r"'$loginJs\n$act'"));
    });

    test('java 对象暴露书源登录脚本惯用的登录态方法', () {
      final src =
          File('lib/help/source/js/bridge/legado_bridge_js_07.dart')
              .readAsStringSync();
      for (final m in [
        'getLoginInfoMap',
        'putLoginInfo',
        'getLoginHeader',
        'putLoginHeader',
        'removeLoginInfo',
        'removeLoginHeader',
      ]) {
        expect(src, contains('$m: function'),
            reason: 'java.$m 应委托到 source 对象实现');
      }
    });
  });
}
