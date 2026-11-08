import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/di/book_provider.dart';
import 'package:legado_md3/ui/book/read/reading_screen.dart';

/// 阅读页冒烟测试：构建不崩溃、菜单控件齐全（对齐 legado-E view_read_menu）
Widget _wrap(Book book) => MultiProvider(
      providers: [
        ChangeNotifierProvider<BookProvider>(create: (_) => BookProvider()),
        ChangeNotifierProvider<ReadProvider>(create: (_) => ReadProvider()),
      ],
      child: MaterialApp(home: ReadingScreen(book: book)),
    );

void main() {
  setUpAll(() {
    // 测试环境用 FFI 工厂（无原生 sqflite 插件时数据库不可用的兜底）
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // 阅读页有时钟/自动阅读等周期定时器，pumpAndSettle 会一直等待，
  // 改用多次 pump 推进帧与异步加载。
  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 30)));
    }
  }

  testWidgets('阅读页可构建且无章节时展示占位内容', (tester) async {
    final book = Book(name: '十日终焉', author: '杀虫队队员', local: true, origin: '');
    await tester.pumpWidget(_wrap(book));
    await pumpFrames(tester);

    // 页面构建成功
    expect(find.byType(ReadingScreen), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 无章节时展示简介/占位内容而非崩溃（分页器会加首行缩进）
    expect(find.textContaining('暂无内容'), findsOneWidget);
  });

  testWidgets('点击正文中央唤出阅读菜单（进度条/字号）', (tester) async {
    final book = Book(name: '测试书', author: '作者', local: true, origin: '');
    await tester.pumpWidget(_wrap(book));
    await pumpFrames(tester);

    // 点击屏幕中央唤出菜单（clickActions 默认中间=菜单）
    final size = tester.getSize(find.byType(ReadingScreen));
    await tester.tapAt(Offset(size.width / 2, size.height / 2));
    await pumpFrames(tester);

    // 菜单唤出后底部设置面板可见（章节进度/字号/背景）
    expect(find.byIcon(Icons.skip_previous), findsWidgets);
    expect(find.byIcon(Icons.skip_next), findsWidgets);
    expect(find.text('字号'), findsWidgets);
    expect(find.text('背景'), findsNothing); // 背景色选择无文字标题，防止误判
  });
}
