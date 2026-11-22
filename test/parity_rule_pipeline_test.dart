import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:legado_md3/help/source/json_path.dart';
import 'package:legado_md3/help/source/rule_data.dart';
import 'package:legado_md3/help/source/rule_pipeline.dart';
import 'package:legado_md3/help/source/url_option.dart';
import 'package:legado_md3/help/source/xpath_selector.dart';
import 'package:legado_md3/utils/url_edge.dart';

void main() {
  // 1. 统一变量存储
  group('1 RuleData 分层变量与会话共享', () {
    test('分层读取按 chapter → book → ruleData → source 优先', () {
      final d = RuleData();
      d.putInLayer('source', 'k', 'src');
      d.putInLayer('book', 'k', 'bk');
      d.putInLayer('ruleData', 'k', 'rd');
      d.putInLayer('chapter', 'k', 'ch');
      expect(d.getVariable('k'), 'ch');
      d.putInLayer('chapter', 'k', ''); // 空值跳过，回退到下一层
      expect(d.getVariable('k'), 'bk');
    });

    test('长度 >=10000 的值进入外置大变量存储', () {
      final d = RuleData();
      final big = 'x' * 10000;
      d.putVariable('big', big);
      expect(d.getBigVariable('big').length, 10000);
      expect(d.getVariable('big').length, 10000);
      expect(d.variableMap['big']?.length, 10000);
    });

    test('variableMapJson 导出与 clear 清空', () {
      final d = RuleData();
      d.put('a', '1');
      d.putInLayer('source', 's', 'S');
      final decoded = jsonDecode(d.variableMapJson) as Map;
      expect(decoded['a'], '1');
      expect(decoded['s'], 'S');
      d.clear();
      expect(d.variableMap, isEmpty);
      expect(d.get('a'), '');
    });

    test('bindToPipeline / readForJs / writeForJs 共享同一变量表', () {
      final data = RuleDataScope.begin();
      final p = RulePipeline();
      RuleData.bindToPipeline(p);
      RuleData.writeForJs(p, 'token', 'abc');
      expect(p.variables['token'], 'abc');
      expect(data.get('token'), 'abc');
      p.variables['fromRule'] = 'xyz'; // 规则侧直接写
      expect(RuleData.readForJs(p, 'fromRule'), 'xyz');
      expect(data.ruleDataLayer['fromRule'], 'xyz');
    });

    test('RuleDataScope.begin 开启独立会话', () {
      final a = RuleDataScope.current;
      a.put('k', 'v');
      final b = RuleDataScope.begin();
      expect(identical(a, b), isFalse);
      expect(b.get('k'), '');
    });
  });

  // 2. $N 内联捕获组引用
  group(r'2 $N 捕获组内联系引', () {
    final p = RulePipeline();

    test('expandCaptures 按序号内联拼回', () {
      expect(p.expandCaptures(r'pre$1-$2post', ['ALL', 'G1', 'G2']),
          'preG1-G2post');
    });

    test('空捕获组与越界引用替换为空，无分组时移除引用', () {
      expect(p.expandCaptures(r'a$1b$9c', ['ALL', '']), 'abc');
      expect(p.expandCaptures(r'x$1y', null), 'xy');
    });

    test(r'链式规则内 $N 引用前段分组并强制按正则求值', () {
      final list = p.extractListFromRaw('x5yy 42yy', r':x(\d+)&&$1yy');
      expect(list, contains('5yy'));
    });
  });

  // 3. 链式正则
  group('3 链式正则', () {
    test('matchChain 中间段拼接全匹配、末段返回分组数组', () {
      final groups =
          RegexParser.matchChain([r'\d+', r'(\d)(\d)'], 'a12 b34 c56');
      expect(groups.length, 3);
      expect(groups[0][0], '12');
      expect(groups[0][1], '1');
      expect(groups[0][2], '2');
    });

    test('_regexValues 支持 :正则&&正则 形式', () {
      final p = RulePipeline();
      final list = p.extractListFromRaw('a=12;b=34', r':(\d+)&&(\d)');
      expect(list, isNotEmpty);
      expect(list, contains('1'));
      expect(list, contains('4'));
    });
  });

  // 4. 平衡切分器
  group('4 平衡切分器', () {
    final p = RulePipeline();

    test('混合连接符以首个命中的连接符统一定性', () {
      expect(p.ruleDominantConnector('a&&b||c'), '&&');
      expect(p.splitRuleBalanced('a&&b||c'), ['a', 'b||c']);
    });

    test('引号内连接符不参与切分', () {
      expect(p.splitRuleBalanced("a'&&'b&&c"), ["a'&&'b", 'c']);
    });

    test('括号或引号不平衡时抛出带信息的 FormatException', () {
      expect(
          () => p.splitRuleBalanced('a[||b'), throwsA(isA<FormatException>()));
      expect(() => p.splitRuleBalanced('a{b'), throwsA(isA<FormatException>()));
    });
  });

  // 5. {$.…} 内联 JSONPath
  group(r'5 {$.…} 内联 JSONPath', () {
    test('expandInnerRules 先求值再拼回规则串', () {
      final root = jsonDecode('{"a":{"b":"B"},"c":9}');
      final expanded = JsonPath.expandInnerRules(r'x{$.a.b}y{$.c}z', (path) {
        final v = JsonPath.selectFirst(root, path);
        return v == null ? '' : v.toString();
      });
      expect(expanded, 'xBy9z');
    });
  });

  // 6. JSONPath 增强
  group('6 JSONPath 增强', () {
    final root = jsonDecode('{"list":[10,20,30,40,50],"a":1,"b":2}') as Map;

    test('切片 [start:end] 与省略端点 / 步长', () {
      expect(JsonPath.select(root, r'$.list[1:3]'), [20, 30]);
      expect(JsonPath.select(root, r'$.list[:2]'), [10, 20]);
      expect(JsonPath.select(root, r'$.list[::2]'), [10, 30, 50]);
    });

    test(r"['a','b'] 联合、通配、length()", () {
      expect(JsonPath.select(root, r'$["a","b"]'), [1, 2]);
      final all = JsonPath.select(root, r'$.*');
      expect(all.length, 3);
      expect(all, contains(1));
      expect(all, contains(2));
      expect(JsonPath.selectFirst(root, r'$.list.length()'), 5);
    });

    test(r'$..key 递归下降与 || 多路径保持', () {
      final nested = jsonDecode('{"x":{"name":"A"},"y":[{"name":"B"}]}');
      expect(JsonPath.select(nested, r'$..name'), ['A', 'B']);
      expect(JsonPath.selectString(root, r'$.nope||$.a'), '1');
    });

    test('过滤器 == 与 <', () {
      final data = jsonDecode(
          '{"items":[{"name":"a","price":5},{"name":"b","price":15},{"name":"c","price":9}]}');
      expect(JsonPath.select(data, r'$.items[?(@.price<10)]').length, 2);
      expect(JsonPath.select(data, r"$.items[?(@.name=='b')]").length, 1);
    });
  });

  // 7. XPath 增强
  group('7 XPath 增强', () {
    const xhtml =
        '<ul><li id="a" class="x">A1 A2</li><li id="b" class="y">B</li><li id="c">C</li></ul>';

    test('| 联合去重', () {
      final r = XpathSelector.selectText(
          xhtml, r'//li[@id="a"]/text() | //li[@id="c"]/text()');
      expect(r, ['A1 A2', 'C']);
    });

    test('following-sibling / preceding-sibling 兄弟轴', () {
      expect(
          XpathSelector.selectText(
              xhtml, r'//li[@id="a"]/following-sibling::li/text()'),
          ['B', 'C']);
      expect(
          XpathSelector.selectText(
              xhtml, r'//li[@id="c"]/preceding-sibling::li/text()'),
          ['A1 A2', 'B']);
    });

    test('string(.) / normalize-space() / count()', () {
      expect(
          XpathSelector.selectText(xhtml, r'string(//li[@id="a"])'), ['A1 A2']);
      expect(
          XpathSelector.selectText(
              '<p>  a   b \n c  </p>', r'normalize-space(//p)'),
          ['a b c']);
      expect(XpathSelector.selectText(xhtml, r'count(//li)'), ['3']);
    });

    test('position() / last() / not()', () {
      expect(XpathSelector.selectText(xhtml, r'//li[position()<=2]/text()'),
          ['A1 A2', 'B']);
      expect(XpathSelector.selectText(xhtml, r'//li[last()]/text()'), ['C']);
      expect(
          XpathSelector.selectText(xhtml, r'//li[not(@class)]/text()'), ['C']);
    });

    test('谓词 and/or 与 contains / starts-with', () {
      expect(
          XpathSelector.selectText(
              xhtml, r'//li[@class="x" or @id="c"]/text()'),
          ['A1 A2', 'C']);
      expect(
          XpathSelector.selectText(xhtml, r'//li[contains(text(),"A")]/text()'),
          ['A1 A2']);
      expect(
          XpathSelector.selectText(xhtml, r'//li[starts-with(@id,"b")]/text()'),
          ['B']);
    });
  });

  // 8. 索引语法
  group('8 索引语法', () {
    const idxHtml =
        '<div class="row"><span>0</span><span>1</span><span>2</span><span>3</span><span>4</span></div>';
    final p = RulePipeline();

    test('[start:end:step] 步长与省略端点', () {
      expect(p.extractStringFromRaw(idxHtml, r'class.row@tag.span[::2]@text'),
          '0\n2\n4');
      expect(p.extractStringFromRaw(idxHtml, r'class.row@tag.span[:3]@text'),
          '0\n1\n2');
    });

    test('负 step 反向', () {
      expect(p.extractStringFromRaw(idxHtml, r'class.row@tag.span[::-1]@text'),
          '4\n3\n2\n1\n0');
    });

    test('! 前缀排除与旧式 tag.span.-1:10:2 多索引', () {
      expect(p.extractStringFromRaw(idxHtml, r'class.row@tag.span[!0,4]@text'),
          '1\n2\n3');
      expect(
          p.extractStringFromRaw(idxHtml, r'class.row@tag.span.-1:10:2@text'),
          '4');
    });
  });

  // 9. HTML 实体反转义与取首条
  group('9 HTML 实体反转义与 getString0', () {
    final p = RulePipeline();

    test('unescapeHtml4 覆盖命名实体与数字实体', () {
      expect(unescapeHtml4(r'a&amp;b &lt;x&gt; &#20320;&#x597D; &nbsp;'),
          'a&b <x> 你好 \u00A0');
    });

    test('extractStringFromRaw 的 unescape 可选参数', () {
      const raw = r'title: Tom&amp;Jerry';
      expect(p.extractStringFromRaw(raw, r':title: (\S+)$1'), 'Tom&amp;Jerry');
      expect(p.extractStringFromRaw(raw, r':title: (\S+)$1', unescape: true),
          'Tom&Jerry');
    });

    test('firstStringFromRaw 只取首条', () {
      const raw = 'a=1\na=2\na=3';
      expect(p.firstStringFromRaw(raw, r':a=(\d+)'), 'a=1');
      expect(p.extractStringFromRaw(raw, r':a=(\d+)'), 'a=1\na=2\na=3');
    });
  });

  // 10. getter 独立方法
  group('10 getter 独立方法', () {
    final p = RulePipeline();

    test('joinedHtmlAll 拼 outerHtml 单值并移除 script/style', () {
      const html =
          '<div class="a"><p>one<script>bad()</script></p></div><div class="a"><style>x{}</style><p>two</p></div>';
      final out = p.joinedHtmlAll(html, '@css:.a');
      expect(out.contains('script'), isFalse);
      expect(out.contains('style'), isFalse);
      expect(out.contains('one'), isTrue);
      expect(out.contains('two'), isTrue);
    });

    test('ownTextOf 只取直系文本', () {
      final doc = html_parser.parse('<div id="d">Hello <b>Bold</b> Tail</div>');
      final o = p.ownTextOf(doc.getElementById('d')!);
      expect(o, contains('Hello'));
      expect(o, isNot(contains('Bold')));
    });

    test('attributeValues 去重去空', () {
      final doc = html_parser.parse('<div><a href="/1"></a><a href="/1"></a>'
          '<a href=""></a><a href="/2"></a></div>');
      expect(
          p.attributeValues(doc.querySelectorAll('a'), 'href'), ['/1', '/2']);
    });
  });

  // 11. URL 编码链接线
  group('11 URL 编码链接线', () {
    test('encodeParams URLEncoder 语义、escape 百分号大写、已编码不重复', () {
      expect(encodeParams({'q': 'a b', 'n': 7}), 'q=a+b&n=7');
      expect(encodeParams({'q': 'a b'}, charset: 'escape'), 'q=a%20b');
      expect(
          encodeParams({'q': '你好'}, charset: 'escape'), 'q=%u4F60%u597D');
      expect(encodeParams({'q': 'a%20b'}), 'q=a%20b');
    });

    test('getAbsoluteURL 保持四类分支并补 redirectUrl 优先级', () {
      expect(getAbsoluteURL('http://a.com', 'p'), 'http://a.com/p');
      expect(
          getAbsoluteURL('http://a.com', 'p', redirectUrl: 'http://b.com/dir/'),
          'http://b.com/dir/p');
    });

    test('UrlOptions 的 urlNoQuery / encodedQuery / encodedForm / escape', () {
      final u = UrlOptions.parse(
          'https://a.com/s?x=1&y=2,{"charset":"escape","body":"q=a b"}');
      expect(u.urlNoQuery, 'https://a.com/s');
      expect(u.isEscapeCharset, isTrue);
      expect(u.escapeEncodedBody, 'q=a%20b');

      final u2 =
          UrlOptions.parse('https://a.com/s?q=a%20b,{"body":"hello%20world"}');
      expect(u2.encodedQuery, isTrue);
      expect(u2.encodedForm, isTrue);

      expect(UrlOptions.parse('https://a.com/s?q=a b').encodedQuery, isFalse);
    });
  });

  // 12. webJs 模式
  group('12 RuleMode.webJs', () {
    test('modeOf 识别 @webjs: 前缀且求值不报错', () {
      final p = RulePipeline();
      expect(p.modeOf('@webjs:return result;'), RuleMode.webJs);
      expect(p.extractListFromRaw('<html></html>', '@webjs:return result;'),
          isEmpty);
    });
  });
}
