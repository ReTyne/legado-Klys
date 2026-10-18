import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:legado_md3/help/source/rule_pipeline.dart';

void main() {
  final html = '''
<html><body>
<div class="booklist">
  <li class="item">
    <a href="/book/1.html"><img src="/cover/1.jpg"/><h2> 第一本书 </h2></a>
    <span class="author">张三</span>
    <span class="intro">简介一</span>
  </li>
  <li class="item">
    <a href="/book/2.html"><h2>第二本书</h2></a>
    <span class="author">李四</span>
  </li>
</div>
<div class="content"><p>正文第一段</p><p>正文第二段 广告</p></div>
</body></html>
''';

  final jsonStr = '''
{"code":0,"data":{"list":[
  {"name":"JSON书1","author":"作者A","cover":"//x.com/a.jpg","bookUrl":"/a"},
  {"name":"JSON书2","author":"作者B","cover":"//x.com/b.jpg","bookUrl":"/b"}
]}}
''';

  group('CSS / 默认规则', () {
    final p = RulePipeline(baseUrl: 'https://www.example.com/source');

    test('CSS 列表 + 相对元素取字段', () {
      final doc = html_parser.parse(html);
      final elements = p.selectElements(doc, '@css:.booklist .item');
      expect(elements.length, 2);
      final first = elements.first;
      expect(p.fieldFromElement(first, '@css:h2@text')?.trim(), '第一本书');
      expect(p.fieldFromElement(first, '@css:.author@text'), '张三');
      expect(p.fieldFromElement(first, '@css:a@href'), '/book/1.html');
    });

    test('默认 JSoup 语法 class/tag + 索引 + @text', () {
      // .0 选取第一个
      expect(p.extractStringFromRaw(html, 'class.booklist@tag.li.0@tag.h2@text'), '第一本书');
      // !0 排除第一个，剩下第二本
      expect(p.extractStringFromRaw(html, 'class.booklist@tag.li!0@tag.h2@text'), '第二本书');
      expect(p.extractStringFromRaw(html, 'class.author@text'), '张三');
    });

    test('## 正则后处理：删除匹配内容', () {
      final r = p.extractStringFromRaw(html, '@css:.content@text##广告');
      expect(r?.contains('广告'), false);
      expect(r?.contains('正文第二段'), true);
    });

    test('|| 或规则取第一个非空', () {
      final r = p.extractStringFromRaw(html, '@css:.nope@text||@css:.author@text');
      expect(r, '张三');
    });

    test('默认规则下含点的 CSS 类选择器不被误判为属性', () {
      final doc = html_parser.parse(html);
      // li.item 是选择步骤而非 getter，应选出 2 个 li
      final elements = p.selectElements(doc, 'li.item');
      expect(elements.length, 2);
      // 纯标识符 href 仍应作为属性 getter；.1 选取第二个 a
      expect(p.extractStringFromRaw(html, 'class.booklist@tag.a.1@href'), '/book/2.html');
    });
  });

  group('XPath', () {
    final p = RulePipeline();
    test('//tag[@class]/text()', () {
      final list = p.extractListFromRaw(html, '//span[@class="author"]/text()');
      expect(list, ['张三', '李四']);
    });
  });

  group('JSON', () {
    final p = RulePipeline(baseUrl: 'https://www.example.com');
    test(r'$. 路径 + 数组通配', () {
      final nodes = p.selectJsonNodes(jsonDecode(jsonStr), r'$.data.list[*]');
      expect(nodes.length, 2);
      expect(p.fieldFromJson(nodes.first, r'$.name'), 'JSON书1');
      expect(p.fieldFromJson(nodes.last, r'$.author'), '作者B');
    });
  });

  group('JS 子集', () {
    final p = RulePipeline();
    test('结尾 @js 清洗', () {
      final r = p.extractStringFromRaw(html, '@css:h2@text@js:result.trim()');
      expect(r, '第一本书');
    });
  });
}
