import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/help/source/source_network_log.dart';
import 'package:legado_md3/help/source/source_server_probe.dart';

/// 登录诊断 / 调试源码可读化的离线回归：
/// * 7632 的备用服务器列表写在 jsLib 的 `var host = [...]`，需正确提取；
/// * 用户在调试页看到的 `7b2274...` 是 hex 中间产物，应自动解码；
/// * 网络日志能区分成功 / 5xx / 本地失败，供登录页给出切换提示。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  BookSource load7632() {
    final raw = File('test/fixtures/source_7632.json').readAsStringSync();
    return BookSource.fromJson(
        (jsonDecode(raw) as Map<String, dynamic>).cast<String, dynamic>());
  }

  group('聚合源备用服务器提取', () {
    test('7632 从 jsLib 提取内置 host 列表', () {
      final hosts = SourceServerProbe.extractHosts(load7632());
      expect(hosts, isNotEmpty);
      expect(hosts.first, 'https://v5.langge.uk');
      expect(hosts.length, greaterThanOrEqualTo(5));
      expect(hosts.every((h) => h.startsWith('http')), isTrue);
      expect(hosts.toSet().length, hosts.length, reason: 'host 不应重复');
    });

    test('无 jsLib 时返回空列表而不是抛错', () {
      final s = BookSource.fromJson(const {
        'bookSourceName': 'test',
        'bookSourceUrl': 'https://example.com',
      });
      expect(SourceServerProbe.extractHosts(s), isEmpty);
    });
  });

  group('调试源码可读化', () {
    test('用户提供的 hex 中间产物被解码为原始 JSON', () {
      const hex = '7b22746162223a22e5b08fe8afb4222c2275726c223a22227d';
      final view = SourceNetworkLog.readable(hex);
      expect(view.text, contains('"tab"'));
      expect(view.text, contains('小说'));
      expect(view.note, contains('hex'));
      // 解码后的内容可被 JSON 解析（详情页能看清到底传了什么）
      expect(() => jsonDecode(view.text), returnsNormally);
    });

    test('合法 JSON 自动缩进美化', () {
      final view = SourceNetworkLog.readable('{"a":1,"b":[2,3]}');
      expect(view.text, contains('\n'));
      expect(view.note, contains('JSON'));
    });

    test('普通 HTML 原样返回', () {
      final view = SourceNetworkLog.readable('<html><body>hi</body></html>');
      expect(view.text, '<html><body>hi</body></html>');
      expect(view.note, isNull);
    });
  });

  group('网络请求日志', () {
    setUp(() {
      SourceNetworkLog.instance.clear();
      SourceNetworkLog.instance.clearScriptErrors();
    });

    test('记录成功 / 5xx / 本地失败并定位最近失败', () {
      final log = SourceNetworkLog.instance;
      log.record(
          url: 'https://v5.langge.uk/user_api',
          method: 'GET',
          origin: 'js-ajax',
          statusCode: 200,
          text: '{"code":0}');
      expect(log.last!.ok, isTrue);
      expect(log.lastFailure, isNull);

      log.record(
          url: 'https://v5.langge.uk/login_api',
          method: 'POST',
          origin: 'js-ajax',
          statusCode: 502,
          error: 'HTTP 502');
      expect(log.lastFailure!.statusCode, 502);
      expect(log.lastFailure!.url, contains('login_api'));

      log.record(
          url: 'https://v8.langge.uk/user_api',
          method: 'GET',
          origin: 'js-ajax',
          statusCode: 502,
          error: '请求失败: SocketException: Failed host lookup');
      expect(log.lastFailure!.error, contains('host lookup'));
      expect(log.entries.length, 3);
    });

    test('脚本加载错误可查询', () {
      SourceNetworkLog.instance
          .addScriptError('loginUrl（登录脚本）加载失败: SyntaxError');
      expect(SourceNetworkLog.instance.scriptErrors.single,
          contains('loginUrl'));
    });
  });
}
