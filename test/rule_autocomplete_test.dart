import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:legado_md3/help/source/rule_auto_completer.dart';
import 'package:legado_md3/help/source/rule_pipeline.dart';

const base = 'https://example.com';

String listHtml() {
  final sb = StringBuffer('<html><body><div class="header">导航</div><div class="result-list">');
  final names = ['斗破苍穹', '凡人修仙传', '诡秘之主', '大奉打更人', '夜的命名术'];
  final authors = ['天蚕土豆', '忘语', '爱潜水的乌贼', '卖报小郎君', '会说话的肘子'];
  for (var i = 0; i < 5; i++) {
    final id = 1001 + i;
    sb.writeln('''
    <div class="book-item">
      <a href="/book/$id.html"><img data-src="/img/$id.jpg" class="cover" alt="封面"></a>
      <div class="info">
        <h3 class="book-name"><a href="/book/$id.html">${names[i]}</a></h3>
        <p class="author">作者：${authors[i]}</p>
        <p class="book-cate">分类：玄幻</p>
        <p class="intro">这是${names[i]}的简介内容，用于测试智能规则补全能否正确命中简介字段，需要足够长。</p>
        <span class="latest"><a href="/read/$id/900.html">最新章节 第九百章</a></span>
        <span class="word-count">字数：530万字</span>
      </div>
    </div>''');
  }
  sb.writeln('</div></body></html>');
  return sb.toString();
}

const detailHtml = '''
<html><body><div id="maininfo">
  <h1>斗破苍穹</h1>
  <div id="fmimg"><img src="/img/1001.jpg" id="cover" alt="封面"></div>
  <div id="info">
    <span class="author">作&nbsp;&nbsp;者：天蚕土豆</span>
    <span class="cate">分类：玄幻奇幻</span>
    <span class="last">最新章节：第九百章 大结局</span>
  </div>
  <div id="intro">《斗破苍穹》是一部连载于起点中文网的玄幻小说，作者是天蚕土豆，讲述了少年萧炎的成长故事，这段简介需要足够长以满足识别阈值。</div>
  <a href="/1001/catalog.html" id="catalog">目录</a>
</div></body></html>''';

String tocHtml() {
  final sb = StringBuffer('<html><body><div id="list" class="chapter-list">');
  for (var i = 1; i <= 12; i++) {
    sb.writeln('<dd><a href="/1001/$i.html">第${i}章 测试章节标题</a></dd>');
  }
  sb.writeln('<dd><a href="/1001/index_2.html">下一页</a></dd>');
  sb.writeln('</div></body></html>');
  return sb.toString();
}

const contentHtml = '''
<html><body>
<h1 class="chapter-title">第一章 陨落的天才</h1>
<div id="content">
<p>第一段正文内容，萧炎缓缓睁开双眼，感受着体内久违的斗气，这一段需要足够长以超过正文识别所要求的最低字数阈值，于是他开始回忆这些年在家族中所经历的种种冷暖与变故。</p>
<p>第二段正文内容，他抬起头望向窗外，乌云密布，一场关于天才陨落与重新崛起的故事就此拉开序幕，继续补足长度以确保正文容器的纯文本长度能够稳定超过识别门槛，让推导结果可靠。</p>
</div>
<a id="next" href="/1001/2.html">下一页</a>
</body></html>''';

String jsonApi() {
  final list = List.generate(5, (i) {
    final id = 2000 + i;
    return {
      'bookName': '测试小说$i',
      'author': '作者$i',
      'coverImg': '/img/$id.jpg',
      'bookUrl': '/b/$id.html',
      'intro': '这是第$i本小说的简介内容，需要一定长度。',
    };
  });
  return jsonEncode({'code': 0, 'data': {'records': list}});
}

