import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';

/// UI 重构回归：锁定设计令牌、三态组件、无障碍语义与响应式容器契约，
/// 防止后续改动把统一组件重新退化成散落的裸 widget。
void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('设计令牌', () {
    test('间距遵循 4pt 栅格且页面/卡片预设一致', () {
      expect(AppSpacing.xs, 4);
      expect(AppSpacing.s, 8);
      expect(AppSpacing.m, 12);
      expect(AppSpacing.l, 16);
      expect(AppSpacing.xl, 24);
      expect(AppSpacing.pageAll, const EdgeInsets.all(16));
      expect(AppSpacing.section, const EdgeInsets.fromLTRB(16, 16, 16, 8));
    });

    test('圆角为编译期常量且断点遵循 M3 窗口尺寸类', () {
      expect(AppRadius.m, 12);
      expect(AppRadius.mAll, const BorderRadius.all(Radius.circular(12)));
      expect(AppBreakpoints.compact, 600);
      expect(AppBreakpoints.medium, 840);
      expect(AppBreakpoints.expanded, 1200);
    });

    testWidgets('语义色扩展跟随 Theme', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue)),
        home: Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        }),
      ));
      expect(ctx.cs.primary, ctx.theme.colorScheme.primary);
      expect(ctx.onSurface, ctx.theme.colorScheme.onSurface);
      expect(ctx.onSurfaceVariant, ctx.theme.colorScheme.onSurfaceVariant);
    });
  });

  group('通用三态组件与无障碍', () {
    testWidgets('AppEmptyState 渲染标题/说明且图标带语义标签', (tester) async {
      await tester.pumpWidget(wrap(const AppEmptyState(
        icon: Icons.inbox_outlined,
        title: '暂无书籍',
        message: '去书城添加',
      )));
      expect(find.text('暂无书籍'), findsOneWidget);
      expect(find.text('去书城添加'), findsOneWidget);
      expect(find.bySemanticsLabel('空状态：暂无书籍'), findsOneWidget);
    });

    testWidgets('AppErrorState 渲染重试按钮且带 button 语义', (tester) async {
      var retried = 0;
      await tester.pumpWidget(wrap(AppErrorState(
        message: '网络异常',
        onRetry: () => retried++,
      )));
      expect(find.text('加载失败'), findsOneWidget);
      expect(find.text('网络异常'), findsOneWidget);
      expect(find.bySemanticsLabel('错误状态：加载失败'), findsOneWidget);
      await tester.tap(find.text('重试'));
      expect(retried, 1);
    });

    testWidgets('AppLoadingIndicator 带加载中语义且无 message 时等价裸 Center',
        (tester) async {
      await tester.pumpWidget(wrap(const AppLoadingIndicator()));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.bySemanticsLabel('加载中'), findsWidgets);
    });

    testWidgets('AppAsyncState 按 loading/empty/child 正确切换', (tester) async {
      final child = ListView(children: const [Text('数据行')]);
      // loading
      await tester.pumpWidget(wrap(AppAsyncState(
          loading: true, isEmpty: false, child: child)));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('数据行'), findsNothing);
      // empty
      await tester.pumpWidget(wrap(AppAsyncState(
          loading: false, isEmpty: true, emptyTitle: '空', child: child)));
      expect(find.text('空'), findsOneWidget);
      // data
      await tester.pumpWidget(wrap(AppAsyncState(
          loading: false, isEmpty: false, child: child)));
      expect(find.text('数据行'), findsOneWidget);
    });
  });

  group('响应式容器', () {
    // MaterialApp / Scaffold 自身就会引入 ConstrainedBox，因此只在
    // AppAdaptiveBody 的子树内断言，避免把框架自带的限宽容器误判为组件行为。
    Finder adaptiveBox() => find.descendant(
          of: find.byType(AppAdaptiveBody),
          matching: find.byType(ConstrainedBox),
        );

    testWidgets('窄屏原样返回 child（不套限宽容器）', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(wrap(const AppAdaptiveBody(child: Text('内容'))));
      expect(adaptiveBox(), findsNothing);
      expect(find.text('内容'), findsOneWidget);
    });

    testWidgets('宽屏居中并限制最大宽度', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(wrap(const AppAdaptiveBody(
          maxWidth: 720, child: Text('内容'))));
      expect(adaptiveBox(), findsOneWidget);
      expect(tester.widget<ConstrainedBox>(adaptiveBox()).constraints.maxWidth, 720);
      expect(find.text('内容'), findsOneWidget);
    });

    testWidgets('宽屏包裹可滚动列表仍可正常布局', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(wrap(AppAdaptiveBody(
        child: ListView(children: const [Text('行1'), Text('行2')]),
      )));
      // 保障列表型页面（如标签分组规则）接入限宽容器后不产生 unbounded 约束异常。
      expect(tester.takeException(), isNull);
      expect(find.text('行1'), findsOneWidget);
      expect(find.text('行2'), findsOneWidget);
    });
  });
}
