// B1 组件契约：EOverflowMenuButton 必须锚定 AppBar 右上、项序可严格断言、
// visible=false 不渲染、checkable 有勾选态、扩展项隔离在末尾次级分组。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/constant/e_placement.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('测试'),
          actions: [child],
        ),
        body: const SizedBox.expand(),
      ),
    );

/// 打开 overflow 后，按稳定 Key 的 y 坐标升序还原实际渲染顺序。
List<String> _renderedOrder(WidgetTester tester, List<String> ids) {
  final withY = <MapEntry<String, double>>[];
  for (final id in ids) {
    final finder = find.byKey(Key('e_menu::$id'));
    if (finder.evaluate().isEmpty) continue;
    withY.add(MapEntry(id, tester.getTopLeft(finder).dy));
  }
  withY.sort((a, b) => a.value.compareTo(b.value));
  return withY.map((e) => e.key).toList();
}

void main() {
  testWidgets('项集合与严格顺序按传入顺序渲染（稳定 Key）', (tester) async {
    final items = [
      EOverflowItem(id: 'a', label: '甲', onTap: () {}),
      EOverflowItem(id: 'b', label: '乙', onTap: () {}),
      EOverflowItem(id: 'c', label: '丙', onTap: () {}),
    ];
    await tester.pumpWidget(_wrap(EOverflowMenuButton(
      items: items,
      onSelected: (_) {},
    )));
    await tester.tap(find.byIcon(Icons.more_vert_outlined));
    await tester.pumpAndSettle();

    expect(find.text('甲'), findsOneWidget);
    expect(find.text('乙'), findsOneWidget);
    expect(find.text('丙'), findsOneWidget);
    expect(_renderedOrder(tester, ['a', 'b', 'c']), ['a', 'b', 'c']);
  });

  testWidgets('visibleByDefault=false 项默认不渲染（不伪造空壳）', (tester) async {
    final items = [
      EOverflowItem(id: 'a', label: '可见', onTap: () {}),
      EOverflowItem(id: 'b', label: '隐藏', visibleByDefault: false, onTap: () {}),
      EOverflowItem(id: 'c', label: '可见2', onTap: () {}),
    ];
    await tester.pumpWidget(_wrap(EOverflowMenuButton(items: items)));
    await tester.tap(find.byIcon(Icons.more_vert_outlined));
    await tester.pumpAndSettle();

    expect(find.text('可见'), findsOneWidget);
    expect(find.text('隐藏'), findsNothing);
    expect(find.byKey(const Key('e_menu::b')), findsNothing);
  });

  testWidgets('checkable 项显示勾选态图标', (tester) async {
    final items = [
      EOverflowItem(id: 'on', label: '已勾选', checkable: true, checked: true, onTap: () {}),
      EOverflowItem(id: 'off', label: '未勾选', checkable: true, checked: false, onTap: () {}),
    ];
    await tester.pumpWidget(_wrap(EOverflowMenuButton(items: items)));
    await tester.tap(find.byIcon(Icons.more_vert_outlined));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.check_box), findsOneWidget);
    expect(find.byIcon(Icons.check_box_outline_blank), findsOneWidget);
  });

  testWidgets('扩展项隔离在末尾「更多功能」子分组且仍可点击', (tester) async {
    final primary = [
      EOverflowItem(id: 'p1', label: '主项1', onTap: () {}),
      EOverflowItem(id: 'p2', label: '主项2', onTap: () {}),
    ];
    final secondary = [
      EOverflowItem(id: 'x1', label: 'AI 助手', onTap: () {}),
      EOverflowItem(id: 'x2', label: '阅读统计', onTap: () {}),
    ];
    final tapped = <String>[];
    await tester.pumpWidget(_wrap(EOverflowMenuButton(
      items: primary.map((e) => EOverflowItem(
            id: e.id,
            label: e.label,
            onTap: () => tapped.add(e.id),
          )).toList(),
      secondary: secondary.map((e) => EOverflowItem(
            id: e.id,
            label: e.label,
            onTap: () => tapped.add(e.id),
          )).toList(),
    )));
    await tester.tap(find.byIcon(Icons.more_vert_outlined));
    await tester.pumpAndSettle();

    // 次级分组标题与分隔线存在
    expect(find.text('更多功能'), findsOneWidget);
    expect(find.byType(PopupMenuDivider), findsOneWidget);
    // 主项在前、次级项在后
    expect(
      _renderedOrder(tester, ['p1', 'p2', 'x1', 'x2']),
      ['p1', 'p2', 'x1', 'x2'],
    );
    // 次级项可点击
    await tester.tap(find.text('AI 助手'));
    await tester.pumpAndSettle();
    expect(tapped, ['x1']);
  });

  testWidgets('onSelected 与 item.onTap 同时分发，且仅命中被点项', (tester) async {
    final selected = <String>[];
    final tapped = <String>[];
    await tester.pumpWidget(_wrap(EOverflowMenuButton(
      items: [
        EOverflowItem(id: 'a', label: '甲', onTap: () => tapped.add('a')),
        EOverflowItem(id: 'b', label: '乙', onTap: () => tapped.add('b')),
      ],
      onSelected: selected.add,
    )));
    await tester.tap(find.byIcon(Icons.more_vert_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('乙'));
    await tester.pumpAndSettle();
    expect(selected, ['b']);
    expect(tapped, ['b']);
  });

  test('eOverflowItemsFrom 从单一真源构造，顺序/勾选/隐藏无漂移', () {
    final items = eOverflowItemsFrom(
      EPlacement.readOverflow,
      onTapFor: (_) => () {},
    );
    expect(items.length, EPlacement.readOverflow.length);
    expect(items.map((e) => e.id).toList(),
        EPlacement.readOverflow.map((e) => e.id).toList());
    final hidden = items.where((e) => !e.visibleByDefault).map((e) => e.id).toList();
    expect(hidden, ['menu_get_progress', 'menu_cover_progress', 'menu_enable_review']);
    final checked = items.where((e) => e.checkable && e.checked).map((e) => e.id).toList();
    expect(checked, ['menu_enable_replace']);
  });

  test('eOverflowItemsFrom 支持 overrides 覆盖可见性与文案', () {
    final items = eOverflowItemsFrom(
      EPlacement.mainMenus['bookshelf']!,
      onTapFor: (_) => () {},
      overrides: const {
        'menu_download': (checked: null, visible: null, label: '缓存导出'),
      },
    );
    final dl = items.firstWhere((e) => e.id == 'menu_download');
    expect(dl.label, '缓存导出');
  });
}
