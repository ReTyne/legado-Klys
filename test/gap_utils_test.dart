import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/help/source/js_text_utils.dart';
import 'package:legado_md3/help/source/rule_pipeline.dart';
import 'package:legado_md3/utils/alphanum_comparator.dart';
import 'package:legado_md3/utils/chinese_utils.dart';
import 'package:legado_md3/utils/url_edge.dart';

void main() {
  group('自然排序：等长数字块逐位比较', () {
    test('数字块按对应位比较而非恒取第 0 位', () {
      expect(AlphanumComparator.compare('12', '13'), lessThan(0));
      expect(AlphanumComparator.compare('13', '12'), greaterThan(0));
      expect(AlphanumComparator.compare('12', '12'), 0);
    });

    test('排序结果符合数值顺序', () {
      expect(
        AlphanumComparator.naturalSorted(['13', '12', '10', '2']),
        ['2', '10', '12', '13'],
      );
      expect(
        AlphanumComparator.naturalSorted(['file10.txt', 'file2.txt']),
        ['file2.txt', 'file10.txt'],
      );
    });
  });

  group('正则：捕获组边界与链式拼接', () {
    test('firstMatch 可取到最后一个捕获组', () {
      expect(RegexParser.firstMatch('abc123', r'([a-z]+)(\d+)', group: 2),
          '123');
      expect(RegexParser.firstMatch('abc123', r'([a-z]+)(\d+)', group: 1),
          'abc');
      expect(RegexParser.firstMatch('abc123', r'([a-z]+)(\d+)', group: 0),
          'abc123');
      // 越界分组仍回退到整个匹配
      expect(RegexParser.firstMatch('abc123', r'([a-z]+)', group: 3), 'abc');
    });

    test('matchChain 中间结果直接拼接，不插入换行', () {
      final result = RegexParser.matchChain([r'[a-z]+', r'(.)'], 'ab12cd');
      expect(result.length, 4);
      expect(result.map((e) => e[0]).toList(), ['a', 'b', 'c', 'd']);
      expect(result.every((e) => !e[0].contains('\n')), isTrue);
    });
  });

  group('HTML 图片归一化', () {
    test('无 baseUrl 时行为保持兼容', () {
      expect(JsTextUtils.htmlFormat('<img src="/a.jpg">'),
          '<img src="/a.jpg">');
    });

    test('相对 src 基于 baseUrl / redirectUrl 绝对化', () {
      expect(
        JsTextUtils.htmlFormat('<img src="/a.jpg">',
            baseUrl: 'http://h.com/book/'),
        '<img src="http://h.com/a.jpg">',
      );
      expect(
        JsTextUtils.htmlFormat('<img src="/a.jpg">',
            baseUrl: 'http://h.com/book/',
            redirectUrl: 'http://r.com/next/'),
        '<img src="http://r.com/a.jpg">',
      );
    });

    test('懒加载属性优先取真图', () {
      expect(
        JsTextUtils.htmlFormat('<img src="ph.gif" data-src="/real.jpg">',
            baseUrl: 'http://h.com/'),
        '<img src="http://h.com/real.jpg">',
      );
    });

    test('嵌套花括号规则参数保留在 src 中', () {
      expect(
        JsTextUtils.htmlFormat(r'<img src="/img/a.jpg,{{$.x}}">',
            baseUrl: 'http://h.com/book/'),
        r'<img src="http://h.com/img/a.jpg,{{$.x}}">',
      );
      expect(
        JsTextUtils.htmlFormat(r'<img src="{{$.x}}">'),
        r'<img src="{{$.x}}">',
      );
    });
  });

  group('请求参数编码', () {
    test('escape 字符集按 UTF-16 码元输出 %uXXXX', () {
      expect(encodeParams({'q': '中文'}, charset: 'escape'), 'q=%u4E2D%u6587');
      expect(encodeParams({'e': '😀'}, charset: 'escape'), 'e=%uD83D%uDE00');
      expect(encodeParams({'s': 'a b&'}, charset: 'escape'), 's=a%20b%26');
    });

    test('非 escape 字符集保持原有空格与 UTF-8 编码', () {
      expect(encodeParams({'s': 'a b'}, charset: 'utf-8'), 's=a+b');
      expect(encodeParams({'q': '中文'}, charset: 'utf-8'),
          'q=%E4%B8%AD%E6%96%87');
    });

    test('已编码值不重复编码', () {
      expect(encodeParams({'q': '%E4%B8%AD'}, charset: 'utf-8'), 'q=%E4%B8%AD');
    });
  });

  group('繁转简排除词表', () {
    test('两岸差异词保持原样', () {
      expect(ChineseUtils.t2s('雪梨'), '雪梨');
      expect(ChineseUtils.t2s('光碟'), '光碟');
      expect(ChineseUtils.t2s('磁碟'), '磁碟');
      expect(ChineseUtils.t2s('在雪梨买光碟'), '在雪梨买光碟');
    });

    test('非排除词仍正常转换', () {
      expect(ChineseUtils.t2s('臺灣'), '台湾');
      expect(ChineseUtils.t2s('資訊'), '信息');
    });
  });
}
