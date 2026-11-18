import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/help/source/url_guard.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await UrlGuard.instance.setEnabled(true);
    await UrlGuard.instance.setCustomDomains(<String>[]);
  });

  group('主域提取与匹配', () {
    test('www、多级子域、端口、路径均取主域+后缀', () {
      const domains = <String>['example.com'];
      expect(
          UrlGuard.instance.isBlocked('http://www.example.com', domains: domains),
          isTrue);
      expect(
          UrlGuard.instance
              .isBlocked('https://a.b.example.com:8080/path?q=1', domains: domains),
          isTrue);
      expect(
          UrlGuard.instance.isBlocked('example.com/path', domains: domains),
          isTrue);
      expect(
          UrlGuard.instance.isBlocked('https://other.com', domains: domains),
          isFalse);
    });

    test('大小写不敏感', () {
      expect(
          UrlGuard.instance.isBlocked('https://WWW.Example.COM/a',
              domains: <String>['ExAmPlE.CoM']),
          isTrue);
    });

    test('非法 URL 放行', () {
      expect(
          UrlGuard.instance.isBlocked('not a url', domains: <String>['example.com']),
          isFalse);
      expect(UrlGuard.instance.isBlocked('', domains: <String>['example.com']),
          isFalse);
      expect(
          UrlGuard.instance.isBlocked('about:blank', domains: <String>['example.com']),
          isFalse);
    });

    test('名单为空放行', () {
      expect(
          UrlGuard.instance.isBlocked('https://www.example.com',
              domains: <String>[]),
          isFalse);
    });
  });

  test('内置名单解码后可命中，且解码失败降级为空', () {
    final encoded = File('assets/url_block_list.txt').readAsStringSync().trim();
    final decoded = UrlGuard.decodeDomains(encoded);
    expect(decoded, contains('pornhub.com'));
    final domains = decoded.toList();
    expect(
        UrlGuard.instance.isBlocked('https://www.pornhub.com/view', domains: domains),
        isTrue);
    expect(
        UrlGuard.instance.isBlocked('https://www.safe-site.com', domains: domains),
        isFalse);
    expect(UrlGuard.decodeDomains('not-base64!!!'), isEmpty);
  });

  test('自定义名单命中（无需注入，直接使用合并名单）', () async {
    await UrlGuard.instance.setCustomDomains(<String>['my-block.com']);
    expect(UrlGuard.instance.isBlocked('https://sub.my-block.com/a'), isTrue);
    expect(UrlGuard.instance.isBlocked('https://www.example.com'), isFalse);
  });

  test('setCustomDomains 往返', () async {
    await UrlGuard.instance.setCustomDomains(<String>['Block-A.com', 'block-b.net']);
    expect(UrlGuard.instance.customDomains, <String>['block-a.com', 'block-b.net']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(UrlGuard.keyCustomDomains), 'block-a.com\nblock-b.net');
  });

  test('enabled=false 时恒放行', () async {
    await UrlGuard.instance.setEnabled(false);
    expect(UrlGuard.instance.enabled, isFalse);
    expect(
        UrlGuard.instance.isBlocked('https://www.pornhub.com',
            domains: <String>['pornhub.com']),
        isFalse);
    await UrlGuard.instance.setEnabled(true);
    expect(UrlGuard.instance.enabled, isTrue);
    expect(
        UrlGuard.instance.isBlocked('https://www.pornhub.com',
            domains: <String>['pornhub.com']),
        isTrue);
  });
}
