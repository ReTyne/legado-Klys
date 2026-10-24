import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 模拟「子页面压栈后按系统返回键」的最小复现。
///
/// 背景：Android 返回键经 FlutterActivity -> navigationChannel.popRoute()
/// 到达 Dart 的 WidgetsBinding.handlePopRoute()，最终调用的是
/// WidgetsApp 内部根 Navigator 的 maybePop()。
/// 因此如果首页 widget 自己又套了一层 Navigator（旧版 MainScreen 的做法），
/// 子页面 push 进的是内层栈，根 Navigator 栈底 route 的 popDisposition 为
/// bubble，没人消费 -> SystemNavigator.pop() -> Activity finish -> 回到桌面。
///
/// 这里把返回键消息直接发给 framework，断言子页面是否被正确 pop。

const _navChannel = MethodChannel('flutter/navigation');

Future<void> _pressSystemBack(WidgetTester tester) async {
  final completer = <void>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
    _navChannel.name,
    const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
    (_) => completer.add(null),
  );
  await tester.pumpAndSettle();
}

/// 旧结构：home 内部自建 Navigator（复现 bug 的结构）。
class _OldStructureApp extends StatelessWidget {
  const _OldStructureApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Navigator(
        onGenerateRoute: (settings) {
          if (settings.name == '/') {
            return MaterialPageRoute(builder: (_) => const _HomePage());
          }
          return null;
        },
      ),
    );
  }
}

/// 新结构：home 直接返回 Scaffold，子页面 push 到 MaterialApp 的根 Navigator。
class _NewStructureApp extends StatelessWidget {
  const _NewStructureApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: _HomePage());
  }
}

class _HomePage extends StatelessWidget {
  const _HomePage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('home')),
      body: Center(
        child: ElevatedButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const _SubPage()),
          ),
          child: const Text('open sub'),
        ),
      ),
    );
  }
}

class _SubPage extends StatelessWidget {
  const _SubPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('sub')),
      body: const Center(child: Text('sub page')),
    );
  }
}

void main() {
  testWidgets('旧结构（内层 Navigator）：系统返回键无法 pop 子页面', (tester) async {
    await tester.pumpWidget(const _OldStructureApp());
    await tester.tap(find.text('open sub'));
    await tester.pumpAndSettle();
    expect(find.text('sub page'), findsOneWidget);

    await _pressSystemBack(tester);
    // bug 复现：子页面还在（真实设备上表现为直接退出应用回桌面）
    expect(find.text('sub page'), findsOneWidget);
    expect(find.text('home'), findsNothing);
  });

  testWidgets('新结构（根 Navigator）：系统返回键逐级回退', (tester) async {
    await tester.pumpWidget(const _NewStructureApp());
    await tester.tap(find.text('open sub'));
    await tester.pumpAndSettle();
    expect(find.text('sub page'), findsOneWidget);

    await _pressSystemBack(tester);
    expect(find.text('sub page'), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('新结构：栈底按返回不崩溃（允许退出应用）', (tester) async {
    await tester.pumpWidget(const _NewStructureApp());
    await _pressSystemBack(tester);
    // 栈底 route 冒泡后由 SystemNavigator.pop() 处理（test 中为 no-op），
    // 不应抛异常、页面应仍在。
    expect(find.text('home'), findsOneWidget);
  });
}
