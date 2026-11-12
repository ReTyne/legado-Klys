// 菜单常量回归：校验「定义 → 常量 → 界面」链路中的常量层。
//
// 两类断言：
//  A. 常量自检（始终运行）——防止菜单常量被改坏而无人发现；
//  B. XML 定义交叉校验（定义源存在时运行；不存在则 skip 并显式打印，不静默通过）。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/constant/e_placement.dart';

final bool _eAvailable = Directory(EPlacement.eSourceRoot).existsSync();
String _res(String sub) => '${EPlacement.eSourceRoot}/$sub';

/// 提取 menu/*.xml 中所有 <item> 的 android:id（按顺序，跳过 <group>）。
List<String> _menuIds(String file) {
  final s = File(file).readAsStringSync();
  final ids = <String>[];
  // 只取 <item ...> 开标签，避免把 <group android:id> 算进来。
  for (final m in RegExp(r'<item\b[^>]*>', dotAll: true).allMatches(s)) {
    final id = RegExp(r'android:id="@\+id/(\w+)"').firstMatch(m.group(0)!);
    if (id != null) ids.add(id.group(1)!);
  }
  return ids;
}

/// 提取 preference/*.xml 中所有 **Preference 项** 的 android:key（按顺序）。
/// 注意：部分 PreferenceCategory 自身带 android:key（如 pref_main 的
/// `aboutCategory`、主题/封面/欢迎页的 `dayThemeCategory`/`nightThemeCategory`），
/// 根 PreferenceScreen 也可能带 key —— 这些属于「分组/容器」而非设置项，
/// 必须按标签块解析并跳过，否则会把分组 key 误当成设置项。
List<String> _prefKeys(String file) {
  final s = File(file).readAsStringSync();
  final keys = <String>[];
  // 逐个 XML 标签块（从 '<tag' 到 '>'），只对「非 Category/Screen」的标签取 key。
  for (final m in RegExp(r'<([A-Za-z_][\w.]*)\b[^>]*>', dotAll: true)
      .allMatches(s)) {
    final tagName = m.group(1)!;
    if (tagName.endsWith('PreferenceCategory') ||
        tagName.endsWith('PreferenceScreen')) {
      continue;
    }
    final id = RegExp(r'android:key="([^"]+)"').firstMatch(m.group(0)!);
    if (id != null) keys.add(id.group(1)!);
  }
  return keys;
}

/// settingConfigKeys 中去掉 `|category` 分类标记后剩下的纯 key 列表。
List<String> _configKeys(List<String> src) =>
    src.where((k) => !k.startsWith('|')).toList();

List<String> _ids(List<EMenuItem> items) => items.map((e) => e.id).toList();