void main() {
  final pipe = RulePipeline(baseUrl: base);

  test('搜索列表：生成的规则可被引擎正确提取', () {
    final html = listHtml();
    final r = RuleAutoCompleter.inferList(html, baseUrl: base);
    expect(r.isEmpty, false, reason: '应识别出列表');
    expect(r.isJson, false);
    // listRule 命中 5 条
    final doc = html_parser.parse(html);
    final els = pipe.selectElements(doc, r.listRule);
    expect(els.length, 5, reason: 'bookList=$r.listRule');
    // 字段
    final first = els.first;
    String? v(String k) =>
        r.fields[k] == null ? null : pipe.fieldFromElement(first, r.fields[k]!);
    expect(v('name'), '斗破苍穹', reason: 'name=${r.fields['name']}');
    expect(v('bookUrl'), contains('/book/1001.html'),
        reason: 'bookUrl=${r.fields['bookUrl']}');
    expect(v('coverUrl'), contains('/img/1001.jpg'),
        reason: 'coverUrl=${r.fields['coverUrl']}');
    expect(v('author'), '天蚕土豆', reason: 'author=${r.fields['author']}（应去除“作者：”前缀）');
    expect(v('kind'), '玄幻', reason: 'kind=${r.fields['kind']}（应去除“分类：”前缀）');
    expect(v('intro'), contains('简介'), reason: 'intro=${r.fields['intro']}');
    expect(r.sampleUrl, 'https://example.com/book/1001.html');
    // 五条都能稳定取到书名
    final names = els
        .map((e) => pipe.fieldFromElement(e, r.fields['name']!))
        .toList();
    expect(names.whereType<String>().length, 5);
  });

  test('详情页：书名/封面/简介/目录链接', () {
    final r = RuleAutoCompleter.inferBookInfo(detailHtml, baseUrl: base);
    String? v(String k) =>
        r.fields[k] == null ? null : pipe.extractStringFromRaw(detailHtml, r.fields[k]!);
    expect(v('name'), '斗破苍穹', reason: 'name=${r.fields['name']}');
    expect(v('coverUrl'), contains('/img/1001.jpg'), reason: 'cover=${r.fields['coverUrl']}');
    expect(v('intro'), contains('斗破苍穹'), reason: 'intro=${r.fields['intro']}');
    expect(v('tocUrl'), contains('catalog'), reason: 'toc=${r.fields['tocUrl']}');
    expect(r.nextUrl, 'https://example.com/1001/catalog.html');
  });

  test('目录页：章节列表/标题/链接', () {
    final html = tocHtml();
    final r = RuleAutoCompleter.inferChapterList(html, baseUrl: base);
    final doc = html_parser.parse(html);
    final els = pipe.selectElements(doc, r.listRule);
    expect(els.length >= 12, true, reason: 'chapterList=${r.listRule} n=${els.length}');
    final t = pipe.fieldFromElement(els.first, r.fields['chapterName']!);
    final u = pipe.fieldFromElement(els.first, r.fields['chapterUrl']!);
    expect(t, contains('第1章'), reason: 'chapterName=${r.fields['chapterName']}');
    expect(u, contains('/1001/1.html'), reason: 'chapterUrl=${r.fields['chapterUrl']}');
    expect(r.sampleUrl, 'https://example.com/1001/1.html');
  });

  test('正文页：正文主体/标题/下一页', () {
    final r = RuleAutoCompleter.inferContent(contentHtml, baseUrl: base);
    expect(r.fields['content'], isNotNull, reason: '应识别正文容器');
    final c = pipe.extractStringFromRaw(contentHtml, r.fields['content']!);
    expect(c, contains('萧炎'), reason: 'content=${r.fields['content']}');
    final t = pipe.extractStringFromRaw(contentHtml, r.fields['title']!);
    expect(t, contains('第一章'), reason: 'title=${r.fields['title']}');
    final next = pipe.extractStringFromRaw(contentHtml, r.fields['nextContentUrl']!);
    expect(next, contains('2.html'),
        reason: 'next=${r.fields['nextContentUrl']}');
  });

  test('JSON 接口：列表路径与字段', () {
    final raw = jsonApi();
    final r = RuleAutoCompleter.inferList(raw, baseUrl: base);
    expect(r.isJson, true);
    expect(r.listRule, contains('records'));
    final nodes = pipe.selectJsonNodes(jsonDecode(raw), r.listRule);
    expect(nodes.length, 5);
    final name = pipe.fieldFromJson(nodes.first, r.fields['name']!);
    final url = pipe.fieldFromJson(nodes.first, r.fields['bookUrl']!);
    expect(name, '测试小说0');
    expect(url, contains('/b/2000.html'));
  });
}
