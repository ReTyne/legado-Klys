import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/data/model/rss_source.dart';
import 'package:legado_md3/help/http/rss_service.dart';
import 'package:legado_md3/help/source/rule_auto_completer.dart';

void main() {
  test('RSS 网页型源：自定义文章规则真正生效（含翻页）', () async {
    String page(int p) {
      final sb = StringBuffer('<html><body><ul class="news-list">');
      for (var i = 1; i <= 5; i++) {
        final id = (p - 1) * 5 + i;
        sb.writeln('''
        <li class="news-item">
          <a href="/news/$id.html" class="title">资讯标题$id</a>
          <p class="summary">这是第$id条资讯的摘要内容，用于验证描述规则。</p>
          <span class="time">2026-09-18</span>
        </li>''');
      }
      if (p == 1) sb.writeln('<a class="next" href="/list_2.html">下一页</a>');
      sb.writeln('</ul></body></html>');
      return sb.toString();
    }

    final server = await HttpServer.bind('localhost', 0);
    server.listen((req) {
      req.response.headers.contentType = ContentType.html;
      req.response.write(req.uri.path.contains('list_2') ? page(2) : page(1));
      req.response.close();
    });

    try {
      final port = server.port;
      final base = 'http://localhost:$port/list.html';
      final inferred = RuleAutoCompleter.inferList(page(1), baseUrl: base);
      expect(inferred.isEmpty, false);

      final source = RssSource(
        sourceName: '资讯站',
        sourceUrl: base,
        ruleArticles: inferred.listRule,
        ruleTitle: inferred.fields['name'],
        ruleLink: inferred.fields['bookUrl'],
        ruleDescription: inferred.fields['intro'],
        ruleNextPage: '@css:a.next@href',
      );

      final rss = RssService();
      final articles = await rss.fetchRss(source);
      expect(articles.isNotEmpty, true, reason: '应按自定义规则取到文章');
      expect(articles.first.title, contains('资讯标题'));
      expect(articles.first.link, startsWith('http://localhost:$port/news/'));
      // 翻页：两页共 10 条且不重复
      expect(articles.length, 10, reason: '应翻页取到两页共 10 条，实际 ${articles.length}');
      final links = articles.map((a) => a.link).toSet();
      expect(links.length, 10);
    } finally {
      await server.close();
    }
  });
}
