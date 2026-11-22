import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/constant/app_theme.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/help/source/source_event_callback.dart';
import 'package:legado_md3/help/source/source_extensions.dart';
import 'package:legado_md3/help/web/web_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// 书源高级服务与原生/Web 契约缺口的回归测试。
void main() {
  String read(String p) => File(p).readAsStringSync();

  group('事件常量字面值', () {
    test('分享/缓存/复制/书架刷新事件使用标准字面值', () {
      expect(SourceEventCallback.share, 'clickShareBook');
      expect(SourceEventCallback.clearCache, 'clickClearCache');
      expect(SourceEventCallback.copyBookUrl, 'clickCopyBookUrl');
      expect(SourceEventCallback.copyTocUrl, 'clickCopyTocUrl');
      expect(SourceEventCallback.copyPlayUrl, 'clickCopyPlayUrl');
      expect(SourceEventCallback.startRefreshBookshelf, 'startShelfRefresh');
      expect(SourceEventCallback.endRefreshBookshelf, 'endShelfRefresh');
      // 已经正确的常量不被改动
      expect(SourceEventCallback.addBookshelf, 'addBookShelf');
      expect(SourceEventCallback.removeBookshelf, 'delBookShelf');
      expect(SourceEventCallback.clickButton, 'clickCustomButton');
    });

    test('四个长按事件常量存在且并入 allEvents', () {
      expect(SourceEventCallback.longClickAuthor, 'longClickAuthor');
      expect(SourceEventCallback.longClickBookName, 'longClickBookName');
      expect(SourceEventCallback.longClickCustomButton, 'longClickCustomButton');
      expect(SourceEventCallback.longClickBookLabel, 'longClickBookLabel');
      for (final e in const [
        'longClickAuthor',
        'longClickBookName',
        'longClickCustomButton',
        'longClickBookLabel',
        'clickShareBook',
        'startShelfRefresh',
        'endShelfRefresh',
      ]) {
        expect(SourceEventCallback.allEvents, contains(e));
      }
    });
  });

  test('多分组书源按单个分组命中', () {
    final s = BookSource(
      bookSourceUrl: 'https://a.example',
      bookSourceName: 'A',
      bookSourceGroup: '玄幻,都市',
    );
    expect(s.extHasGroup('都市'), isTrue);
    expect(s.extHasGroup('玄幻'), isTrue);
    expect(s.extHasGroup('科幻'), isFalse);
    expect(
      read('lib/help/source/search_scope.dart'),
      contains('groups.any((g) => s.extHasGroup(g))'),
    );
  });

  group('原生桥契约', () {
    test('网络事件读取 isWifi 键并兼容 wifi', () {
      final src = read('lib/help/device/native_bridge.dart');
      expect(src, contains("m['isWifi'] ?? m['wifi']"));
    });

    test('亮度事件按 value 字段并归一化到 0-1', () {
      final src = read('lib/help/device/native_bridge.dart');
      expect(src, contains("args is Map ? args['value'] : args"));
      expect(src, contains('(v / 255.0).clamp(0.0, 1.0)'));
      expect(src, contains('systemBrightness.value = v / 255.0'));
    });
  });

  test('深链接受 yuedu scheme', () {
    final src = read('lib/common/deep_link_service.dart');
    expect(src, contains("case 'yuedu':"));
  });

  group('Web 服务契约', () {
    test('WS 升级前执行访问校验', () {
      final src = read('lib/help/web/web_service.dart');
      expect(src, contains('_wsAuthorized(request)'));
      expect(src, contains('wsHandlers.dispatch(request)!'));
    });

    test('非法 Basic 凭证按 401 处理', () {
      final src = read('lib/help/web/web_service.dart');
      expect(src, contains('String? _credentialFromAuth(String auth)'));
      expect(src, contains('Response(401'));
      expect(src, contains('Authorization 格式无效'));
    });

    test('设置密码后未授权的 WS 升级被 403 拒绝', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues(<String, Object>{
        'web_password': 'secret',
      });
      HttpOverrides.global = null;
      const port = 18611;
      final ws = WebService();
      await ws.start(port: port);
      final client = HttpClient();
      try {
        final req = await client.get('127.0.0.1', port, '/searchBook');
        req.headers
          ..set('Upgrade', 'websocket')
          ..set('Connection', 'Upgrade')
          ..set('Sec-WebSocket-Key', base64.encode(List<int>.filled(16, 1)))
          ..set('Sec-WebSocket-Version', '13');
        final resp = await req.close();
        expect(resp.statusCode, 403);
      } finally {
        client.close();
        await ws.stop();
      }
    });

    test('带正确 key 的 WS 升级仍能完成握手', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues(<String, Object>{
        'web_password': 'secret',
      });
      HttpOverrides.global = null;
      const port = 18612;
      final ws = WebService();
      await ws.start(port: port);
      WebSocketChannel? channel;
      try {
        channel = WebSocketChannel.connect(
            Uri.parse('ws://127.0.0.1:$port/bookSourceDebug?key=secret'));
        await channel.ready.timeout(const Duration(seconds: 5));
        expect(channel, isNotNull);
      } finally {
        await channel?.sink.close();
        await ws.stop();
      }
    });

    test('正文返回前套用替换规则', () {
      final src = read('lib/help/web/web_service.dart');
      expect(src, contains('ReplaceRuleService().applyRules('));
    });

    test('图片请求注入书源 UA/header/Cookie', () {
      final src = read('lib/help/web/web_service.dart');
      expect(src, contains('_sourceImageHeaders('));
      expect(src, contains("headers['User-Agent'] = AppPrefs.userAgent"));
      expect(src, contains('CookieManager().cookieHeader(imageUrl)'));
      expect(src, contains('_fetchBytes(src, headers: headers)'));
    });

    test('超时失败同样写入错误注释', () {
      final src = read('lib/help/source/check_source_service.dart');
      expect(
        RegExp(r'source\.addErrorComment\(errorMessage\)').allMatches(src).length,
        greaterThanOrEqualTo(2),
      );
    });
  });

  group('主题外观', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('越界 theme_mode 索引被夹取到合法范围，不抛 RangeError', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{'theme_mode': 999});
      final high = AppTheme();
      await high.load();
      expect(high.themeMode, ThemeMode.dark);

      SharedPreferences.setMockInitialValues(<String, Object>{'theme_mode': -3});
      final negative = AppTheme();
      await negative.load();
      expect(negative.themeMode, ThemeMode.system);

      SharedPreferences.setMockInitialValues(<String, Object>{'theme_mode': 2});
      final dark = AppTheme();
      await dark.load();
      expect(dark.themeMode, ThemeMode.dark);
    });

    test('动态取色开关真正参与配色方案', () async {
      final theme = AppTheme();
      await theme.load();
      await theme.setDynamicColor(false);
      final fixed = theme.lightTheme.colorScheme.primary;
      await theme.setDynamicColor(true);
      final dynamicScheme = theme.lightTheme.colorScheme.primary;
      expect(fixed, isNot(dynamicScheme));
    });
  });

  test('过时说明已移除', () {
    expect(
      read('lib/help/config/app_constants.dart')
          .contains('Flutter 版暂无 Android Intent.ACTION_PROCESS_TEXT'),
      isFalse,
    );
  });
}
