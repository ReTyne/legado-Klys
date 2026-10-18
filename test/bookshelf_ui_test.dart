import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/di/book_provider.dart';
import 'package:legado_md3/ui/main/bookshelf/bookshelf_screen.dart';
import 'package:legado_md3/ui/main/bookshelf/bookshelf_config_screen.dart';
import 'package:legado_md3/ui/main/bookshelf/group_manage_screen.dart';

Widget _wrap(Widget child) => ChangeNotifierProvider<BookProvider>(
      create: (_) => BookProvider(),
      child: MaterialApp(home: child),
    );

Widget _withProvider(BookProvider p, Widget child) =>
    ChangeNotifierProvider<BookProvider>.value(
      value: p,
      child: MaterialApp(home: child),
    );

List<Book> _seedBooks() => [
      Book(
          name: '斗破苍穹',
          author: '天蚕土豆',
          group: '玄幻',
          lastChapter: '第100章 大结局',
          lastChapterIndex: 100,
          durChapterIndex: 3,
          kind: '玄幻',
          intro: '这里是一段足够长的简介文本用于展示简介行数。'),
      Book(name: '大主宰', author: '天蚕土豆', group: '玄幻', lastChapterIndex: 50),
      Book(name: '散书', author: '佚名'),
    ];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('书架空态可正常构建（无 DB 不崩溃）', (tester) async {
    await tester.pumpWidget(_wrap(const BookshelfScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('书架'), findsWidgets);
  });

  testWidgets('书架配置页可切换 5 种布局并持久化', (tester) async {
    await tester.pumpWidget(_wrap(const BookshelfConfigScreen()));
    await tester.pumpAndSettle();
    expect(find.text('三列网格'), findsOneWidget);
    await tester.tap(find.text('三列网格'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('bs_layout'), 2);
    // 网格下列数滑杆出现
    expect(find.textContaining('网格列数'), findsOneWidget);
  });

  testWidgets('分组管理页空态可构建', (tester) async {
    await tester.pumpWidget(_wrap(const GroupManageScreen()));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('分组管理'), findsWidgets);
  });

  testWidgets('列表布局渲染书籍与未读角标', (tester) async {
    SharedPreferences.setMockInitialValues({'bs_showUnread': true});
    final p = BookProvider()..debugSeed(_seedBooks());
    await tester.pumpWidget(_withProvider(p, const BookshelfScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('斗破苍穹'), findsWidgets);
    expect(find.textContaining('第100章'), findsWidgets);
    // 未读角标（斗破苍穹 100-3=97）
    expect(find.text('97'), findsOneWidget);
  });

  testWidgets('网格布局(bs_layout=2)正常渲染', (tester) async {
    SharedPreferences.setMockInitialValues({'bs_layout': 2});
    final p = BookProvider()..debugSeed(_seedBooks());
    await tester.pumpWidget(_withProvider(p, const BookshelfScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('斗破苍穹'), findsWidgets);
    expect(find.text('大主宰'), findsWidgets);
  });

  testWidgets('网格布局 + 未读角标不崩溃且显示数字', (tester) async {
    SharedPreferences.setMockInitialValues({'bs_layout': 2, 'bs_showUnread': true});
    final p = BookProvider()..debugSeed(_seedBooks());
    await tester.pumpWidget(_withProvider(p, const BookshelfScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.takeException(), isNull);
    expect(find.text('斗破苍穹'), findsWidgets);
    expect(find.text('97'), findsOneWidget); // 角标在网格内仍渲染
  });

  testWidgets('平铺分组(bs_groupStyle=1)按分区展示并含未分组', (tester) async {
    SharedPreferences.setMockInitialValues({'bs_groupStyle': 1});
    final p = BookProvider()..debugSeed(_seedBooks());
    await tester.pumpWidget(_withProvider(p, const BookshelfScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('玄幻'), findsWidgets);
    expect(find.text('未分组'), findsWidgets);
    expect(find.text('斗破苍穹'), findsWidgets);
    expect(find.text('散书'), findsWidgets);
  });
}
