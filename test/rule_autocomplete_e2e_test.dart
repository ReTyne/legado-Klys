import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/help/source/source_engine.dart';
import 'package:legado_md3/help/source/rule_auto_completer.dart';

void main() {
  test('本地 HTTP 端到端：抓取 -> 列表 -> 详情 -> 目录 -> 正文 全链路推导', () async {
    String listPage() {
      final sb = StringBuffer('<html><body><div class="result-list">');
      for (var i = 1; i <= 5; i++) {
        sb.writeln('''
        <div class="book-item">
          <a href="/book/100$i.html"><img data-src="/img/100$i.jpg" class="cover"></a>
          <div class="info">
            <h3 class="book-name"><a href="/book/100$i.html">测试书名$i</a></h3>
            <p class="author">作者：某作者$i</p>
            <p class="intro">这是测试书名$i的简介内容，需要足够长以满足简介字段识别的最低长度要求。</p>
          </div>
        </div>''');
      }
      sb.writeln('</div></body></html>');
      return sb.toString();
    }

    const detail = '''
<html><body><div id="maininfo"><h1>测试书名1</h1>
<div id="fmimg"><img src="/img/1001.jpg" id="cover"></div>
<div id="info"><span class="author">作者：某作者1</span></div>
<div id="intro">这是详情页简介，长度需要足够以满足识别阈值，讲述主角的故事背景与成长经历。</div>
<a id="catalog" href="/1001/catalog.html">目录</a></div></body></html>''';

    String toc() {
      final sb = StringBuffer('<html><body><div id="list">');
      for (var i = 1; i <= 10; i++) {
        sb.writeln('<dd><a href="/1001/$i.html">第$i章 标题</a></dd>');
      }
      sb.writeln('</div></body></html>');
      return sb.toString();
    }

    const content = '''
<html><body><h1 class="chapter-title">第1章 标题</h1>
<div id="content"><p>这是第一章的正文内容，主角缓缓睁开双眼，体内斗气重新涌动，这一段必须足够长以超过正文容器识别所要求的最低字数阈值，确保推导稳定。</p>
<p>第二段继续补足正文字数，他望向远方，新的旅程就此展开，再增加一些文字以确保容器文本长度达标。</p></div>
</body></html>''';

    final server = await HttpServer.bind('localhost', 0);
    server.listen((req) {
      final p = req.uri.path;
      String body;
      if (p.startsWith('/search')) {
        body = listPage();
      } else if (p == '/book/1001.html') {
        body = detail;
      } else if (p == '/1001/catalog.html') {
        body = toc();
      } else {
        body = content;
      }
      req.response.headers.contentType = ContentType.html;
      req.response.write(body);
      req.response.close();
    });

    try {
      final port = server.port;
      final base = 'http://localhost:$port/';
      final engine = BookSourceEngine();
      final source = BookSource(
        bookSourceUrl: base,
        bookSourceName: '本地测试源',
        searchUrl: '/search?q={{key}}&page={{page}}',
      );

      // 列表
      final listHtml = await engine.editFetch(source, source.searchUrl!, keyword: '测试');
      expect(listHtml, contains('book-item'));
      final list = RuleAutoCompleter.inferList(listHtml, baseUrl: base);
      expect(list.isEmpty, false);
      expect(list.sampleUrl, 'http://localhost:$port/book/1001.html');
      expect(list.fields['name'], isNotNull);

      // 详情
      final detailHtml = await engine.editFetch(source, list.sampleUrl!);
      final info = RuleAutoCompleter.inferBookInfo(detailHtml, baseUrl: list.sampleUrl!);
      expect(info.fields['name'], isNotNull);
      expect(info.nextUrl, 'http://localhost:$port/1001/catalog.html');

      // 目录
      final tocHtml = await engine.editFetch(source, info.nextUrl!);
      final tocRes = RuleAutoCompleter.inferChapterList(tocHtml, baseUrl: info.nextUrl!);
      expect(tocRes.listRule, isNotEmpty);
      expect(tocRes.sampleUrl, 'http://localhost:$port/1001/1.html');

      // 正文
      final contentHtml = await engine.editFetch(source, tocRes.sampleUrl!);
      final contentRes = RuleAutoCompleter.inferContent(contentHtml, baseUrl: tocRes.sampleUrl!);
      expect(contentRes.fields['content'], isNotNull);
    } finally {
      await server.close();
    }
  });
}
