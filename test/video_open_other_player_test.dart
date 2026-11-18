import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/ui/book/video/video_player_screen.dart'
    show parsePlayUrl, resolveCurrentPlayUrl;

/// 视频页 Overflow「其它播放器打开」的静态契约 + 纯函数单测。
/// canLaunchUrl / launchUrl 为平台调用，难以在单元测试中 mock，
/// 故以源码契约锁定接入方式，并对待测逻辑抽出的纯函数做覆盖。
void main() {
  group('源码契约', () {
    test('视频页菜单项与外部分发齐全', () {
      final src = File('lib/ui/book/video/parts/video_player_screen_state.dart')
          .readAsStringSync();
      expect(src, contains('其它播放器打开'));
      expect(src, contains("v == 'openOtherPlayer'"));
      expect(src, contains('_openInOtherPlayer()'));
      expect(src, contains('canLaunchUrl(uri)'));
      expect(src, contains('LaunchMode.externalApplication'));
      // 无地址 / 无播放器 / 非法地址三类提示
      expect(src, contains('暂无播放地址'));
      expect(src, contains('没有可用的播放器'));
      expect(src, contains('播放地址无效'));
    });

    test('音频页同样提供同名外部打开入口', () {
      final src =
          File('lib/ui/book/audio/audio_player_screen.dart').readAsStringSync();
      expect(src, contains('其它播放器打开'));
      expect(src, contains("case 'openOtherPlayer':"));
      expect(src, contains('canLaunchUrl(uri)'));
      expect(src, contains('LaunchMode.externalApplication'));
    });
  });

  group('resolveCurrentPlayUrl', () {
    test('空线路列表返回空串', () {
      expect(resolveCurrentPlayUrl(const [], 0), isEmpty);
    });

    test('按当前线路索引取地址并去首尾空白', () {
      expect(
        resolveCurrentPlayUrl(
            [' https://a.example/v.mp4 ', 'https://b.example/v.m3u8'], 1),
        'https://b.example/v.m3u8',
      );
    });

    test('索引越界时钳制到末条', () {
      expect(
        resolveCurrentPlayUrl(['https://a.example/v.mp4'], 99),
        'https://a.example/v.mp4',
      );
    });
  });

  group('parsePlayUrl', () {
    test('合法地址解析为带 scheme 与 host 的 Uri', () {
      final uri = parsePlayUrl('https://example.com/v.mp4');
      expect(uri, isNotNull);
      expect(uri!.scheme, 'https');
      expect(uri.host, 'example.com');
    });

    test('首尾空白不影响解析', () {
      final uri = parsePlayUrl('  https://example.com/a.m3u8  ');
      expect(uri, isNotNull);
      expect(uri!.path, '/a.m3u8');
    });

    test('非法地址返回 null 而不抛异常', () {
      expect(parsePlayUrl('http://[::1'), isNull);
    });
  });
}
