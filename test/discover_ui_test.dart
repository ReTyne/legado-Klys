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

  testWidgets('发现页默认首页模块 Feed 在 DB 不可用时渲染空态而不崩溃',
      (tester) async {
    await tester.pumpWidget(_wrap(const DiscoverScreen()));
    // 让 initState 的异步加载（测试环境 sqflite 抛 MissingPluginException）完成。
    // 第十轮：默认首页改为卡片式模块 Feed，DB 不可用必须结束 loading 显示空态，
    // 不能留下无限转圈的 CircularProgressIndicator（否则 pumpAndSettle 会超时）。
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(find.text('发现'), findsWidgets);
    expect(find.text('首页暂无模块'), findsOneWidget);
    // 无持续动画：loading 已结束
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('发现页可切到书源发现列表并渲染空态', (tester) async {
    await tester.pumpWidget(_wrap(const DiscoverScreen()));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    // 点击 AppBar 的「书源发现」切换按钮
    await tester.tap(find.byTooltip('书源发现'));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(find.text('暂无发现书源'), findsOneWidget);
  });
}
