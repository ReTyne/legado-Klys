import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/help/config/app_config.dart';

/// 功能1~3 的小功能回归测试。
/// - 偏好键值往返/钳制：直接走 AppPrefs 真实逻辑（纯 Dart）。
/// - 复制地址分支、各菜单项集合：UI/平台通道相关，用源码静态契约断言。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('功能1：背景图模糊度偏好键值', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('键名符合约定，默认值为 0', () async {
      final prefs = await SharedPreferences.getInstance();
      AppPrefs.loadFrom(prefs);
      expect(AppPrefs.keyBackgroundImageBlurring, 'backgroundImageBlurring');
      expect(AppPrefs.keyBackgroundImageNightBlurring,
          'backgroundImageNightBlurring');
      expect(AppPrefs.backgroundImageBlurring, 0);
      expect(AppPrefs.backgroundImageNightBlurring, 0);
    });

    test('setter 设置后落盘，loadFrom 往返一致', () async {
      final prefs = await SharedPreferences.getInstance();
      AppPrefs.loadFrom(prefs);
      AppPrefs.backgroundImageBlurring = 8;
      AppPrefs.backgroundImageNightBlurring = 17;

      final p2 = await SharedPreferences.getInstance();
      expect(p2.getInt('backgroundImageBlurring'), 8);
      expect(p2.getInt('backgroundImageNightBlurring'), 17);

      AppPrefs.loadFrom(p2);
      expect(AppPrefs.backgroundImageBlurring, 8);
      expect(AppPrefs.backgroundImageNightBlurring, 17);
    });

    test('setter 把越界值钳制到 0~25', () async {
      final prefs = await SharedPreferences.getInstance();
      AppPrefs.loadFrom(prefs);
      AppPrefs.backgroundImageBlurring = 99;
      AppPrefs.backgroundImageNightBlurring = -5;
      expect(AppPrefs.backgroundImageBlurring, 25);
      expect(AppPrefs.backgroundImageNightBlurring, 0);
    });

    test('loadFrom 对已持久化的越界值同样钳制', () async {
      SharedPreferences.setMockInitialValues({
        'backgroundImageBlurring': 1000,
        'backgroundImageNightBlurring': -7,
      });
      final prefs = await SharedPreferences.getInstance();
      AppPrefs.loadFrom(prefs);
      expect(AppPrefs.backgroundImageBlurring, 25);
      expect(AppPrefs.backgroundImageNightBlurring, 0);
    });

    test('渲染侧按明暗模式取对应键并套 ImageFiltered、0 不套', () {
      final shelf =
          File('lib/ui/main/bookshelf/parts/bookshelf_screen_state.dart')
              .readAsStringSync();
      expect(shelf.contains('backgroundImageNightBlurring'), isTrue);
      expect(shelf.contains('backgroundImageBlurring'), isTrue);
      expect(shelf.contains('ui.ImageFilter.blur'), isTrue);
      expect(shelf.contains('if (blurring > 0)'), isTrue);

      final reader = File('lib/ui/book/read/reading_screen.dart').readAsStringSync();
      expect(reader.contains('AppPrefs.backgroundImageNightBlurring'), isTrue);
      expect(reader.contains('AppPrefs.backgroundImageBlurring'), isTrue);
      expect(reader.contains('if (blurring <= 0) return child;'), isTrue);
    });

    test('主题管理页含日间/夜间两个模糊强度滑杆', () {
      final src = File('lib/ui/config/parts/theme_manage_screen_state.dart')
          .readAsStringSync();
      expect(src.contains('日间模糊强度'), isTrue);
      expect(src.contains('夜间模糊强度'), isTrue);
      expect(src.contains('AppPrefs.backgroundImageBlurring = v'), isTrue);
      expect(src.contains('AppPrefs.backgroundImageNightBlurring = v'), isTrue);
      expect(src.contains('max: 25'), isTrue);
    });
  });

  group('功能2：复制播放地址', () {
    test('音频页含复制分支：取当前 URL、Clipboard 写入、SnackBar 与空值提示', () {
      final src = File('lib/ui/book/audio/audio_player_screen.dart')
          .readAsStringSync();
      expect(src.contains("import 'package:flutter/services.dart';"), isTrue);
      expect(src.contains('Clipboard.setData(ClipboardData(text: url))'), isTrue);
      expect(src.contains("'已复制播放地址'"), isTrue);
      expect(src.contains("'暂无播放地址'"), isTrue);
      expect(src.contains("if (_segments.isEmpty) return '';"), isTrue);
      expect(src.contains("case 'copyUrl':"), isTrue);
    });

    test('视频页含复制分支：取当前行地址、Clipboard 写入、SnackBar 与空值提示', () {
      final src = File('lib/ui/book/video/parts/video_player_screen_state.dart')
          .readAsStringSync();
      expect(src.contains('Clipboard.setData(ClipboardData(text: url))'), isTrue);
      expect(src.contains("'已复制播放地址'"), isTrue);
      expect(src.contains("'暂无播放地址'"), isTrue);
      expect(src.contains('resolveCurrentPlayUrl'), isTrue);
      expect(src.contains("if (lines.isEmpty) return '';"), isTrue);
      expect(src.contains("if (v == 'copyUrl') await _copyPlayUrl();"), isTrue);
    });

    test('音频菜单项集合：倍速/跳过/悬浮窗/复制地址', () {
      final src = File('lib/ui/book/audio/audio_player_screen.dart')
          .readAsStringSync();
      for (final label in ['播放倍速', '跳过片头片尾', '迷你悬浮窗', '复制播放地址']) {
        expect(src.contains(label), isTrue, reason: '缺少音频菜单项：$label');
      }
    });

    test('视频菜单项集合：含复制播放地址', () {
      final src = File('lib/ui/book/video/parts/video_player_screen_state.dart')
          .readAsStringSync();
      expect(src.contains("PopupMenuItem(value: 'copyUrl'"), isTrue);
      expect(src.contains('复制播放地址'), isTrue);
    });
  });

  group('功能3：正文图片长按菜单', () {
    test('正文加长按手势并含四项菜单', () {
      final src = File('lib/ui/book/read/reading_screen.dart').readAsStringSync();
      expect(src.contains('onLongPress: _onContentLongPress'), isTrue);
      for (final label in ['显示大图', '刷新图片', '保存图片', '选择保存文件夹']) {
        expect(src.contains("'$label'"), isTrue, reason: '缺少菜单项：$label');
      }
    });

    test('四项动作均有真实实现（大图/清缓存/下载落盘/选目录）', () {
      final src = File('lib/ui/book/read/reading_screen.dart').readAsStringSync();
      expect(src.contains('InteractiveViewer('), isTrue); // 显示大图
      expect(src.contains('PaintingBinding.instance.imageCache.clear()'), isTrue);
      expect(src.contains('PaintingBinding.instance.imageCache.clearLiveImages()'), isTrue);
      expect(src.contains('Dio().get<List<int>>('), isTrue); // 保存图片
      expect(src.contains('FilePicker.platform.getDirectoryPath('), isTrue); // 选文件夹
    });

    test('近似实现有如实说明（正文纯文本、页级近似）', () {
      final src = File('lib/ui/book/read/reading_screen.dart').readAsStringSync();
      expect(src.contains('页级近似'), isTrue);
      expect(src.contains('纯文本'), isTrue);
    });
  });
}
