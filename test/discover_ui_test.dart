import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/di/book_provider.dart';
import 'package:legado_md3/ui/main/discover/discover_screen.dart';

Widget _wrap(Widget child) => ChangeNotifierProvider<BookProvider>(
      create: (_) => BookProvider(),
      child: MaterialApp(home: child),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('发现页在无书源/DB 不可用时渲染空态而不崩溃（回归：曾永远只显示分类）', (tester) async {
    await tester.pumpWidget(_wrap(const DiscoverScreen()));
    // 让 initState 的异步加载（测试环境 sqflite 抛 MissingPluginException）完成
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(find.text('发现'), findsWidgets);
    expect(find.text('暂无发现书源'), findsOneWidget);
  });
}
