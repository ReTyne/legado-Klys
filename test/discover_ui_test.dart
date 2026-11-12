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

  testWidgets('发现页默认渲染书源发现列表空态而不崩溃', (tester) async {
    await tester.pumpWidget(_wrap(const DiscoverScreen()));
    // initState 的异步加载（测试环境 sqflite 抛 MissingPluginException）完成后，
    // 默认视图须为「书源发现列表」并显示空态，不能留下无限转圈。
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(find.text('发现'), findsWidgets);
    expect(find.text('暂无发现书源'), findsOneWidget);
    // 无持续动画：loading 已结束
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('首页模块 Feed 仍可从次级入口「更多功能」触达', (tester) async {
    await tester.pumpWidget(_wrap(const DiscoverScreen()));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    // 主落点收敛为 「分组」，扩展首页模块 Feed 沉到 AppBar 末尾的
    // 「更多功能」overflow；从该次级入口切换，验证功能未被删除。
    await tester.tap(find.byIcon(Icons.more_vert_outlined));
    await tester.pumpAndSettle();
    expect(find.text('首页模块 Feed'), findsOneWidget);
    await tester.tap(find.text('首页模块 Feed'));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(find.text('首页暂无模块'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
