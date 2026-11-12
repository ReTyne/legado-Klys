// 功能位置「可验收基线」（B5 重写）。
//
// 与旧版区别：旧版用「逐项 find.text ... findsOneWidget」的假顺序断言，
// 只验存在不验顺序、且锁定 本项目旧文案。本版：
//   - overflow 项用稳定 Key('e_menu::<id>') + getTopLeft().dy 升序做真正严格顺序断言；
//   - 我的页断言 pref_main 14 项分组树 + 独有项按语义平铺归位（主界面顺序不变、功能不删、直接可触达）；
//   - 断言容器是锚定 AppBar 右上的 overflow（而非底部 sheet）。
// 所有 expected 均由 lib/constant/e_placement.dart 单一真源驱动，避免文案漂移。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/constant/app_theme.dart';
import 'package:legado_md3/constant/e_placement.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/di/book_provider.dart';
import 'package:legado_md3/ui/main/bookshelf/bookshelf_manage_screen.dart';
import 'package:legado_md3/ui/main/bookshelf/bookshelf_screen.dart';
import 'package:legado_md3/ui/main/my/profile_screen.dart';
import 'package:legado_md3/ui/main/subscribe/subscribe_screen.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';

Widget _wrap(Widget child) => ChangeNotifierProvider<BookProvider>(
      create: (_) => BookProvider(),
      child: MaterialApp(home: child),
    );

/// 我的页依赖 AppTheme（主题模式选择器）
Widget _wrapProfile(Widget child) => MultiProvider(
      providers: [
        ChangeNotifierProvider<BookProvider>(create: (_) => BookProvider()),
        ChangeNotifierProvider<AppTheme>(create: (_) => AppTheme()),
      ],
      child: MaterialApp(home: child),
    );

Widget _withProvider(BookProvider p, Widget child) =>
    ChangeNotifierProvider<BookProvider>.value(
      value: p,
      child: MaterialApp(home: child),
    );

List<Book> _seedBooks() => [
      Book(name: '斗破苍穹', author: '天蚕土豆', group: '玄幻', lastChapter: '第100章 大结局'),
      Book(name: '大主宰', author: '天蚕土豆', group: '玄幻'),
    ];

/// 打开 PopupMenu 后，按稳定 Key 的 y 坐标升序还原 overflow 项的实际渲染顺序。
List<String> _overflowOrderById(WidgetTester tester, List<String> ids) {
  final withY = <MapEntry<String, double>>[];
  for (final id in ids) {
    final f = find.byKey(Key('e_menu::$id'));
    if (f.evaluate().isEmpty) continue;
    withY.add(MapEntry(id, tester.getTopLeft(f).dy));
  }
  withY.sort((a, b) => a.value.compareTo(b.value));
  return withY.map((e) => e.key).toList();
}

