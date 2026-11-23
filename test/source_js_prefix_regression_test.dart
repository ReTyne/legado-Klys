import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 书源脚本字段前缀剥离防回归。
/// 凡是把书源字段当 JS 执行的地方，若字段以 @js:/<js> 开头，
/// 必须先剥离前缀，否则顶层 `@` 会触发 SyntaxError 让整段脚本失效。
void main() {
  String src(String rel) => File(rel).readAsStringSync();

  group('字段前缀剥离契约', () {
    test('事件回调 callBackJs 拼接前剥离', () {
      final s = src('lib/help/source/source_event_callback.dart');
      expect(s, contains('stripJsRulePrefix(source.callBackJs)'));
    });

    test('正文回调 callBack 求值前剥离', () {
      final s = src('lib/help/source/source_engine.dart');
      expect(s, contains('stripJsRulePrefix(callBackRaw)'));
    });

    test('封面解密 coverDecodeJs 求值前剥离', () {
      final s = src('lib/help/source/source_engine.dart');
      expect(s, contains('stripJsRulePrefix(coverDecode)'));
    });

    test('图片解密 imageDecode 求值前剥离', () {
      final s = src('lib/help/source/source_engine.dart');
      expect(s, contains('stripJsRulePrefix(decodeJs)'));
    });

    test('@js: 内容规则走完整 JS 运行时而非迷你求值器', () {
      final s = src('lib/help/source/source_engine.dart');
      expect(s, contains("r.toLowerCase().startsWith('@js:')"));
    });

    test('RSS injectJs/preloadJs/override 注入前用 _jsBody 剥离', () {
      final s = src('lib/ui/rss/parts/html_body.dart');
      expect(s, contains('_jsBody(injectJs ?? \'\')'));
      expect(s, contains('_jsBody(preloadJs ?? \'\')'));
      expect(s, contains('_jsBody(shouldOverrideUrlLoading ?? \'\')'));
    });
  });

  group('登录态与Cookie正确性', () {
    test('loginInfo 显式清空时移除持久化键', () {
      final s = src('lib/help/source/js/parts/web_view_legado_js.dart');
      expect(s, contains("await prefs.remove('loginInfo_\$srcUrl')"));
    });

    test('多键 Cookie 用 replaceCookie 逐 pair 写入', () {
      final s = src('lib/help/source/js/parts/web_view_legado_js.dart');
      // 不应再用 saveFromResponse 解析完整 Cookie 串（只取首项）
      expect(s.contains('CookieManager().replaceCookie(url, v)'), isTrue);
      expect(s.contains('CookieManager().replaceCookie(url, cookieStr)'), isTrue);
    });

    test('login scene 白名单包含登录态方法', () {
      final s = src('lib/help/source/js/bridge/legado_bridge_js_08.dart');
      expect(s, contains('"getLoginInfoMap"'));
      expect(s, contains('"putLoginInfo"'));
      expect(s, contains('"getLoginHeader"'));
    });
  });

  group('书源管理按域名分组真实生效', () {
    test('分组开关驱动列表构建而非仅提示', () {
      final s = src('lib/ui/book/source/source_manage_screen.dart');
      expect(s, contains('_groupByDomain\n                        ? _buildDomainGroupedList()'));
      expect(s, contains('List<({String? header, BookSource? source})> get _domainGroupedItems'));
    });
  });
}
