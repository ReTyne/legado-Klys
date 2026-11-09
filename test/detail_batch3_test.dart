import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/data/model/read_config.dart';
import 'package:legado_md3/ui/book/read/read_detail_utils.dart';

String src(String p) => File(p).readAsStringSync();

void main() {
  group('批次 3 · 边距过大回退（对齐 ChapterProvider.setFallbackLayout）', () {
    test('正常边距不回退，返回原边距与可视区', () {
      final p = resolveReadPadding(
        viewWidth: 360, viewHeight: 800,
        left: 16, top: 8, right: 16, bottom: 8,
      );
      expect(p.fellBack, isFalse);
      expect(p.left, 16);
      expect(p.top, 8);
      expect(p.right, 16);
      expect(p.bottom, 8);
      expect(p.visibleWidth, 328);
      expect(p.visibleHeight, 784);
    });

    test('左右边距之和超过屏宽触发回退 20/5/20/5', () {
      final p = resolveReadPadding(
        viewWidth: 360, viewHeight: 800,
        left: 200, top: 8, right: 200, bottom: 8,
      );
      expect(p.fellBack, isTrue);
      expect(p.left, 20);
      expect(p.top, 5);
      expect(p.right, 20);
      expect(p.bottom, 5);
      expect(p.visibleWidth, 320);
      expect(p.visibleHeight, 790);
    });

    test('上下边距之和超过屏高也触发回退（top >= viewHeight-bottom）', () {
      final p = resolveReadPadding(
        viewWidth: 360, viewHeight: 100,
        left: 16, top: 60, right: 16, bottom: 60,
      );
      expect(p.fellBack, isTrue);
      expect(p.top, 5);
      expect(p.bottom, 5);
    });

    test('双页模式可视宽按上游 viewWidth/2 计算', () {
      final p = resolveReadPadding(
        viewWidth: 800, viewHeight: 600,
        left: 16, top: 8, right: 16, bottom: 8,
        doublePage: true,
      );
      expect(p.fellBack, isFalse);
      expect(p.visibleWidth, 368);
    });

    test('0 宽高首帧不误判为边距过大（对齐 upViewSize 早退）', () {
      final p = resolveReadPadding(
        viewWidth: 0, viewHeight: 0,
        left: 16, top: 8, right: 16, bottom: 8,
      );
      expect(p.fellBack, isFalse);
      expect(p.left, 16);
      expect(p.visibleWidth, 0);
    });
  });

  group('批次 3 · 最小背光 / 尺寸防抖 / 点击状态机', () {
    test('minBacklight：0 抬到 0.004，正常值原样返回', () {
      expect(minBacklight(0.0), 0.004);
      expect(minBacklight(0.002), 0.004); // 低于 1/255
      expect(minBacklight(0.9), 0.9);
      expect(minBacklight(0.01), 0.01);
    });

    test('classifyViewSizeChange：首次/宽度变/仅高度变/回到原值', () {
      expect(
          classifyViewSizeChange(
              oldW: null, oldH: null, newW: 400, newH: 800),
          ViewSizeChange.immediate);
      expect(
          classifyViewSizeChange(
              oldW: 400, oldH: 800, newW: 410, newH: 800),
          ViewSizeChange.immediate);
      expect(
          classifyViewSizeChange(
              oldW: 400, oldH: 800, newW: 400, newH: 700),
          ViewSizeChange.debounced);
      expect(
          classifyViewSizeChange(
              oldW: 400, oldH: 800, newW: 400, newH: 800),
          ViewSizeChange.none);
      expect(viewSizeDebounceMs, 300);
    });

    test('ClickTracker：300ms 防抖 + 双击态翻转', () {
      final t = ClickTracker();
      final r1 = t.onTap(1000);
      expect(r1.debounced, isFalse);
      expect(r1.doubleClick, isFalse);
      final r2 = t.onTap(1200); // 200ms < 300
      expect(r2.debounced, isTrue);
      expect(r2.doubleClick, isTrue);
      expect(t.onTap(1400).doubleClick, isFalse); // 连续第三次翻转回来
      final r5 = t.onTap(2000); // 超过 300ms 重置
      expect(r5.debounced, isFalse);
      expect(r5.doubleClick, isFalse);

      final short = ClickTracker(windowMs: 100);
      short.onTap(1000);
      expect(short.onTap(1050).debounced, isTrue);
      expect(short.onTap(1200).debounced, isFalse);
    });

    test('字体路径校验与系统字体映射', () {
      expect(isFontFilePath('衬线体'), isFalse);
      expect(isFontFilePath('/sdcard/fonts/a.ttf'), isTrue);
      expect(isFontFilePath('b.otf'), isTrue);
      expect(fontPathExists('衬线体'), isTrue); // 非路径不校验
      expect(fontPathExists('/definitely/not/exist_font_batch3.ttf'), isFalse);
      expect(systemFontFamily(0), isNull);
      expect(systemFontFamily(1), 'serif');
      expect(systemFontFamily(2), 'monospace');
      expect(clickImgWayLabels.length, 5);
    });
  });

  group('批次 3 · 日/夜/墨水屏三套独立配置（ReadConfig）', () {
    test('cur* getter 按 readThemeMode 选取三套各自的值', () {
      final c = ReadConfig();
      expect(c.readThemeMode, 0);
      expect(c.curBgColor, 0xFFFFF8E1);
      expect(c.curTextColor, 0xFF333333);
      expect(c.curTextAccentColor, 0xFFE53935);
      expect(c.curStatusIconDark, isTrue);
      expect(c.curPageAnim, 0);

      c.readThemeMode = 1; // 夜间
      expect(c.curBgColor, 0xFF000000);
      expect(c.curTextColor, 0xFFADADAD);
      expect(c.curTextAccentColor, 0xFFFE4D55);
      expect(c.curStatusIconDark, isFalse);
      expect(c.curPageAnim, 0); // 夜间仍用 pageAnim

      c.readThemeMode = 2; // 墨水屏
      expect(c.curBgColor, 0xFFFFFFFF);
      expect(c.curTextColor, 0xFF000000);
      expect(c.curTextAccentColor, 0xFF000000);
      expect(c.curStatusIconDark, isTrue);
      expect(c.curPageAnim, 4); // pageAnimEInk 默认无动画
    });

    test('setCur* 只写当前模式那份，不覆盖其它模式', () {
      final c = ReadConfig()..readThemeMode = 1; // 夜间
      c.setCurBgColor(0xFF112233);
      c.setCurTextColor(0xFF445566);
      c.setCurTextAccentColor(0xFF778899);
      c.setCurStatusIconDark(true);
      c.setCurPageAnim(3); // 夜间写 pageAnim
      expect(c.bgColorNight, 0xFF112233);
      expect(c.textColorNight, 0xFF445566);
      expect(c.textAccentColorNight, 0xFF778899);
      expect(c.darkStatusIconNight, isTrue);
      expect(c.pageAnim, 3);
      // 白天那份完全不受影响
      expect(c.bgColor, 0xFFFFF8E1);
      expect(c.textColor, 0xFF333333);
      expect(c.textAccentColor, 0xFFE53935);
      expect(c.darkStatusIcon, isTrue);
      expect(c.pageAnimEInk, 4);

      c.readThemeMode = 2; // 墨水屏写 pageAnimEInk
      c.setCurPageAnim(5);
      expect(c.pageAnimEInk, 5);
      expect(c.pageAnim, 3); // 夜间那份未被覆盖
    });

    test('toJson/fromJson 往返保留全部批次 3 新字段与批次 1 keepLight', () {
      final c = ReadConfig(
        readThemeMode: 2,
        textAccentColor: 0xFFABCDEF,
        darkStatusIcon: false,
        bgColorNight: 0xFF111111,
        textColorNight: 0xFF222222,
        textAccentColorNight: 0xFF333333,
        darkStatusIconNight: true,
        bgColorEInk: 0xFF444444,
        textColorEInk: 0xFF555555,
        textAccentColorEInk: 0xFF666666,
        darkStatusIconEInk: false,
        pageAnimEInk: 2,
        systemTypefaces: 2,
        contentSelectSpeakMod: 1,
        showAddToShelfAlert: false,
        keepLight: 300,
      );
      final r = ReadConfig.fromJsonString(c.toJsonString());
      expect(r.readThemeMode, 2);
      expect(r.textAccentColor, 0xFFABCDEF);
      expect(r.darkStatusIcon, isFalse);
      expect(r.bgColorNight, 0xFF111111);
      expect(r.textColorNight, 0xFF222222);
      expect(r.textAccentColorNight, 0xFF333333);
      expect(r.darkStatusIconNight, isTrue);
      expect(r.bgColorEInk, 0xFF444444);
      expect(r.textColorEInk, 0xFF555555);
      expect(r.textAccentColorEInk, 0xFF666666);
      expect(r.darkStatusIconEInk, isFalse);
      expect(r.pageAnimEInk, 2);
      expect(r.systemTypefaces, 2);
      expect(r.contentSelectSpeakMod, 1);
      expect(r.showAddToShelfAlert, isFalse);
      expect(r.keepLight, 300); // 批次 1 改动未被回退
    });

    test('fromJson 越界值钳回合法域、兼容数字字符串', () {
      final r = ReadConfig.fromJson({
        'readThemeMode': 99,
        'pageAnimEInk': -3,
        'systemTypefaces': 7,
        'contentSelectSpeakMod': 5,
      });
      expect(r.readThemeMode, 2);
      expect(r.pageAnimEInk, 0);
      expect(r.systemTypefaces, 2);
      expect(r.contentSelectSpeakMod, 1);
      final s = ReadConfig.fromJson({
        'readThemeMode': '1',
        'pageAnimEInk': '3',
      });
      expect(s.readThemeMode, 1);
      expect(s.pageAnimEInk, 3);
    });

    test('空配置缺省值与上游一致（含批次 1 默认值）', () {
      final d = ReadConfig.fromJson({});
      expect(d.readThemeMode, 0);
      expect(d.pageAnimEInk, 4);
      expect(d.bgColorNight, 0xFF000000);
      expect(d.textColorNight, 0xFFADADAD);
      expect(d.bgColorEInk, 0xFFFFFFFF);
      expect(d.textColorEInk, 0xFF000000);
      expect(d.darkStatusIcon, isTrue);
      expect(d.darkStatusIconNight, isFalse);
      expect(d.darkStatusIconEInk, isTrue);
      expect(d.showAddToShelfAlert, isTrue);
      expect(d.systemTypefaces, 0);
      expect(d.contentSelectSpeakMod, 0);
      expect(d.keepLight, 0);
    });
  });

  group('批次 3 · 源码接线契约（避免只写不读的假开关）', () {
    test('ReadConfig 暴露三套字段与 cur* 选择器', () {
      final s = src('lib/data/model/read_config.dart');
      expect(s, contains('int get curBgColor'));
      expect(s, contains('int get curTextColor'));
      expect(s, contains('int get curTextAccentColor'));
      expect(s, contains('bool get curStatusIconDark'));
      expect(s, contains('int get curPageAnim'));
      expect(s, contains('void setCurBgColor(int color)'));
      expect(s, contains('void setCurTextColor(int color)'));
      expect(s, contains('void setCurPageAnim(int anim)'));
      expect(s, contains("'pageAnimEInk': pageAnimEInk"));
      expect(s, contains("'readThemeMode': readThemeMode"));
      expect(s, contains("'keepLight': keepLight")); // 批次 1 保留
    });

    test('reading_screen 真实消费三套配色/动画', () {
      final s = src('lib/ui/book/read/reading_screen.dart');
      expect(s, contains('statusBarColor: Color(config.curBgColor)'));
      expect(s, contains('config.curStatusIconDark ? Brightness.dark'));
      expect(s, contains('Color(config.curTextAccentColor)'));
      expect(s, contains('config.curPageAnim == 4'));
      expect(s, contains('readProvider.config.curPageAnim'));
      expect(s, contains('c.setCurBgColor(bg)'));
    });

    test('reading_screen 真实消费极端值容错四件套', () {
      final s = src('lib/ui/book/read/reading_screen.dart');
      expect(s, contains('resolveReadPadding(')); // 边距回退
      expect(s, contains('minBacklight(value.clamp(0.0, 1.0))')); // 最小背光
      expect(s, contains('_validateFontFamily(cfg)')); // 字体坏路径
      expect(s, contains('systemFontFamily(config.systemTypefaces)'));
      expect(s, contains('classifyViewSizeChange(')); // 尺寸防抖
      expect(s, contains('viewSizeDebounceMs'));
      expect(s, contains('setFallbackLayout')); // 上游标注
    });

    test('reading_screen 真实消费点击状态机/选择菜单/退出提示/5分钟备份', () {
      final s = src('lib/ui/book/read/reading_screen.dart');
      expect(s, contains('final ClickTracker _clickTracker = ClickTracker()'));
      expect(s, contains('_clickTracker.onTap('));
      expect(s, contains('const visibleCount = 5')); // 折叠前 5 项
      expect(s, contains("Text('更多')"));
      expect(s, contains('contentSelectSpeakMod')); // 长按切朗读模式
      expect(s, contains('_inBookshelf == false && config.showAddToShelfAlert'));
      expect(s, contains('加入书架'));
      expect(s, contains('Timer(const Duration(minutes: 5)'));
      expect(s, contains('BackupService.runAutoBackup()'));
      expect(s, contains('_startAutoBackupJob()'));
    });

    test('设置页接线三模式切换与各独立配置', () {
      final s = src('lib/ui/book/read/config/reading_settings_screen.dart');
      expect(s, contains('SegmentedButton<int>'));
      expect(s, contains('c.readThemeMode = s.first'));
      expect(s, contains('c.setCurTextColor(color.value)'));
      expect(s, contains('c.setCurBgColor(color.value)'));
      expect(s, contains('c.setCurTextAccentColor(color.value)'));
      expect(s, contains('c.setCurStatusIconDark(v)'));
      expect(s, contains('c.pageAnimEInk = v ?? 4'));
      expect(s, contains('c.systemTypefaces = v ?? 0'));
      expect(s, contains('c.showAddToShelfAlert = v'));
      expect(s, contains('clickImgWayLabels')); // 图片点击 5 档
    });

    test('纯函数工具带上游行号证据', () {
      final s = src('lib/ui/book/read/read_detail_utils.dart');
      expect(s, contains('setFallbackLayout'));
      expect(s, contains('0.004'));
      expect(s, contains('handler.postDelayed(300)'));
      expect(s, contains('ContentTextView.kt:245-253'));
      expect(s, contains('ChapterProvider.kt:328-374'));
    });
  });
}
