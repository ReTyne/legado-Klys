import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/data/model/read_config.dart';

String src(String p) => File(p).readAsStringSync();

void main() {
  group('keep_light 五档（对齐 legado-E pref_config_read.xml）', () {
    test('默认 0（跟随系统），toJson/fromJson 往返保真', () {
      final c = ReadConfig();
      expect(c.keepLight, 0);
      for (final v in const [0, 60, 300, 600, -1]) {
        final c2 = ReadConfig.fromJson({'keepLight': v});
        expect(c2.keepLight, v);
        expect(ReadConfig.fromJson(c2.toJson()).keepLight, v);
      }
    });

    test('旧配置缺字段或非法值回退 0', () {
      expect(ReadConfig.fromJson({}).keepLight, 0);
      expect(ReadConfig.fromJson({'keepLight': '60'}).keepLight, 60);
      expect(ReadConfig.fromJson({'keepLight': 'abc'}).keepLight, 0);
      expect(ReadConfig.fromJson({'keepLight': null}).keepLight, 0);
    });

    test('设置页提供全部 5 档', () {
      final s = src('lib/ui/book/read/config/reading_settings_screen.dart');
      expect(s, contains('keep_light'));
      for (final v in const ['0', '60', '300', '600', '-1']) {
        expect(s, contains('value: $v,'), reason: '缺少档位 $v');
      }
    });
  });

  group('上游默认值契约（此前 5 项全部反向）', () {
    test('antiAlias=false / autoClearExpired=true', () {
      expect(src('lib/ui/config/other_config_screen.dart'),
          contains("p.getBool('oc_antiAlias') ?? false"));
      expect(src('lib/ui/config/other_config_screen.dart'),
          contains("p.getBool('oc_autoClearExpired') ?? true"));
      expect(src('lib/main.dart'),
          contains("prefs.getBool('oc_autoClearExpired') ?? true"));
      expect(src('lib/ui/book/read/reading_screen.dart'),
          contains('_antiAlias = p.getBool(\'oc_antiAlias\') ?? false'));
    });

    test('progressBarBehavior=page / mouseWheelPage=true / expandTextMenu=false', () {
      for (final f in const [
        'lib/ui/book/read/reading_screen.dart',
        'lib/ui/book/read/config/reading_settings_screen.dart',
      ]) {
        final s = src(f);
        expect(s, contains("String _progressBarBehavior = 'page'"), reason: f);
        expect(s, contains('bool _mouseWheelPage = true'), reason: f);
        expect(s, contains('bool _expandTextMenu = false'), reason: f);
        expect(s, contains("fallback: 'page'"), reason: f);
        expect(s, contains('kMouseWheelPage, fallback: true'), reason: f);
        expect(s, contains('kExpandTextMenu, fallback: false'), reason: f);
      }
    });
  });
}
