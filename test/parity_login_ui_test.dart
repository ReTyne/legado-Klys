import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 书源 loginUi 控件解析：兼容 toggle/switch 两种开关写法、
/// options/chars 两种下拉选项写法，并尊重 default / viewName 字段。
void main() {
  final file = File('lib/ui/book/source/parts/source_login_screen_state.dart');
  late String src;
  setUpAll(() => src = file.readAsStringSync());

  group('loginUi 控件兼容', () {
    test('开关类型同时接受 switch 与 toggle', () {
      expect(src, contains("type == 'switch' || type == 'toggle'"));
    });

    test('下拉选项同时接受 options 与 chars', () {
      expect(src, contains("item['options'] ?? item['chars']"));
    });

    test('尊重 default 默认值字段', () {
      expect(src, contains("item['default']"));
      // 开关、下拉、文本三处都读取 default
      final hits = "item['default']".allMatches(src).length;
      expect(hits, greaterThanOrEqualTo(3));
    });

    test('标题回退到 viewName', () {
      expect(src, contains("item['viewName']"));
    });

    test('选项解析支持名称::值与名称=值写法', () {
      expect(src, contains("t.contains('::')"));
      expect(src, contains("t.contains('=')"));
    });

    test('选项解析支持字符串按逗号/换行拆分', () {
      expect(src, contains(r"RegExp(r'[,，\r\n]+')"));
    });

    test('原有 options 对象数组解析仍保留', () {
      expect(src, contains("e['name'] ?? e['value']"));
      expect(src, contains('_parseSelectOptions'));
    });
  });
}
