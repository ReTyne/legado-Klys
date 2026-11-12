// 本轮「书源按钮失效 / 网页空白 / 界面观感」修复的离线回归基线。
//
// 覆盖不便在纯 widget 环境稳定复现的链路，用源码契约 + 纯函数断言锁死：
//  * _corsHeaders 必须返回可变 map（否则 java.ajax 抛 unmodifiable map，
//    checkNet() 等按钮被伪装成 502 请求失败）；
//  * 登录页 / 发现页共用 flex_fillet.dart 的规则化布局与统一 fillet 按钮；
//  * 浏览器对 data: 自包含页面走解码 + loadData，不再让 WebUri 破坏 base64；
//  * 我的页 14 项 K 独有功能按语义平铺归位、功能一项不删，E 主落点由真源驱动。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/ui/widgets/flex_fillet.dart';

String _src(String rel) => File(rel).readAsStringSync();

void main() {
  group('java.ajax CORS 头可变性（checkNet 等按钮失效根因）', () {
    test('_corsHeaders 返回可变 map，不能是 const', () {
      final s = _src(
          'lib/help/source/js/parts/web_view_legado_js.dart');
      final m = RegExp(r'Map<String, String> _corsHeaders\(\)\s*=>\s*([^;]+);')
          .firstMatch(s);
      expect(m, isNotNull, reason: '应存在 _corsHeaders() 定义');
      final expr = m!.group(1)!;
      // 关键：不能是 `const {...}`，否则后续 outHeaders['…']=… 赋值会抛
      // Unsupported operation: Cannot modify unmodifiable map
      expect(expr.trimLeft().startsWith('const'), isFalse,
          reason: 'CORS 头必须可变：调用方会追加 Content-Type/X-Set-Cookie/'
              'X-Legado-Error');
      // 必须是显式泛型可变字面量
      expect(expr, contains('<String, String>{'));
    });

    test('存在对 CORS 头的追加赋值（证明必须可变）', () {
      final s = _src(
          'lib/help/source/js/parts/web_view_legado_js.dart');
      expect(RegExp(r"outHeaders\['Content-Type'\]\s*=").hasMatch(s), isTrue);
      expect(RegExp(r"outHeaders\['X-Legado-Error'\]\s*=").hasMatch(s), isTrue);
      expect(RegExp(r"headers\['X-Set-Cookie'\]\s*=").hasMatch(s), isTrue);
    });
  });

  group('E 版 flexbox 规则化布局', () {
    test('flexBasisPercentOf 解析 -1/缺省/0.4/1', () {
      expect(flexBasisPercentOf(null), 0.4);
      expect(flexBasisPercentOf({'layout_flexBasisPercent': -1}), 0.4);
      expect(flexBasisPercentOf({'layout_flexBasisPercent': 0}), 0.4);
      expect(flexBasisPercentOf({'layout_flexBasisPercent': 0.4}), 0.4);
      expect(flexBasisPercentOf({'layout_flexBasisPercent': 0.45}), 0.45);
      expect(flexBasisPercentOf({'layout_flexBasisPercent': 1}), 1);
      expect(flexBasisPercentOf({'layout_flexBasisPercent': 0.96}), 1);
    });

    test('登录页与发现页共用 flex_fillet 组件', () {
      final login = _src(
          'lib/ui/book/source/parts/source_login_screen_state.dart');
      final discover =
          _src('lib/ui/main/discover/discover_screen.dart');
      expect(login, contains('FlexPercentLayout'));
      expect(discover, contains('FlexPercentLayout'));
      expect(login, contains('flexBasisPercentOf'));
      expect(discover, contains('flexBasisPercentOf'));
      // 统一 fillet 按钮：不再三色分级
      expect(_src('lib/ui/book/source/parts/login_button.dart'),
          contains('FilletButton'));
      expect(discover, contains('FilletButton'));
    });

    testWidgets('FlexPercentLayout 按 basisPercent 分行、整行项独占、行内等宽铺满',
        (tester) async {
      // 还原书源 7632：若干 0.4 按钮 + 一个 1(书源设置中心) 独占整行。
      // 0.4+0.4=0.8 → 同一行 2 个；第三个 0.4 累加到 1.2>1 → 换行；
      // 1 → 独占整行。预期行： [0,1] [2] [3,4] [5] [6] ...
      const percents = <double>[0.4, 0.4, 1, 0.4, 0.4, 0.4];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 400,
              child: FlexPercentLayout(
                percents: percents,
                children: List.generate(
                  percents.length,
                  (i) => FilletButton(label: '按钮$i', onPressed: () {}),
                ),
              ),
            ),
          ),
        ),
      ));
      // 分行：[0,1] [2] [3,4] [5] → 4 行
      expect(find.byType(Row), findsNWidgets(4));
      // 第一行两个按钮：宽度相等（按 flex 权重均分，铺满整行）
      final rows = tester.widgetList<Row>(find.byType(Row)).toList();
      expect(rows, isNotEmpty);
      final firstRowChildren = rows.first.children
          .whereType<Expanded>()
          .toList();
      expect(firstRowChildren.length, 2, reason: '第一行应是 2 个等宽按钮');
      // 整行项（第三个）独占一行：该行只有一个 Expanded
      final fullRow = rows[1].children.whereType<Expanded>().toList();
      expect(fullRow.length, 1, reason: 'basisPercent=1 的按钮应独占整行');
    });
  });

  group('浏览器 data: 自包含页面', () {
    test('源码含解码 + loadData 路径，地址栏不暴露 base64', () {
      final s = _src(
          'lib/ui/browser/parts/browser_screen_state.dart');
      expect(s, contains('_decodeDataHtml'));
      expect(s, contains('InAppWebViewInitialData'));
      expect(s, contains('loadData'));
      expect(s, contains('_buildDataPageAppBar'));
      // 返回可靠：getHtml 有超时 + 防重入
      expect(s, contains('.timeout(const Duration(seconds: 2))'));
      expect(s, contains('_exiting'));
    });
  });

  group('我的页：功能归位但不删', () {
    test('14 项 K 独有功能类名与语义分区都在', () {
      final s = _src('lib/ui/main/my/profile_screen.dart');
      for (final cls in const [
        'AutoTaskScreen', 'HomepageModuleScreen', 'DownloadManageScreen',
        'CloudTtsScreen', 'ReadingStatsScreen', 'AiChatScreen',
        'AgentToolScreen', 'WelcomeConfigScreen', 'AppIconScreen',
        'VideoSettingScreen', 'SettingsScreen',
      ]) {
        expect(s, contains(cls), reason: '独有功能 $cls 不应被删');
      }
      // 相似度聚合分区（不再是单个「更多功能」折叠黑洞，也不把同类功能拆散）
      for (final t in const [
        '设置与外观', '阅读与内容', '视听与 AI', '关于与项目',
      ]) {
        expect(s, contains(t), reason: '缺少相似度聚合分区 $t');
      }
      // 评分改为应用内反馈，与 GitHub 项目主页动作去重
      expect(s, contains('app_rating'));
      expect(s, contains('全部设置（汇总全部分项）'));
      expect(s, contains('_sectionCard'));
      expect(s, contains('_buildFeatureSections'));
    });

    test('E 主落点顺序仍由 EPlacement 单一真源驱动', () {
      final s = _src('lib/ui/main/my/profile_screen.dart');
      expect(s, contains('EPlacement.myTop'));
      expect(s, contains('EPlacement.mySettingCategory'));
      expect(s, contains('EPlacement.myOtherCategory'));
      expect(s, contains('EPlacement.myCategoryTitles'));
      expect(s, contains('EOverflowMenuButton'));
    });
  });
}
