import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/common/app_name.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('应用显示名本地化', () {
    test('中文环境显示「阅读」', () {
      appLocale = const Locale('zh', 'CN');
      expect(appDisplayName, '阅读');
    });

    test('英文环境显示 legado', () {
      appLocale = const Locale('en');
      expect(appDisplayName, 'legado');
    });

    test('跟随系统（测试环境默认 en）显示 legado', () {
      appLocale = null;
      expect(appDisplayName, 'legado');
    });

    test('其他语言回退 legado', () {
      appLocale = const Locale('ja');
      expect(appDisplayName, 'legado');
    });
  });
}