void main() {
  // ── A. 常量自检（始终运行）──────────────────────────────────────────
  group('A · 单一真源常量自检', () {
    test('底部导航恰好 4 tab 且顺序固定', () {
      expect(_ids(EPlacement.tabs),
          ['menu_bookshelf', 'menu_discovery', 'menu_rss', 'menu_my_config']);
    });

    test('mainMenus 覆盖 4 个 tab，书架 12 项（1 常驻 + 11 overflow）', () {
      expect(EPlacement.mainMenus.keys.toSet(),
          {'bookshelf', 'explore', 'rss', 'my'});
      final bs = EPlacement.mainMenus['bookshelf']!;
      expect(bs.length, 12);
      expect(bs.first.id, 'menu_search');
      expect(bs.where((e) => e.always).length, 1);
      expect(bs.where((e) => e.overflow).length, 11);
    });

    test('发现/订阅/我的 tab 菜单项数与 always 语义', () {
      expect(EPlacement.mainMenus['explore']!.length, 1);
      expect(EPlacement.mainMenus['rss']!.length, 4);
      expect(EPlacement.mainMenus['rss']!.every((e) => e.always), isTrue);
      expect(EPlacement.mainMenus['my']!.length, 1);
      expect(EPlacement.mainMenus['my']!.first.id, 'menu_help');
    });

    test('pref_main 恰好 14 项，两个分类标题', () {
      expect(EPlacement.myAll.length, 14);
      expect(EPlacement.myTop.length, 6);
      expect(EPlacement.mySettingCategory.length, 3);
      expect(EPlacement.myOtherCategory.length, 5);
      expect(EPlacement.myCategoryTitles, ['设置', '其它']);
    });

    test('关于页 9 项（3 顶层 + 6 其它）', () {
      expect(EPlacement.aboutAll.length, 9);
      expect(EPlacement.aboutTop.length, 3);
      expect(EPlacement.aboutOtherCategory.length, 6);
    });

    test('阅读页常驻：在线 3 / 本地 TXT 1(隐藏) / 本地 1', () {
      expect(EPlacement.readAlwaysOnline.length, 3);
      expect(EPlacement.readAlwaysText.length, 1);
      expect(EPlacement.readAlwaysText.first.visibleByDefault, isFalse,
          reason: 'menu_toc_regex 上游 visible=false，默认不渲染');
      expect(EPlacement.readAlwaysLocal.length, 1);
    });

    test('阅读页 overflow 含 3 个 visible=false 项、6 个 checkable 项', () {
      final hidden = EPlacement.readOverflow
          .where((e) => !e.visibleByDefault)
          .map((e) => e.id)
          .toList();
      expect(hidden, [
        'menu_get_progress',
        'menu_cover_progress',
        'menu_enable_review',
      ]);
      expect(EPlacement.readOverflow.where((e) => e.checkable).length, 6);
      expect(
          EPlacement.readOverflow
              .firstWhere((e) => e.id == 'menu_enable_replace')
              .checkedByDefault,
          isTrue,
          reason: 'menu_enable_replace 上游 checked=true');
    });

    test('阅读页底部恰好 4 按钮且顺序为 目录/朗读/界面/设置', () {
      expect(EPlacement.readBottomButtons.length, 4);
      expect(_ids(EPlacement.readBottomButtons),
          ['ll_catalog', 'll_read_aloud', 'll_font', 'll_setting']);
    });

    test('选字菜单恰好 8 项且顺序固定', () {
      expect(_ids(EPlacement.textSelectActions), [
        'menu_replace', 'menu_copy', 'menu_bookmark', 'menu_aloud',
        'menu_dict', 'menu_search_content', 'menu_browser', 'menu_share_str',
      ]);
    });

    test('设置分类树：入口 3 分类，各子页 key 列表非空', () {
      expect(EPlacement.settingEntryCategories.length, 3);
      for (final entry in EPlacement.settingConfigKeys.entries) {
        expect(_configKeys(entry.value).isNotEmpty, isTrue,
            reason: '${entry.key} 子页 key 列表不应为空');
      }
    });

    test('扩展功能已登记到次级区，降级清单非空', () {
      expect(EPlacement.kSecondary.containsKey('profile'), isTrue);
      expect(EPlacement.kSecondary.containsKey('reading'), isTrue);
      expect(EPlacement.kSecondary['reading_secondary_button'], ['备忘']);
      expect(EPlacement.degradations.isNotEmpty, isTrue);
      expect(EPlacement.degradations.containsKey('android:visible=false'),
          isTrue);
    });

    test('每个 EMenuItem 的 key 以 e_menu:: 开头且稳定唯一（在主菜单内）', () {
      for (final menu in EPlacement.mainMenus.values) {
        final keys = menu.map((e) => e.key).toList();
        expect(keys.every((k) => k.startsWith('e_menu::')), isTrue);
        expect(keys.toSet().length, keys.length);
      }
    });
  });

  // ── B.  XML 交叉校验（源缺失则 skip 并打印）─────────────────────
  group(
    'B · 菜单定义 XML 交叉校验',
    () {
      setUpAll(() {
        // ignore: avoid_print
        print('[菜单常量] 定义源: ${EPlacement.eSourceRoot}');
      });

      test('main_bnv.xml → tabs', () {
        expect(_menuIds(_res('menu/main_bnv.xml')), _ids(EPlacement.tabs));
      });

      for (final entry in {
        'bookshelf': 'main_bookshelf.xml',
        'explore': 'main_explore.xml',
        'rss': 'main_rss.xml',
        'my': 'main_my.xml',
      }.entries) {
        test('menu/${entry.value} → mainMenus[${entry.key}]', () {
          expect(_menuIds(_res('menu/${entry.value}')),
              _ids(EPlacement.mainMenus[entry.key]!));
        });
      }

      test('xml/pref_main.xml → myAll', () {
        expect(_prefKeys(_res('xml/pref_main.xml')), _ids(EPlacement.myAll));
      });

      test('xml/about.xml → aboutAll', () {
        expect(_prefKeys(_res('xml/about.xml')), _ids(EPlacement.aboutAll));
      });

      for (final entry in {
        'other': 'pref_config_other.xml',
        'backup': 'pref_config_backup.xml',
        'theme': 'pref_config_theme.xml',
        'cover': 'pref_config_cover.xml',
        'welcome': 'pref_config_welcome.xml',
        'aloud': 'pref_config_aloud.xml',
        'read': 'pref_config_read.xml',
      }.entries) {
        test('xml/${entry.value} → settingConfigKeys[${entry.key}]', () {
          expect(_prefKeys(_res('xml/${entry.value}')),
              _configKeys(EPlacement.settingConfigKeys[entry.key]!));
        });
      }

      test('menu/book_read.xml → 常驻 + overflow 全序', () {
        final expected = [
          ..._ids(EPlacement.readAlwaysOnline),
          ..._ids(EPlacement.readAlwaysText),
          ..._ids(EPlacement.readAlwaysLocal),
          ..._ids(EPlacement.readOverflow),
        ];
        expect(_menuIds(_res('menu/book_read.xml')), expected);
      });

      test('menu/content_select_action.xml → textSelectActions', () {
        expect(_menuIds(_res('menu/content_select_action.xml')),
            _ids(EPlacement.textSelectActions));
      });
    },
    skip: _eAvailable ? false : '定义源 ${EPlacement.eSourceRoot} 不存在，跳过 XML 交叉校验（不静默通过）',
  );
}
