import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/constant/app_theme.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/di/book_provider.dart';
import 'package:legado_md3/ui/main/bookshelf/bookshelf_manage_screen.dart';
import 'package:legado_md3/ui/main/bookshelf/bookshelf_screen.dart';
import 'package:legado_md3/ui/main/my/profile_screen.dart';
import 'package:legado_md3/ui/main/subscribe/subscribe_screen.dart';

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

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('书架更多菜单与 legado-E main_bookshelf 一致（项与顺序）', (tester) async {
    final p = BookProvider()..debugSeed(_seedBooks());
    await tester.pumpWidget(_withProvider(p, const BookshelfScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    // 风格统一：actions 图标一律线框（*_outlined）
    await tester.tap(find.byIcon(Icons.more_vert_outlined));
    await tester.pumpAndSettle();

    // legado-E 书架菜单的完整条目
    const expected = [
      '更新目录',
      '添加本地',
      '远程书籍',
      '添加URL',
      '书架管理',
      '缓存导出',
      '分组管理',
      '书架布局',
      '导出书架',
      '导入书架',
      '日志',
    ];
    for (final item in expected) {
      expect(find.text(item), findsOneWidget, reason: '缺少菜单项：$item');
    }
    // E 书架没有的入口不应出现
    for (final absent in const ['首页模块视图', '搜索书籍', '多选模式', '阅读记录', '设置', '清空书架', '排序设置']) {
      expect(find.text(absent), findsNothing, reason: '不应存在菜单项：$absent');
    }
  });

  testWidgets('书架布局对话框提供 E 的布局/排序/分组样式选项', (tester) async {
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
    for (final opt in const ['分组样式', '显示未读', '显示上次更新时间', '显示待更新书籍', '快速滚动条', '布局', '排序', '书名']) {
      expect(find.text(opt), findsWidgets, reason: '缺少布局选项：$opt');
    }
    // E 的 7 种布局
    for (final layout in const ['列表', '紧凑列表', '网格2列', '网格3列', '网格4列', '网格5列', '网格6列']) {
      expect(find.text(layout), findsOneWidget, reason: '缺少布局：$layout');
    }
    // E 的 6 种排序
    for (final sort in const ['最近阅读', '更新时间', '书名', '手动', '综合', '作者']) {
      expect(find.text(sort), findsOneWidget, reason: '缺少排序：$sort');
    }
  });

  testWidgets('书架管理页可构建、多选与批量操作栏', (tester) async {
    final p = BookProvider()..debugSeed(_seedBooks());
    await tester.pumpWidget(_withProvider(p, const BookshelfManageScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('书架管理'), findsOneWidget);
    // 统一封面组件 BookCover 的默认占位也会显示书名，故标题文本出现 2 次
    expect(find.text('斗破苍穹'), findsWidgets);

    // 点选一本后出现底部批量操作栏（对齐 E 的 SelectActionBar）。
    // 用 ListTile 的 ValueKey 精准定位，避免误点封面占位文字。
    await tester.tap(find.byKey(const ValueKey('斗破苍穹::天蚕土豆')));
    await tester.pumpAndSettle();
    expect(find.text('已选 1 本'), findsOneWidget);
    for (final action in const ['移动分组', '缓存', '导出', '删除']) {
      expect(find.text(action), findsOneWidget, reason: '缺少批量操作：$action');
    }

    // 全选
    await tester.tap(find.byTooltip('全选'));
    await tester.pumpAndSettle();
    expect(find.text('已选 2 本'), findsOneWidget);
  });

  testWidgets('我的页包含三个基准项目的全局管理入口，且无越界项', (tester) async {
    await tester.pumpWidget(_wrapProfile(const ProfileScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    // 按 UI 自上而下的顺序排列（ListView 懒构建：单调向下滚动逐项校验，
    // 已滚出屏幕的项不再回查）。除 legado-E pref_main 的原有条目外，
    // 还包含本轮按三个基准补齐的入口：首页模块(MD3 fork)、定时任务(官方原版
    // AutoTaskManage)、朗读引擎/下载管理/AI 助手/阅读统计(原版与 fork 共有)。
    const orderedItems = [
      '书源管理', 'TXT目录规则', '替换净化', '词典规则', '首页模块', '定时任务',
      '主题模式', 'Web服务', '备份与恢复', '主题设置', '其他设置', '朗读引擎',
      '下载管理', 'AI 助手', '书签', '阅读记录', '阅读统计', '文件管理', '关于', '退出',
    ];
    for (final item in orderedItems) {
      for (var i = 0; i < 30 && find.text(item).evaluate().isEmpty; i++) {
        await tester.drag(find.byType(ListView).first, const Offset(0, -120));
        await tester.pumpAndSettle();
      }
      expect(find.text(item), findsOneWidget, reason: '缺少我的页条目：$item');
    }
    // 三个基准项目都没有的入口不应出现（防止随意乱加页面）
    for (final absent in const ['OPDS书源', '高亮标签配置', '标签分组规则', 'RSS订阅', '规则订阅', '翻译设置', '实验室', '书籍标记', '缓存管理', '云盘同步']) {
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