/// 在懒构建 ListView 中向下滚动直到目标可见（有上限，避免死循环）。
Future<void> _scrollUntilVisible(
    WidgetTester tester, Finder target, int maxDrag) async {
  for (var i = 0; i < maxDrag && target.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(ListView).first, const Offset(0, -120));
    await tester.pumpAndSettle();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('书架 overflow 与 E main_bookshelf 严格一致（项集合 + Key 顺序）',
      (tester) async {
    final p = BookProvider()..debugSeed(_seedBooks());
    await tester.pumpWidget(_withProvider(p, const BookshelfScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    // 容器必须是锚定 AppBar actions 的 EOverflowMenuButton（不是底部 sheet）。
    expect(find.byType(EOverflowMenuButton), findsOneWidget);
    await tester.tap(find.byIcon(Icons.more_vert_outlined));
    await tester.pumpAndSettle();

    final overflow = EPlacement.mainMenus['bookshelf']!
        .where((e) => e.overflow)
        .toList();
    // 每项有稳定 Key 且文案取自单一真源
    for (final e in overflow) {
      expect(find.byKey(Key(e.key)), findsOneWidget,
          reason: '缺少 overflow 项：${e.zh} (${e.id})');
      expect(find.text(e.zh), findsOneWidget,
          reason: '缺少 标准文案：${e.zh}');
    }
    // 真正严格顺序：按渲染 y 坐标升序必须等于单一真源顺序
    final ids = overflow.map((e) => e.id).toList();
    expect(_overflowOrderById(tester, ids), ids,
        reason: '书架 overflow 渲染顺序必须与 E main_bookshelf.xml 一致');

    // 本项目旧文案（已被 标准文案替换）不应出现在 主界面
    for (final old in const ['添加URL', '缓存导出', '导出书架', '导入书架']) {
      expect(find.text(old), findsNothing, reason: '应改用 标准文案：$old');
    }
    // 已下架的入口不应出现
    for (final absent in const [
      '首页模块视图', '搜索书籍', '多选模式', '阅读记录', '清空书架', '排序设置'
    ]) {
      expect(find.text(absent), findsNothing, reason: '不应存在菜单项：$absent');
    }
  });

  testWidgets('书架布局对话框提供 布局/排序/分组样式选项', (tester) async {
    final p = BookProvider()..debugSeed(_seedBooks());
    await tester.pumpWidget(_withProvider(p, const BookshelfScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    await tester.tap(find.byIcon(Icons.more_vert_outlined));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('书架布局'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('书架布局'));
    await tester.pumpAndSettle();

    expect(find.text('书架布局'), findsWidgets); // 对话框标题
    for (final opt in const [
      '分组样式', '显示未读', '显示上次更新时间', '显示待更新书籍', '快速滚动条', '布局', '排序', '书名'
    ]) {
      expect(find.text(opt), findsWidgets, reason: '缺少布局选项：$opt');
    }
    for (final layout in const [
      '列表', '紧凑列表', '网格2列', '网格3列', '网格4列', '网格5列', '网格6列'
    ]) {
      expect(find.text(layout), findsOneWidget, reason: '缺少布局：$layout');
    }
    for (final sort in const ['最近阅读', '更新时间', '书名', '手动', '综合', '作者']) {
      // 默认布局为网格后，「书名显示」分区标题也叫「书名」（ book_name_choice
      // 仅网格可见），会与排序项「书名」重名，故用 findsWidgets。
      expect(find.text(sort), sort == '书名' ? findsWidgets : findsOneWidget,
          reason: '缺少排序：$sort');
    }
    // 默认网格生效：书名显示方式（显示/隐藏/叠加）分区应可见
    expect(find.text('叠加'), findsWidgets,
        reason: '默认网格布局下书名显示分区应可见');
  });

  testWidgets('书架管理页可构建、多选与批量操作栏', (tester) async {
    final p = BookProvider()..debugSeed(_seedBooks());
    await tester.pumpWidget(_withProvider(p, const BookshelfManageScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('书架管理'), findsOneWidget);
    expect(find.text('斗破苍穹'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('斗破苍穹::天蚕土豆')));
    await tester.pumpAndSettle();
    expect(find.text('已选 1 本'), findsOneWidget);
    for (final action in const ['移动分组', '缓存', '导出', '删除']) {
      expect(find.text(action), findsOneWidget, reason: '缺少批量操作：$action');
    }

    await tester.tap(find.byTooltip('全选'));
    await tester.pumpAndSettle();
    expect(find.text('已选 2 本'), findsOneWidget);
  });

  testWidgets('我的页严格对齐 pref_main 14 项分组树 + 独有项语义平铺归位',
      (tester) async {
    await tester.pumpWidget(_wrapProfile(const ProfileScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    // AppBar「帮助」overflow（main_my.xml 仅 1 项）
    expect(find.byType(EOverflowMenuButton), findsOneWidget);

    // 按 UI 真实自上而下顺序单调遍历：顶层 6 → 「设置」标题 → 设置 3 →
    // 「其它」标题 → 其它 5。每项在滚动路径上即时验证，避免懒构建卸载上方项
    // 后回查不到（这是旧版「逐项 findsOneWidget」假顺序断言的坑）。
    final orderedFinders = <Finder>[
      for (final e in EPlacement.myTop) find.byKey(Key(e.key)),
      find.text(EPlacement.myCategoryTitles[0]),
      for (final e in EPlacement.mySettingCategory) find.byKey(Key(e.key)),
      find.text(EPlacement.myCategoryTitles[1]),
      for (final e in EPlacement.myOtherCategory) find.byKey(Key(e.key)),
    ];
    for (final f in orderedFinders) {
      await _scrollUntilVisible(tester, f, 30);
      expect(f, findsWidgets, reason: '缺少 pref_main 结构项：$f');
    }

    // 扩展项已按「相似度」聚合归位到 主界面之后的 4 张分区卡片中
    // （不再藏在单个默认折叠的「更多功能」里，也不把同类功能拆散到不同组）。
    // 按页面真实自上而下顺序单调遍历验证，避免 ListView 懒构建卸载上方项
    // 后回查不到（沿用上面的滚动策略）。每项既是「分区存在」也是「功能
    // 不删、直接可触达」的断言。
    for (final k in const [
      '设置与外观', '全部设置（汇总全部分项）', '欢迎页设置', '桌面图标',
      '阅读与内容', '阅读统计', '首页模块', '定时任务', '下载管理',
      '视听与 AI', '朗读引擎', '视频设置', 'AI 助手', '智能体工具',
      '关于与项目', 'GitHub项目', '分享应用', '评分',
    ]) {
      await _scrollUntilVisible(tester, find.text(k), 40);
      expect(find.text(k), findsWidgets, reason: '归位后应可直接触达：$k');
    }

    // 三个基准都没有的入口不应出现
    for (final absent in const [
      'OPDS书源', '高亮标签配置', '标签分组规则', 'RSS订阅', '规则订阅',
      '翻译设置', '实验室', '书籍标记', '缓存管理', '云盘同步'
    ]) {
      expect(find.text(absent), findsNothing, reason: '不应存在我的页条目：$absent');
    }
  });

  testWidgets('订阅页无订阅源时渲染空态而不崩溃', (tester) async {
    await tester.pumpWidget(_wrap(const SubscribeScreen()));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(find.text('订阅'), findsWidgets);
    expect(find.text('暂无订阅源'), findsOneWidget);
  });
}
