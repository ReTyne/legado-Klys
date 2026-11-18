import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:legado_md3/help/source/rule_pipeline.dart';

/// 用社区真实书源里的规则片段 + 罐头响应，验证规则引擎能真实求值
/// （不只是"能解析字符串"），证明这批书源的规则语法在 K 版可用。
/// 抽取自 yck2026.fun 源仓库 29 个书源中的代表性纯规则（CSS / JSONPath /
/// 正则），全部离线确定性执行，不依赖网络或 WebView。
void main() {
  const fixtureDir = 'test/fixtures/community';
  final p = RulePipeline();

  Map<String, dynamic> load(String id) {
    final d = jsonDecode(File('$fixtureDir/source_$id.json').readAsStringSync());
    final m = d is List ? d.first : d;
    return (m as Map).cast<String, dynamic>();
  }

  group('真实书源 JSONPath 规则求值', () {
    // 8103 淘小说API：bookList=$.data.bookList / name=$.title / author=$.authorName
    test('8103: JSONPath 列表 + 字段规则从真实规则求值', () {
      final rs = load('8103')['ruleSearch'] as Map<String, dynamic>;
      expect(rs['bookList'], r'$.data.bookList');
      expect(rs['name'], r'$.title');
      const canned =
          '{"data":{"bookList":[{"title":"斗破苍穹","authorName":"天蚕土豆"}]}}';
      final list = p.selectJsonNodes(jsonDecode(canned), rs['bookList'] as String);
      expect(list, isNotEmpty);
      expect(p.fieldFromJson(list.first, rs['name'] as String), '斗破苍穹');
      expect(p.fieldFromJson(list.first, rs['author'] as String), '天蚕土豆');
    });

    // 8104 青橙小说API：name=$.name / author=$.author / coverUrl=$.coverUrl
    test('8104: JSONPath 字段规则逐个求值', () {
      final rs = load('8104')['ruleSearch'] as Map<String, dynamic>;
      const canned =
          '{"name":"遮天","author":"辰东","bookUrl":"/b/1","coverUrl":"/c.jpg"}';
      final node = jsonDecode(canned);
      expect(p.fieldFromJson(node, rs['name'] as String), '遮天');
      expect(p.fieldFromJson(node, rs['author'] as String), '辰东');
      expect(p.fieldFromJson(node, rs['coverUrl'] as String), '/c.jpg');
    });

    // 7713 UAA：ruleExplore 用 @json: 前缀 + $.model.data
    test('7713: @json: 前缀 + JSONPath 列表规则', () {
      final re = load('7713')['ruleExplore'] as Map<String, dynamic>;
      expect(re['bookList'], contains('@json:'));
      const canned = '{"model":{"data":[{"bookName":"诡秘之主"}]}}';
      final list = p.extractListFromRaw(canned, re['bookList'] as String);
      expect(list, isNotEmpty);
    });
  });

  group('真实书源 CSS 规则求值', () {
    // 8123 书海阁：bookList=article.classBookCard / name=.classBookTitle a@text
    const cannedHtml = '''
      <article class="classBookCard">
        <div class="classBookTitle"><a href="/book/1">逆水寒</a></div>
        <div class="classBookAuthor"><a href="/a/1">温瑞安</a></div>
        <div class="classBookCover"><img src="/cover/1.jpg"/></div>
      </article>''';
    test('8123: CSS 列表 + @text/@href/@src 字段规则', () {
      final rs = load('8123')['ruleSearch'] as Map<String, dynamic>;
      final doc = html_parser.parse(cannedHtml);
      final els = p.selectElements(doc, rs['bookList'] as String);
      expect(els, isNotEmpty);
      expect(p.fieldFromElement(els.first, rs['name'] as String), '逆水寒');
      expect(p.fieldFromElement(els.first, rs['bookUrl'] as String), '/book/1');
      expect(p.fieldFromElement(els.first, rs['author'] as String), '温瑞安');
      expect(p.fieldFromElement(els.first, rs['coverUrl'] as String),
          '/cover/1.jpg');
    });
  });

  group('真实书源规则模式识别覆盖全部语法', () {
    test('29 个书源的规则字段覆盖 JS/JSON/JSONPath/CSS/XPath/正则', () {
      final modes = <RuleMode>{};
      final dir = Directory(fixtureDir);
      for (final f in dir.listSync().whereType<File>()) {
        final m = RegExp(r'source_(\d+)\.json$').firstMatch(f.path);
        if (m == null) continue;
        final src = load(m.group(1)!);
        for (final key in const [
          'searchUrl', 'exploreUrl', 'loginUrl', 'header', 'jsLib',
        ]) {
          final v = src[key];
          if (v is String && v.isNotEmpty) modes.add(p.modeOf(v));
        }
        for (final g in const [
          'ruleSearch', 'ruleExplore', 'ruleBookInfo', 'ruleToc', 'ruleContent',
        ]) {
          final gr = src[g];
          if (gr is! Map) continue;
          for (final v in gr.values) {
            if (v is String && v.isNotEmpty) modes.add(p.modeOf(v));
          }
        }
      }
      // 真实社区书源覆盖的全部主流模式（无前缀规则归 defaultRule）
      expect(modes, contains(RuleMode.js));
      expect(modes, contains(RuleMode.json));
      expect(modes, contains(RuleMode.css));
      expect(modes, contains(RuleMode.xpath));
      expect(modes, contains(RuleMode.regex));
      expect(modes, contains(RuleMode.defaultRule));
    });
  });
}
