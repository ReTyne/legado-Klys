import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/help/source/rule_complete.dart';

///   `help/RuleComplete.kt` 的字符串补全行为。
void main() {
  group('autoComplete 三类 getter', () {
    test('type1 文字补 @text', () {
      expect(RuleComplete.autoComplete('class.item'), 'class.item@text');
      expect(RuleComplete.autoComplete('id.book'), 'id.book@text');
    });

    test('type2 链接补 @href', () {
      expect(RuleComplete.autoComplete('class.item', type: 2),
          'class.item@href');
    });

    test('type3 图片补 @src', () {
      expect(RuleComplete.autoComplete('class.item', type: 3),
          'class.item@src');
    });

    test('已带 getter 不重复补全', () {
      expect(RuleComplete.autoComplete('class.item@text'), 'class.item@text');
      expect(RuleComplete.autoComplete('class.item@html'), 'class.item@html');
      expect(RuleComplete.autoComplete('class.item/text()'),
          'class.item/text()');
      expect(RuleComplete.autoComplete('class.item@href', type: 2),
          'class.item@href');
      expect(RuleComplete.autoComplete('text'), 'text');
      expect(RuleComplete.autoComplete('href'), 'href');
    });

    test('非法 type 原样返回', () {
      expect(RuleComplete.autoComplete('class.item', type: 9), 'class.item');
      expect(RuleComplete.autoComplete('class.item', type: 0), 'class.item');
    });
  });

  group('autoComplete 连接符分段（needComplete 的 seq）', () {
    test('&& 逐段补 getter', () {
      expect(RuleComplete.autoComplete('class.a&&class.b'),
          'class.a@text&&class.b@text');
    });

    test('%% 与 || 同样是分段点', () {
      expect(RuleComplete.autoComplete('class.a%%class.b'),
          'class.a@text%%class.b@text');
      expect(RuleComplete.autoComplete('class.a||class.b'),
          'class.a@text||class.b@text');
    });

    test('只有部分段带 getter 时仅补缺失段', () {
      expect(RuleComplete.autoComplete('class.a@text&&class.b'),
          'class.a@text&&class.b@text');
      expect(RuleComplete.autoComplete('class.a&&class.b@href'),
          'class.a@text&&class.b@href');
    });

    test('连接符后紧跟纯 getter 名不补', () {
      expect(RuleComplete.autoComplete('class.a&&text'),
          'class.a@text&&text');
    });
  });

  group('autoComplete XPath getter 形式', () {
    test('// 开头用 //text() / //@href / //@src', () {
      expect(RuleComplete.autoComplete('//div/a'), '//div/a//text()');
      expect(RuleComplete.autoComplete('//div/a', type: 2),
          '//div/a//@href');
      expect(RuleComplete.autoComplete('//div/img', type: 3),
          '//div/img//@src');
    });

    test('@Xpath: 前缀（大小写不敏感）', () {
      expect(RuleComplete.autoComplete('@Xpath://a'), '@Xpath://a//text()');
      expect(RuleComplete.autoComplete('@XPath://a'), '@XPath://a//text()');
    });

    test('XPath 已带 //text() 不重复补', () {
      expect(RuleComplete.autoComplete('//div/a//text()'),
          '//div/a//text()');
    });
  });

  group('autoComplete 尾部规则保留（细节 1）', () {
    test('尾部 ## 正则替换原样保留在 getter 之后', () {
      expect(RuleComplete.autoComplete('class.item##\\d+##第\$1章'),
          'class.item@text##\\d+##第\$1章');
    });

    test('尾部 ,{ 参数保留', () {
      expect(RuleComplete.autoComplete('class.item,{"a":1}'),
          'class.item@text,{"a":1}');
    });

    test('尾部存在时 getter 不加到尾部内容里', () {
      final out = RuleComplete.autoComplete('class.a##x##y')!;
      expect(out.startsWith('class.a@text##'), isTrue);
      expect(out.endsWith('##@text'), isFalse);
    });
  });

  group('autoComplete 复杂规则跳过（细节 2 / 3）', () {
    test('{{}}、@js:、<js>、@Json:、\$. 一律不补全', () {
      for (final r in [
        '{{key}}@css:.a',
        '@js:result',
        '<js>java.code()</js>',
        '@Json:\$.data',
        '\$.data[*].name',
      ]) {
        expect(RuleComplete.autoComplete(r), r, reason: '应跳过: $r');
      }
    });

    test('以 : 或 ## 开头不补全', () {
      expect(RuleComplete.autoComplete(':regexRule'), ':regexRule');
      expect(RuleComplete.autoComplete('##正则##替换'), '##正则##替换');
    });

    test('preRule 含复杂语法时整条字段不补全', () {
      expect(
        RuleComplete.autoComplete('class.item', preRule: '<js>x</js>'),
        'class.item',
      );
      expect(
        RuleComplete.autoComplete('class.item', preRule: 'class.list@html'),
        'class.item@text',
      );
    });

    test('null / 空串原样返回', () {
      expect(RuleComplete.autoComplete(null), isNull);
      expect(RuleComplete.autoComplete(''), '');
    });
  });

  group('autoComplete 图片取 text 修正为 alt（细节 5 / fixImgInfo）', () {
    test('CSS img.class@text → img.class@alt', () {
      expect(RuleComplete.autoComplete('img.cover@text'), 'img.cover@alt');
    });

    test('CSS img@text → img@alt', () {
      expect(RuleComplete.autoComplete('img@text'), 'img@alt');
    });

    test('XPath img[...]/text() → img[...]/@alt', () {
      expect(RuleComplete.autoComplete('//img[@class=x]/text()'),
          '//img[@class=x]/@alt');
    });

    test('仅 type1 做 alt 修正，链接/图片类型不修正', () {
      expect(RuleComplete.autoComplete('img.cover', type: 3),
          'img.cover@src');
      expect(RuleComplete.autoComplete('img.cover', type: 2),
          'img.cover@href');
    });

    test('非 img 元素不受影响', () {
      expect(RuleComplete.autoComplete('div.cover'), 'div.cover@text');
    });
  });

  group('字段类型与前置规则映射（对齐编辑页 ruleComplete 实参）', () {
    test('图片字段 → 3', () {
      expect(RuleComplete.fieldType('coverUrl'), 3);
      expect(RuleComplete.fieldType('ruleImage'), 3);
    });

    test('URL 字段 → 2', () {
      for (final k in [
        'bookUrl', 'tocUrl', 'chapterUrl', 'nextTocUrl',
        'nextContentUrl', 'ruleNextPage',
      ]) {
        expect(RuleComplete.fieldType(k), 2, reason: k);
      }
    });

    test('文本字段 → 1', () {
      for (final k in [
        'name', 'author', 'intro', 'kind', 'wordCount', 'lastChapter',
        'chapterName', 'content', 'title', 'subContent', 'downloadUrls',
        'ruleTitle', 'rulePubDate', 'ruleDescription', 'ruleLink',
        'ruleContent',
      ]) {
        expect(RuleComplete.fieldType(k), 1, reason: k);
      }
    });

    test('列表/JS/开关字段不补全', () {
      for (final k in [
        'bookList', 'chapterList', 'init', 'ruleArticles',
        'preUpdateJs', 'formatJs', 'imageStyle', 'webJs',
        'isVip', 'canReName', 'replaceRegex',
      ]) {
        expect(RuleComplete.fieldType(k), isNull, reason: k);
      }
    });

    test('preRuleKey 与上游 preRule 实参一致', () {
      expect(RuleComplete.preRuleKey('ruleSearch'), 'bookList');
      expect(RuleComplete.preRuleKey('ruleExplore'), 'bookList');
      expect(RuleComplete.preRuleKey('ruleBookInfo'), 'init');
      expect(RuleComplete.preRuleKey('ruleToc'), 'chapterList');
      expect(RuleComplete.preRuleKey('ruleContent'), isNull);
    });
  });

  group('真实书源片段端到端', () {
    test('搜索书名规则', () {
      expect(
        RuleComplete.autoComplete('class.book-name'),
        'class.book-name@text',
      );
    });

    test('详情页目录 URL 规则', () {
      expect(
        RuleComplete.autoComplete('tag.a@href', type: 2),
        'tag.a@href',
      );
      expect(
        RuleComplete.autoComplete('tag.a', type: 2),
        'tag.a@href',
      );
    });

    test('带多段与尾部的组合', () {
      expect(
        RuleComplete.autoComplete('class.a||class.b##\\s+##'),
        'class.a@text||class.b@text##\\s+##',
      );
    });
  });
}
