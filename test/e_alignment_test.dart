// 「真值 → 常量 → UI」三层链路的第三层：源码契约级分组基线。
//
// B0 的 e_placement_baseline_test.dart 校验「E 版 XML → 常量」；
// 本文件校验「常量 → 生产 UI」：各页必须由单一真源驱动、菜单锚定右上、
// 阅读页 4 按钮 / 选字 8 项、设置多级分类、发现默认视图、K 独有项隔离。
// 覆盖不便用 widget 稳定渲染的重页面（reading_screen 需 DB/章节上下文）。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/constant/e_placement.dart';

String _src(String rel) => File(rel).readAsStringSync();

/// 若目标是 part 文件（含 `part of 'xxx'`），返回其所属主库源码，
/// 因为 import 语句写在主库而非 part 里（如 bookshelf_screen_state.dart）。
String _libSourceForImports(String rel) {
  final s = _src(rel);
  final m = RegExp(r"part of\s+'([^']+)'").firstMatch(s);
  if (m == null) return s;
  final owner = Uri.file(rel).resolve(m.group(1)!).toFilePath();
  return _src(owner);
}

void main() {
  group('单一真源接线：生产 UI 必须引用 EPlacement', () {
    const pages = {
      'lib/ui/main/my/profile_screen.dart': '我的页',
      'lib/ui/config/settings_screen.dart': '设置页',
      'lib/ui/about/about_screen.dart': '关于页',
      'lib/ui/main/bookshelf/parts/bookshelf_screen_state.dart': '书架',
      'lib/ui/main/discover/discover_screen.dart': '发现',
      'lib/ui/main/subscribe/subscribe_screen.dart': '订阅',
      'lib/ui/book/read/reading_screen.dart': '阅读页',
      'lib/help/config/read_menu_config.dart': '选字菜单',
    };
    for (final entry in pages.entries) {
      test('${entry.value} 由 EPlacement 单一真源驱动', () {
        final s = _src(entry.key);
        expect(s, contains('EPlacement.'),
            reason: '${entry.value} 应引用 lib/constant/e_placement.dart');
        expect(_libSourceForImports(entry.key), contains('e_placement.dart'),
            reason: '${entry.value} 所在库应 import 单一真源');
      });
    }
  });

  group('主落点容器：锚定 AppBar 右上的 overflow（非底部 sheet）', () {
    test('书架「更多」用 EOverflowMenuButton', () {
      final s = _src('lib/ui/main/bookshelf/parts/bookshelf_screen_state.dart');
      expect(s, contains('EOverflowMenuButton('));
      expect(s, contains("EPlacement.mainMenus['bookshelf']"));
      expect(s, contains('eOverflowItemsFrom('));
    });

    test('我的页 AppBar「帮助」用 EOverflowMenuButton（main_my 仅 1 项）', () {
      final s = _src('lib/ui/main/my/profile_screen.dart');
      expect(s, contains('EOverflowMenuButton('));
      expect(s, contains("EPlacement.mainMenus['my']"));
    });

    test('阅读页 overflow 由 readOverflow 构造、K 独有项沉 secondary', () {
      final s = _src('lib/ui/book/read/reading_screen.dart');
      expect(s, contains('EPlacement.readOverflow'));
      expect(s, contains('eOverflowItemsFrom('));
      expect(s, contains('EOverflowMenuButton('));
      expect(s, contains('secondary:'),
          reason: 'K 独有扩展项应收进「更多功能」子分组');
      // 旧硬编码顺序已移除
      expect(s.contains('const _eMoreMenuOrder'), isFalse,
          reason: '不应再复用旧 15 项硬编码顺序');
    });
  });

  group('阅读页主落点：底部 4 按钮 / 选字 8 项', () {
    test('底部按钮由 readBottomButtons 驱动，恰好 4 个', () {
      final s = _src('lib/ui/book/read/reading_screen.dart');
      expect(s, contains('EPlacement.readBottomButtons'));
      // 4 个索引都引用到同一常量，保证「目录/朗读/界面/设置」
      for (final i in [0, 1, 2, 3]) {
        // 朗读用独立 _buildReadAloudAction，其余 3 个直接索引
        if (i == 1) continue;
        expect(s, contains('EPlacement.readBottomButtons[$i]'),
            reason: '底部按钮 [$i] 应由真源驱动');
      }
      expect(s.contains("'备忘'"), isTrue,
          reason: '备忘应迁到次级分区而非删除');
      expect(s, contains('kSecondary'),
          reason: '备忘迁次级应引用 EPlacement.kSecondary 语义');
    });

    test('选字菜单默认固定为 textSelectActions 8 项', () {
      final s = _src('lib/help/config/read_menu_config.dart');
      expect(s, contains('EPlacement.textSelectActions'));
      expect(s, contains('defaultSelectMenu'),
          reason: '默认选字菜单应存在且由真源派生');
      expect(
          s.contains('kExtraSelectActions') || s.contains('allSelectActions'),
          isTrue,
          reason: 'K 独有选字动作应保留在可选池，不删功能');
      expect(EPlacement.textSelectActions.length, 8);
    });

    test('顶部常驻项由 readAlways* 驱动', () {
      final s = _src('lib/ui/book/read/reading_screen.dart');
      expect(s, contains('EPlacement.readAlwaysOnline'));
      expect(s, contains('EPlacement.readAlwaysText'));
      expect(s, contains('EPlacement.readAlwaysLocal'));
    });
  });

  group('设置层级：多级分类入口 + 旧单页沉折叠（不删功能）', () {
    test('settings_screen 有分类入口页与折叠次级分区', () {
      final s = _src('lib/ui/config/settings_screen.dart');
      expect(s, contains('EPlacement.settingEntryCategories'));
      expect(s, contains('ExpansionTile('),
          reason: '旧版 17 分区应沉入默认折叠的次级分区');
      expect(s, contains('_buildAllSettingSections'),
          reason: '原全部设置项应保留可触达');
      expect(s, contains('initiallyExpanded: false'),
          reason: '次级分区应默认折叠，不占 E 主落点');
    });

    test('关于页为独立页面（about.xml 9 项），非弹窗', () {
      final s = _src('lib/ui/about/about_screen.dart');
      expect(s, contains('class AboutScreen'));
      expect(s, contains('EPlacement.aboutTop'));
      expect(s, contains('EPlacement.aboutOtherCategory'));
      expect(s.contains('degradations') || s.contains('当前平台不支持'), isTrue,
          reason: 'createHeapDump 应显式标注平台降级');
      final p = _src('lib/ui/main/my/profile_screen.dart');
      // 精确匹配方法定义，避免把「旧 _showAbout 弹窗移除」这类注释算作残留。
      expect(RegExp(r'\bvoid\s+_showAbout\s*\(').hasMatch(p), isFalse,
          reason: '旧 11 项关于弹窗方法应已移除');
      expect(p, contains('AboutScreen'));
    });
  });

  group('发现 / 订阅默认落点', () {
    test('发现页默认书源发现列表（_showFeed=false）', () {
      final s = _src('lib/ui/main/discover/discover_screen.dart');
      expect(RegExp(r'_showFeed\s*=\s*false').hasMatch(s), isTrue,
          reason: '默认视图应为书源发现列表，不是 Feed');
      expect(s, contains('homepage_feed'),
          reason: 'Feed 文件应保留不删（v14 契约依赖）');
    });

    test('订阅页由 mainMenus[rss] 4 项驱动', () {
      final s = _src('lib/ui/main/subscribe/subscribe_screen.dart');
      expect(s, contains("EPlacement.mainMenus['rss']"));
      for (final i in [0, 1, 2, 3]) {
        expect(
            s.contains("EPlacement.mainMenus['rss']![$i]") ||
                s.contains("mainMenus['rss']![$i]"),
            isTrue,
            reason: '订阅主落点 [$i] 应由真源驱动');
      }
    });
  });

  group('K 独有功能「按语义归位」（不删、E 主落点顺序不变）', () {
    test('profile 保留全部独有类名并按语义平铺分区归位', () {
      final s = _src('lib/ui/main/my/profile_screen.dart');
      for (final cls in const [
        'AutoTaskScreen', 'HomepageModuleScreen', 'DownloadManageScreen',
        'CloudTtsScreen', 'ReadingStatsScreen', 'AiChatScreen',
        'AgentToolScreen', 'WelcomeConfigScreen', 'AppIconScreen',
        'VideoSettingScreen',
      ]) {
        expect(s, contains(cls), reason: '独有功能 $cls 不应被删');
      }
      // 用户反馈「我的页太丑、把更多功能里的功能调到较适合的位置」：
      // 由「单个默认折叠的更多功能」改为按语义平铺的分区卡片；再按
      // 「有些功能很类似」把相似项聚合为 4 组，仍位于 E 主落点之后，功能一项不删。
      expect(s, contains('_buildFeatureSections'));
      expect(s, contains('_sectionCard'));
      for (final t in const [
        '设置与外观', '阅读与内容', '视听与 AI', '关于与项目',
      ]) {
        expect(s, contains(t), reason: '缺少相似度聚合分区 $t');
      }
      // 重复入口去重：「GitHub项目」与「评分」不再跳同一个 URL
      expect(s, contains('app_rating'));
    });

    test('EPlacement.kSecondary 覆盖各页独有项且降级清单完整', () {
      expect(EPlacement.kSecondary.containsKey('profile'), isTrue);
      expect(EPlacement.kSecondary.containsKey('discover'), isTrue);
      expect(EPlacement.kSecondary.containsKey('subscribe'), isTrue);
      expect(EPlacement.kSecondary.containsKey('reading'), isTrue);
      expect(EPlacement.kSecondary['reading_secondary_button'], ['备忘']);
      for (final key in const [
        'android:visible=false', 'PreferenceScreen 多级 Category',
        'showAsAction=always/never', 'android:checkable',
      ]) {
        expect(EPlacement.degradations.containsKey(key), isTrue,
            reason: '降级清单缺：$key');
      }
    });
  });
}
