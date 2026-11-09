import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// UI 重构源码契约：锁定「页面已接入统一三态组件 / 设计令牌 / 加载态收敛」，
/// 防止后续功能迭代把公共组件重新退化成散落的内联样板。
String _src(String rel) => File('lib/ui/$rel').readAsStringSync();

void main() {
  group('UI 重构契约 · 三态组件落地', () {
    const asyncPages = <String>[
      'config/txt_toc_rule_screen.dart',
      'config/replace_rule_screen.dart',
      'config/cover_album_screen.dart',
      'config/dict_rule_screen.dart',
      'config/tag_group_rule_screen.dart',
    ];

    for (final page in asyncPages) {
      test('$page 使用 AppAsyncState 统一加载/空/数据三态', () {
        final s = _src(page);
        expect(s, contains('AppAsyncState('));
        expect(s, isNot(contains('? const AppLoadingIndicator()')),
            reason: '$page 不应再内联加载态三元分支');
      });
    }

    test('标签分组规则页同时接入响应式限宽容器', () {
      final s = _src('config/tag_group_rule_screen.dart');
      expect(s, contains('AppAdaptiveBody('));
      expect(s, contains('AppAsyncState('));
    });
  });

  group('UI 重构契约 · 设计令牌', () {
    test('app_widgets.dart 统一导出设计令牌库', () {
      expect(File('lib/ui/widgets/app_widgets.dart').readAsStringSync(),
          contains("export '../theme/app_design.dart'"));
    });

    const tokenPages = <String>[
      'config/txt_toc_rule_screen.dart',
      'config/replace_rule_screen.dart',
      'config/cover_album_screen.dart',
      'config/dict_rule_screen.dart',
      'config/tag_group_rule_screen.dart',
      'config/highlight_tag_rule_screen.dart',
    ];
    for (final page in tokenPages) {
      test('$page 使用 AppSpacing/AppRadius 令牌', () {
        final s = _src(page);
        expect(s.contains('AppSpacing.') || s.contains('AppRadius.'), isTrue,
            reason: '$page 不应继续散落硬编码间距/圆角');
      });
    }
  });

  group('UI 重构契约 · 加载态收敛', () {
    test('UI 层无裸 Center(child: CircularProgressIndicator()) 残留', () {
      final re = RegExp(
          r'Center\(\s*child:\s*(?:const\s+)?CircularProgressIndicator\(\)');
      final left = <String>[];
      for (final entity in Directory('lib/ui').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        // 组件自身定义允许保留 Center(child: progress)。
        if (entity.path.endsWith('app_common.dart')) continue;
        if (re.hasMatch(entity.readAsStringSync())) left.add(entity.path);
      }
      expect(left, isEmpty,
          reason: '裸加载态应统一收敛到 AppLoadingIndicator');
    });
  });

  group('UI 重构契约 · 设计令牌规模化', () {
    test('设计令牌覆盖 ≥ 95 个 UI 文件', () {
      final files = Directory('lib/ui')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) =>
              f.path.endsWith('.dart') && !f.path.endsWith('app_design.dart'))
          .toList();
      final covered = files.where((f) {
        final s = f.readAsStringSync();
        return s.contains('AppSpacing.') || s.contains('AppRadius.');
      }).length;
      expect(covered, greaterThanOrEqualTo(95),
          reason: '设计令牌应规模化覆盖 UI 层，实际 $covered/${files.length}');
    });

    test('UI 层不再残留 4pt 阶梯硬编码间距', () {
      final re = RegExp(
          r'EdgeInsets\.all\(\s*(?:4|8|12|16|24|32|48)\s*\)'
          r'|SizedBox\(\s*(?:height|width)\s*:\s*(?:4|8|12|16|24|32|48)\s*\)');
      final left = <String>[];
      for (final entity in Directory('lib/ui').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (re.hasMatch(entity.readAsStringSync())) left.add(entity.path);
      }
      expect(left, isEmpty,
          reason: '4pt 栅格间距应统一收敛到 AppSpacing 令牌');
    });
  });
}
