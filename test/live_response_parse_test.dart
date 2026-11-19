import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:legado_md3/help/source/rule_pipeline.dart';

/// 真实联网端到端验证：把从书源站点实际抓到的 HTTP 响应喂给 K 版规则引擎，
/// 用书源自身的规则解析，证明「搜索结果能真实取出书名/作者/链接」。
///
/// 注意：这是离线回放——响应体已落盘为 fixture，测试期不联网。
/// 目的是验证「真实站点返回的 HTML 结构与 K 版引擎规则兼容」，
/// 而非验证站点当前是否在线（站点可用性受反爬/登录/网络环境影响）。
void main() {
  const fixtureDir = 'test/fixtures/community';
  final p = RulePipeline();

  Map<String, dynamic> loadSource(String id) {
    final d = jsonDecode(File('$fixtureDir/source_$id.json').readAsStringSync());
    final m = d is List ? d.first : d;
    return (m as Map).cast<String, dynamic>();
  }

  group('真实联网响应 → K版引擎解析', () {
    test('8123 书海阁：真实搜索页 CSS 规则取出书名/链接/作者', () {
      final src = loadSource('8123');
      final rules = (src['ruleSearch'] as Map).cast<String, dynamic>();
      final raw = File('$fixtureDir/real_responses/source_8123_search.html')
          .readAsStringSync();
      final doc = html_parser.parse(raw);

      // bookList: article.classBookCard
      final els = p.selectElements(doc, rules['bookList'] as String);
      expect(els.length, greaterThanOrEqualTo(3),
          reason: '真实搜索页应解析出多张书卡');

      // 逐卡取字段
      final first = els.first;
      final name = p.fieldFromElement(first, rules['name'] as String);
      final url = p.fieldFromElement(first, rules['bookUrl'] as String);
      final author = p.fieldFromElement(first, rules['author'] as String);

      expect(name, isNotNull);
      expect(name!.trim().isNotEmpty, isTrue, reason: '书名非空');
      expect(url, isNotNull);
      expect(url!.trim().isNotEmpty, isTrue, reason: '详情链接非空');
      expect(author, isNotNull);
      expect(author!.trim().isNotEmpty, isTrue, reason: '作者非空');
    });

    test('8123 书海阁：所有书卡字段解析无异常', () {
      final src = loadSource('8123');
      final rules = (src['ruleSearch'] as Map).cast<String, dynamic>();
      final raw = File('$fixtureDir/real_responses/source_8123_search.html')
          .readAsStringSync();
      final els = p.selectElements(html_parser.parse(raw),
          rules['bookList'] as String);
      final fieldKeys = ['name', 'author', 'bookUrl', 'coverUrl',
          'intro', 'kind', 'lastChapter', 'wordCount'];
      for (final el in els) {
        for (final k in fieldKeys) {
          final rule = rules[k];
          if (rule is String && rule.isNotEmpty) {
            // 任一字段规则都不得抛异常
            expect(() => p.fieldFromElement(el, rule), returnsNormally,
                reason: '字段 $k 规则解析不应抛异常');
          }
        }
      }
    });
  });

  group('真实联网全链路回放：搜索 → 详情 → 目录 → 正文（8123 书海阁）', () {
    test('四层真实响应用K版引擎逐层解析，链路贯通', () {
      final src = loadSource('8123');
      final sr = (src['ruleSearch'] as Map).cast<String, dynamic>();
      final br = (src['ruleBookInfo'] as Map).cast<String, dynamic>();
      final tr = (src['ruleToc'] as Map).cast<String, dynamic>();
      final cr = (src['ruleContent'] as Map).cast<String, dynamic>();

      // ① 搜索页 → 书名 / 详情链接
      final searchRaw = File('$fixtureDir/real_responses/source_8123_search.html')
          .readAsStringSync();
      final cards = p.selectElements(
          html_parser.parse(searchRaw), sr['bookList'] as String);
      expect(cards.length, greaterThanOrEqualTo(3));
      final firstBookUrl = p.fieldFromElement(cards.first, sr['bookUrl'] as String);
      expect(firstBookUrl, isNotNull);
      expect(firstBookUrl!.contains('/book/'), isTrue);

      // ② 详情页 → 书名 / 目录链接
      final bookRaw = File('$fixtureDir/real_responses/source_8123_book.html')
          .readAsStringSync();
      final bookDoc = html_parser.parse(bookRaw);
      final name = p.fieldFromElement(bookDoc.body!, br['name'] as String);
      final tocUrl = p.fieldFromElement(bookDoc.body!, br['tocUrl'] as String);
      expect(name, '三体全集（全三册）', reason: '真实详情名解析');
      expect(tocUrl, isNotNull);
      expect(tocUrl!.contains('indexList'), isTrue, reason: '真实目录链接解析');

      // ③ 目录页 → 章节列表（含章节名 / 链接）
      final tocRaw = File('$fixtureDir/real_responses/source_8123_toc.html')
          .readAsStringSync();
      final tocEls = p.selectElements(
          html_parser.parse(tocRaw), tr['chapterList'] as String);
      expect(tocEls.length, greaterThan(50), reason: '真实目录应有多章');
      final chName = p.fieldFromElement(tocEls.first, tr['chapterName'] as String);
      final chUrl = p.fieldFromElement(tocEls.first, tr['chapterUrl'] as String);
      expect(chName, isNotNull);
      expect(chName!.trim().isNotEmpty, isTrue, reason: '章节名非空');
      expect(chUrl, isNotNull);
      expect(chUrl!.contains('/book/'), isTrue, reason: '章节链接有效');

      // ④ 正文页 → 正文容器非空（只验证长度，不落具体内容）
      final contentRaw = File('$fixtureDir/real_responses/source_8123_content.html')
          .readAsStringSync();
      final content = p.firstStringFromRaw(contentRaw, cr['content'] as String);
      expect(content, isNotNull, reason: '正文容器应可解析');
      expect(content!.trim().length, greaterThan(100),
          reason: '真实正文应有足量文本');
    });
  });
}
