import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:legado_md3/help/source/rule_pipeline.dart';

void main() {
  final p = RulePipeline();
  const html = '''<html><body><table>
<tr><td><a href="/novel/1/1.htm">第一章 起源</a></td></tr>
<tr><td><a href="/novel/1/2.htm">第二章 觉醒</a></td></tr>
</table></body></html>''';

  test('chapterList td@a 选择元素', () {
    final els = p.selectElements(html_parser.parse(html), 'td@a');
    print('td@a -> ${els.length} 个元素');
    for (final e in els) {
      print('  tag=${e.localName} href=${e.attributes['href']} text=${e.text.trim()}');
    }
    expect(els.length, 2);
    expect(els.every((e) => e.localName == 'a'), isTrue, reason: 'td@a 应选中 a 元素');
  });

  test('裸 href 规则提取属性', () {
    final els = p.selectElements(html_parser.parse(html), 'td@a');
    for (final e in els) {
      final v = p.fieldFromElement(e, 'href');
      print('fieldFromElement(href) -> "$v"');
      final t = p.fieldFromElement(e, 'text');
      print('fieldFromElement(text) -> "$t"');
    }
  });

  test('parse 树形态', () {
    final d = html_parser.parse('<a href="/x">t</a>');
    print('doc children: ${d.children.map((c) => c.localName).toList()}');
    final first = d.children.isNotEmpty ? d.children.first : null;
    print('first: ${first?.localName} attrs=${first?.attributes}');
    final d2 = html_parser.parse('<td><a href="/y">tt</a></td>');
    print('doc2 children: ${d2.children.map((c) => c.localName).toList()}');
    final f2 = d2.children.isNotEmpty ? d2.children.first : null;
    print('first2: ${f2?.localName} attrs=${f2?.attributes}');
  });

  test('extractListFromRaw 裸 href', () {
    final els = p.selectElements(html_parser.parse(html), 'td@a');
    for (final e in els) {
      print('extractListFromRaw(href): ${p.extractListFromRaw(e.outerHtml, 'href')}');
      print('extractListFromRaw(td@a@href): ${p.extractListFromRaw(e.outerHtml, 'td@a@href')}');
    }
  });
}
