import 'package:flutter_test/flutter_test.dart';

import 'package:legado_md3/data/model/read_config.dart';
import 'package:legado_md3/ui/book/chapter/chapter_list_screen.dart';

void main() {
  group('ReadConfig 页眉三槽位字段', () {
    test('默认值为经典页眉且三槽位带默认值', () {
      final config = ReadConfig();
      expect(config.headerMode, 0);
      expect(config.headerSlots, defaultHeaderSlots);
      expect(config.headerSlots!.length, 3);
      expect(config.tipColor, 0xFF6B6B6B);
      expect(config.tipDividerColor, 0xFFE0E0E0);
      expect(config.titleSize, 12);
      expect(config.titleTopSpacing, 0);
      expect(config.titleBottomSpacing, 0);
    });

    test('页眉字段可 toJson/fromJson 往返', () {
      final config = ReadConfig(
        headerMode: 1,
        headerSlots: const [
          FooterSlot.bookName,
          FooterSlot.time,
          FooterSlot.batteryPercent,
        ],
        tipColor: 0xFF112233,
        tipDividerColor: 0xFF445566,
        titleSize: 18,
        titleTopSpacing: 4,
        titleBottomSpacing: 8,
        useZhLayout: false,
        textFullJustify: true,
        textBottomJustify: true,
      );
      final json = config.toJson();
      expect(json['headerSlots'], [
        FooterSlot.bookName.index,
        FooterSlot.time.index,
        FooterSlot.batteryPercent.index,
      ]);
      expect(json['headerMode'], 1);
      expect(json['tipColor'], 0xFF112233);

      final restored = ReadConfig.fromJson(json);
      expect(restored.headerMode, 1);
      expect(restored.headerSlots, config.headerSlots);
      expect(restored.tipColor, 0xFF112233);
      expect(restored.tipDividerColor, 0xFF445566);
      expect(restored.titleSize, 18);
      expect(restored.titleTopSpacing, 4);
      expect(restored.titleBottomSpacing, 8);
      expect(restored.useZhLayout, false);
      expect(restored.textFullJustify, true);
      expect(restored.textBottomJustify, true);
    });

    test('旧配置缺少页眉字段时回退默认值', () {
      final restored = ReadConfig.fromJson({});
      expect(restored.headerMode, 0);
      expect(restored.headerSlots, defaultHeaderSlots);
      expect(restored.useZhLayout, true);
      expect(restored.textFullJustify, false);
      expect(restored.textBottomJustify, false);
    });

    test('越界槽位索引被钳回合法枚举，不抛异常', () {
      final restored = ReadConfig.fromJson({
        'headerSlots': [99, 0, -5],
        'headerMode': 99,
      });
      expect(restored.headerSlots!.length, 3);
      expect(
        restored.headerSlots!.every((s) => FooterSlot.values.contains(s)),
        isTrue,
      );
      expect(restored.headerMode, 1);
    });
  });

  group('章节字数过滤统计', () {
    test('过滤 HTML 标签、标点与空白', () {
      expect(countEffectiveWords('<p>春天来了，花儿开了。</p>'), 8);
      expect(countEffectiveWords('Hello, World! 123'), 13);
      expect(countEffectiveWords('   \n\t'), 0);
      expect(countEffectiveWords(null), 0);
      expect(countEffectiveWords(''), 0);
    });

    test('中英混排按码点计数', () {
      expect(countEffectiveWords('阅读abc测试'), 7);
    });
  });
}
