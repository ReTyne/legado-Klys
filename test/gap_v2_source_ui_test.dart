import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 书源 UI 域细节功能的源码契约，防止新增入口被回退为死菜单。
void main() {
  late String manage;
  late String editState;
  late String loginState;
  late String loginButton;
  late String debugState;

  setUpAll(() {
    const base = 'lib/ui/book/source/';
    manage = File('${base}source_manage_screen.dart').readAsStringSync();
    editState =
        File('${base}parts/source_edit_screen_state.dart').readAsStringSync();
    loginState =
        File('${base}parts/source_login_screen_state.dart').readAsStringSync();
    loginButton = File('${base}parts/login_button.dart').readAsStringSync();
    debugState =
        File('${base}parts/source_debug_screen_state.dart').readAsStringSync();
  });

  group('书源管理细节', () {
    test('单项菜单含“搜索该书源”并传入 scope', () {
      expect(manage, contains("title: '搜索'"));
      expect(manage, contains('_showSourceSearch'));
      expect(manage, contains("searchScope: '\$name::\${source.bookSourceUrl}'"));
    });

    test('支持“未启用发现”筛选', () {
      expect(manage, contains("case 'disabled_explore':"));
      expect(manage, contains("return '未启用发现';"));
      expect(manage, contains("value: 'filter_disabled_explore'"));
    });

    test('多选支持“选中区间”', () {
      expect(manage, contains("case 'select_interval':"));
      expect(manage, contains("value: 'select_interval'"));
    });
  });

  group('书源编辑二维码入口', () {
    test('更多菜单含二维码导入/分享并接通真实逻辑', () {
      expect(editState, contains("title: '二维码导入'"));
      expect(editState, contains('_importFromQr'));
      expect(editState, contains("title: '二维码分享'"));
      expect(editState, contains('_shareQr'));
      expect(editState, contains('QrScannerScreen(title: \'扫码导入书源到编辑\')'));
      expect(editState, contains('QrShareScreen(source: source)'));
    });

    test('二维码导入与粘贴共用 JSON 解析', () {
      expect(editState, contains('_loadFromJsonText'));
      expect(editState, contains("for (final key in ['data', 'bookSources'"));
    });
  });

  group('书源登录动态控件', () {
    test('toggle 按 chars 多状态循环且长按传 isLongClick', () {
      expect(loginState, contains('_parseToggleChars'));
      expect(loginState, contains('_addToggleCycle'));
      expect(loginState, contains('isLongClick: longClick'));
      expect(loginButton, contains('onLongPress: onLongPressed'));
    });

    test('输入框/下拉 action 防抖触发并把结果交给 JS', () {
      expect(loginState, contains('_scheduleFieldAction'));
      expect(loginState, contains('Duration(milliseconds: 600)'));
      expect(loginState, contains('quiet: true'));
      expect(loginState, contains('isLongClick: isLongClick'));
    });

    test('action 为绝对地址时用外部浏览器打开', () {
      expect(loginState, contains("act.startsWith('http://')"));
      expect(loginState, contains('LaunchMode.externalApplication'));
    });

    test('viewName 动态 JS 求值并写入 _form', () {
      expect(loginState, contains('_resolveDynamicLabels'));
      expect(loginState, contains('_dynamicLabels'));
      expect(loginState, contains("m.addAll(_toggleValues)"));
    });
  });

  group('书源调试扫码', () {
    test('菜单含扫码填入调试地址', () {
      expect(debugState, contains("value: 'scan'"));
      expect(debugState, contains("Text('扫码填入调试地址')"));
      expect(debugState, contains('_scanTarget'));
      expect(debugState, contains('QrScannerScreen(title: \'扫码填入调试地址\')'));
    });
  });
}
