import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/help/source/js/offline_js_bridge.dart';
import 'package:legado_md3/help/source/rule_pipeline.dart';

import 'helpers/lib_source_helper.dart';

/// 用 yckceo 社区两个真实聚合书源（7632 大灰狼 / 7814 书山）做的离线兼容回归。
/// 全程不依赖网络 / WebView / 原生通道：fixture 落盘、模型往返、规则前缀识别、
/// jsLib 注入、纯 Dart 桥 API 真实实现均可在 flutter_test 内确定性复现。
void main() {
  Map<String, dynamic> loadFixture(String name) => jsonDecode(
      File('test/fixtures/$name').readAsStringSync()) as Map<String, dynamic>;

  final f7632 = loadFixture('source_7632.json');
  final f7814 = loadFixture('source_7814.json');
  final fixtures = <String, Map<String, dynamic>>{'7632': f7632, '7814': f7814};

  group('真实书源 fromJson / toJson 往返', () {
    for (final entry in fixtures.entries) {
      test('${entry.key} 高级字段完整解析且 toJson 不丢字段', () {
        final f = entry.value;
        final s = BookSource.fromJson(f);
        // 登录 / 共享库 / 动态头 / 动态发现 / 标志位等高级字段逐一还原
        expect(s.bookSourceName, f['bookSourceName']);
        expect(s.bookSourceUrl, f['bookSourceUrl']);
        expect(s.loginUi, f['loginUi']);
        expect(s.loginUrl, f['loginUrl']);
        expect(s.jsLib, f['jsLib']);
        expect(s.header, f['header']);
        expect(s.exploreUrl, f['exploreUrl']);
        expect(s.enabledCookieJar, f['enabledCookieJar']);
        expect(s.customButton, f['customButton']);
        expect(s.eventListener, f['eventListener']);
        expect(s.bookUrlPattern, f['bookUrlPattern']);
        // 嵌套规则保持为 Map（fromJson 不把规则字符串化）
        for (final rule in [
          s.ruleSearch,
          s.ruleExplore,
          s.ruleBookInfo,
          s.ruleToc,
          s.ruleContent,
        ]) {
          expect(rule, isA<Map<String, dynamic>>());
        }

        final round = s.toJson();
        for (final k in f.keys) {
          expect(round.containsKey(k), isTrue, reason: '字段 $k 在往返中丢失');
        }
        for (final k in const [
          'loginUi', 'loginUrl', 'jsLib', 'header', 'exploreUrl', 'searchUrl',
          'bookUrlPattern', 'enabledCookieJar', 'customButton', 'eventListener',
          'ruleSearch', 'ruleExplore', 'ruleBookInfo', 'ruleToc', 'ruleContent',
        ]) {
          expect(round[k], f[k], reason: '字段 $k 往返值不一致');
        }
        // 二次 fromJson(toJson) 稳定（不因 DateTime.now() 兜底产生漂移）
        expect(BookSource.fromJson(round).toJson(), round);
      });
    }
  });

  group('loginUi 动态登录表单控件', () {
    List<Map<String, dynamic>> items(String? raw) =>
        (jsonDecode(raw!) as List).cast<Map<String, dynamic>>();

    test('7632：23 个控件，text/password/button 与 name/action 正确', () {
      final list = items(BookSource.fromJson(f7632).loginUi);
      expect(list.length, 23);
      expect(list.where((e) => e['type'] == 'text').length, 5);
      expect(list.where((e) => e['type'] == 'password').length, 1);
      expect(list.where((e) => e['type'] == 'button').length, 17);
      expect(list[0]['name'], '邮箱');
      expect(list[0]['type'], 'text');
      expect(list[1]['name'], '密码');
      expect(list[1]['type'], 'password');
      final btn = list.firstWhere((e) => e['name'] == '♥登录书源');
      expect(btn['type'], 'button');
      expect(btn['action'], 'login(true)');
      // button 型控件均带 action（调用 loginUrl 中的 JS 函数）
      expect(
          list
              .where((e) => e['type'] == 'button')
              .every((e) => (e['action'] as String).isNotEmpty),
          isTrue);
    });

    test('7814：37 个控件，action 允许为空串', () {
      final list = items(BookSource.fromJson(f7814).loginUi);
      expect(list.length, 37);
      expect(list.where((e) => e['type'] == 'text').length, 7);
      expect(list.where((e) => e['type'] == 'password').length, 3);
      expect(list.where((e) => e['type'] == 'button').length, 27);
      expect(list[0]['name'], '邮箱');
      expect(list[1]['type'], 'password');
      expect(list[2]['name'], '⭕账号登录');
      expect(list[2]['type'], 'button');
      expect(list[2]['action'], 'login(true)');
      expect(list.every((e) => e.containsKey('type') && e.containsKey('name')),
          isTrue);
    });
  });

  group('规则引擎识别 @js: / <js> 前缀', () {
    final p = RulePipeline();

    test('7814 header 的 @js: 前缀判为 JS 规则（非普通 JSON 头）', () {
      final h = BookSource.fromJson(f7814).header!;
      expect(h.trim().toLowerCase().startsWith('@js:'), isTrue);
      expect(p.modeOf(h), RuleMode.js);
      expect(RulePipeline.looksLikeRule(h), isTrue);
      expect(h.trim().startsWith('{'), isFalse);
      // 动态头依赖运行时提供 java.getWebViewUA
      expect(h, contains('java.getWebViewUA()'));
    });

    test('7632 header 是普通 JSON 头（无 @js: 前缀）', () {
      final h = BookSource.fromJson(f7632).header!;
      expect(h.trim().startsWith('{'), isTrue);
      expect(p.modeOf(h), isNot(RuleMode.js));
    });

    test('两个源 exploreUrl 的 <js>...</js> 判为 JS 规则，不误当普通 URL', () {
      for (final f in fixtures.values) {
        final eu = BookSource.fromJson(f).exploreUrl!;
        expect(eu.trim().startsWith('<js>'), isTrue);
        expect(eu.trim().endsWith('</js>'), isTrue);
        expect(p.modeOf(eu), RuleMode.js);
        expect(RulePipeline.looksLikeRule(eu), isTrue);
      }
      // 反例：普通 URL / 带 {{key}} 模板的 URL 均不被误判为 JS 规则
      expect(p.modeOf('https://example.com/search?key={{key}}'),
          isNot(RuleMode.js));
      expect(RulePipeline.looksLikeRule('https://example.com/list'), isFalse);
    });
  });

  group('jsLib 提供给 JS 运行时', () {
    test('7632 jsLib 注入后含 getArguments', () {
      final s = BookSource.fromJson(f7632);
      final rt = OfflineJsBridge();
      rt.loadSource(s);
      expect(rt.script, isNotEmpty);
      expect(rt.script, contains(s.jsLib!));
      expect(rt.script, contains(s.loginUrl!)); // loginUrl 一并注入
      expect(rt.containsFunction('getArguments'), isTrue);
      expect(s.jsLib, contains('function getArguments'));
    });

    test('7814 jsLib 注入后含 getServerHost / getSecretKey / getConfig', () {
      final s = BookSource.fromJson(f7814);
      final rt = OfflineJsBridge();
      rt.loadSource(s);
      expect(rt.containsFunction('getServerHost'), isTrue);
      expect(rt.containsFunction('getSecretKey'), isTrue);
      expect(rt.containsFunction('getConfig'), isTrue);
      expect(rt.script, contains(s.loginUrl!));
    });

    test('WebView 桥代码提供 jsLib 加载期所需的全部兜底 API', () {
      // 直接读桥源码：离线、零插件依赖，断言的是注入脚本本身
      const bridgePath = 'lib/help/source/js/legado_bridge_js.dart';
      final code = File(bridgePath).readAsStringSync() +
          extraLibrarySources(bridgePath);
      for (final api in const [
        'getJsLib:',
        'getArguments',
        'getWebViewUA:',
        'getLoginHeader:',
        'base64DecodeToByteArray:',
        'timeFormat:',
        'putMemory:',
        'getFromMemory:',
        'getCookie:',
        'setCookie:',
        'getKey:',
        'putLoginInfo:',
        'getLoginInfoMap:',
      ]) {
        expect(code, contains(api), reason: '桥脚本缺少 $api');
      }
    });
  });

  group('纯 Dart 桥 API（可离线验证的真实实现）', () {
    test('base64Encode / base64Decode / base64DecodeToByteArray', () {
      expect(JsBridgeCodec.base64Encode('abc'), 'YWJj');
      expect(JsBridgeCodec.base64Decode('YWJj'), 'abc');
      expect(JsBridgeCodec.base64DecodeToByteArray('YWJj'), [97, 98, 99]);
      final zh = JsBridgeCodec.base64Encode('斗破苍穹');
      expect(JsBridgeCodec.base64DecodeToByteArray(zh), utf8.encode('斗破苍穹'));
      expect(JsBridgeCodec.base64DecodeToByteArray('!!!'), isEmpty);
    });

    test('java.getWebViewUA', () {
      expect(JsBridgeEnv.webViewUA, contains('Mozilla'));
      expect(JsBridgeEnv.webViewUA, contains('Chrome'));
    });

    test('java.timeFormat（UTC、秒/毫秒时间戳）', () {
      expect(JsBridgeTime.timeFormat(1700000000000, 'yyyy-MM-dd HH:mm:ss', true),
          '2023-11-14 22:13:20');
      expect(JsBridgeTime.timeFormat(1700000000, 'yyyy/MM/dd', true),
          '2023/11/14');
      expect(JsBridgeTime.timeFormat(null), isEmpty);
    });

    test('cache.put/get 与 putMemory/getFromMemory（内存态不落盘）', () {
      final c = JsBridgeCache();
      c.put('userInfo', {'a': 1});
      expect(c.get('userInfo'), {'a': 1});
      c.putMemory('url', 0);
      expect(c.getFromMemory('url'), 0);
      c.putMemory('url', 1);
      expect(c.getFromMemory('url'), 1);
      expect(c.getFromMemory('missing'), isNull);
      expect(c.diskSnapshot.containsKey('url'), isFalse);
      expect(c.contains('userInfo'), isTrue);
    });

    test('cookie.setCookie / getKey / removeCookie（含域名形态）', () {
      final ck = JsBridgeCookie();
      ck.setCookie('https://x.com/a', 'qttoken=abc; uid=1');
      expect(ck.getKey('https://x.com/b', 'qttoken'), 'abc');
      ck.setCookie('fanqienovel.com', 'sessionid=xyz'); // 7814 传裸域名
      expect(ck.getKey('fanqienovel.com', 'sessionid'), 'xyz');
      expect(ck.getCookie('https://x.com/a'), contains('uid=1'));
      ck.removeCookie('https://x.com/');
      expect(ck.getCookie('x.com'), isEmpty);
    });

    test('source 变量 / 登录信息 / 登录头', () {
      final s = JsBridgeSource(url: '书山聚合');
      expect(s.getKey(), '书山聚合');
      s.setVariable({'server': 'https://a', 'n': 3});
      expect(s.getVariable('server'), 'https://a');
      expect(s.getVariable('n'), '3');
      s.putLoginInfo({'番茄登录Token': 'tk'});
      expect(s.getLoginInfoMap()['番茄登录Token'], 'tk');
      s.putLoginHeader('Authorization: Bearer x');
      expect(s.getLoginHeader(), contains('Bearer'));
    });
  });

  group('createSymmetricCrypto：AES / DES 真实实现', () {
    test('AES-128 ECB 对齐 FIPS-197 标准向量', () {
      final c = JsBridgeCrypto.createSymmetricCrypto(
          'AES', JsBridgeCodec.hexToBytes('000102030405060708090a0b0c0d0e0f'));
      final pt = JsBridgeCodec.hexToBytes('00112233445566778899aabbccddeeff');
      final ct = c.encryptBlock(pt);
      expect(JsBridgeCodec.bytesToHex(ct), '69c4e0d86a7b0430d8cdb78070b4c55a');
      expect(c.decryptBlock(ct), pt);
    });

    test('DES 对齐经典标准向量（key=133457799BBCDFF1）', () {
      final c = JsBridgeCrypto.createSymmetricCrypto(
          'DES', JsBridgeCodec.hexToBytes('133457799BBCDFF1'));
      final pt = JsBridgeCodec.hexToBytes('0123456789ABCDEF');
      final ct = c.encryptBlock(pt);
      expect(JsBridgeCodec.bytesToHex(ct), '85e813540f0ab405');
      expect(c.decryptBlock(ct), pt);
    });

    test('AES/CBC/PKCS5Padding（7814 形态）round-trip', () {
      final c = JsBridgeCrypto.createSymmetricCrypto(
          'AES/CBC/PKCS5Padding', r'G@tY3$jK7#mL2&pW8', 'C!eH4&sM6@wP9^zX1');
      const plain = '斗破苍穹·书山聚合';
      final b64 = c.encryptBase64(plain);
      // 7814 链路：java.base64DecodeToByteArray -> crypto.decryptStr(字节数组)
      final bytes = JsBridgeCodec.base64DecodeToByteArray(b64);
      expect(bytes, isNotEmpty);
      expect(c.decryptStr(bytes), plain);
    });

    test('DES/CBC/PKCS5Padding（7814 形态）round-trip', () {
      final c = JsBridgeCrypto.createSymmetricCrypto(
          'DES/CBC/PKCS5Padding', 'KW8Dvm2N', '1ae2c94b');
      const plain = '书山用户数据';
      final b64 = c.encryptBase64(plain);
      expect(c.decryptStr(JsBridgeCodec.base64DecodeToByteArray(b64)), plain);
    });

    test('AES 无 iv（7632 createSymmetricCrypto("AES", key)）round-trip', () {
      final c = JsBridgeCrypto.createSymmetricCrypto('AES', '0123456789abcdef');
      final hex = c.encryptHex('info');
      expect(c.decryptStr(hex), 'info');
    });
  });
}
