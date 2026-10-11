import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:legado_md3/data/model/rss_source.dart';
import 'package:legado_md3/data/model/rss_article.dart';
import 'package:legado_md3/help/http/rss_service.dart';
import 'package:legado_md3/help/source/js/legado_js_runtime.dart';
import 'package:legado_md3/ui/rss/rss_source_login_screen.dart';

/// 伪运行时：按脚本标记返回罐头数据，验证 RSS 侧 JS 编排
/// （@js 头 / mustache（getUrl/TD/setzt）/ 外层文章数组 / ruleContent HTML）。
class _FakeRssJs implements LegadoJs {
  @override
  Future<void> loadSource(JsSource source) async {}

  @override
  Future<JsEvalResult> eval(JsEvalRequest req) async {
    final s = req.script.trim();

    // 外层文章列表（mustache 已替换，仍含 let list）
    if (s.contains('let list')) {
      return JsEvalResult(value: [
        {
          'name': '首页',
          'url': 'http://gedem.uaa.cn.mt/',
          'img': 'http://x/a.png'
        },
        {
          'name': '独立密钥',
          'url': 'http://gedem.uaa.cn.mt/miyao.html',
          'img': 'http://x/b.png'
        },
      ]);
    }
    // 外层正文
    if (s.contains('var po')) {
      final title = (req.rssArticle?['title'] ?? '').toString();
      if (title == '独立密钥') {
        return JsEvalResult(
            value: '<html><body><div id="r">密钥123</div></body></html>');
      }
      return JsEvalResult(value: req.result is String ? req.result : '');
    }
    // @js 请求头
    if (s.contains('getWebViewUA')) {
      return JsEvalResult(
          value: jsonEncode({'User-Agent': 'UA', 'Authorization': 'Bearer x'}));
    }
    // mustache 内部表达式（精确匹配）
    if (s == 'getUrl()') return JsEvalResult(value: 'gedem');
    if (s == 'TD()') return JsEvalResult(value: 'turn');
    if (s == 'setzt()') return JsEvalResult(value: '');
    if (s == 'eval(String(source.loginUrl))') return JsEvalResult(value: '');
    if (s == 'rssArticle.title') {
      return JsEvalResult(value: req.rssArticle?['title']?.toString());
    }
    return JsEvalResult(value: null);
  }

  @override
  Future<void> dispose() async {}
}

RssSource _buildSource() {
  return RssSource(
    sourceName: '慕এ~',
    sourceUrl: 'data:;base64,辞晨,{"type":""}',
    sourceIcon: 'http://x/icon.png',
    sortUrl: '主页::http://{{getUrl()}}.uaa.cn.mt/',
    header:
        "@js:\nlet url=getUrl();\nJSON.stringify({'User-Agent':java.getWebViewUA(),'Authorization':'Bearer '+token})",
    ruleArticles: r'''@js:
let uri=getUrl();{{TD()}};{{setzt()}};{{eval(String(source.loginUrl))}};
let setl=`http://${getUrl()}.uaa.cn.mt/`;
let list=[{name:'首页',url:`${setl}`,img:'a.png'},{name:'独立密钥',url:`${setl}miyao.html`,img:'b.png'}];
list''',
    ruleContent:
        "<js>\nvar po=`{{rssArticle.title}}`;\nif(po=='独立密钥'){html='<html><body><div id=\"r\">密钥123</div></body></html>';html}else{result}\n</js>",
    ruleTitle: 'name',
    ruleLink: 'url',
    ruleImage: 'img',
    enableJs: true,
    enabledCookieJar: true,
    loginUrl: 'function login(){}',
    loginUi: jsonEncode([
      {'name': '密钥：', 'type': 'text'},
      {'name': '✐密钥✐', 'type': 'button', 'action': 'my()'},
    ]),
  );
}

void main() {
  late RssSource source;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    source = _buildSource();
    JsRuntimeManager.instance.factoryOverride = (_) => _FakeRssJs();
  });

  tearDown(() async {
    JsRuntimeManager.instance.factoryOverride = null;
    await JsRuntimeManager.instance.disposeAll();
  });

  test('sortUrl 解析为分类（含 mustache URL）', () {
    final cats = RssService().parseCategories(source);
    expect(cats.length, 1);
    expect(cats.first.name, '主页');
    expect(cats.first.rawUrl.contains('{{getUrl()}}'), isTrue);
  });

  test('逻辑源 @js 文章列表：映射 name/url/img', () async {
    final articles = await RssService().fetchRss(source);
    expect(articles.length, 2);
    expect(articles[0].title, '首页');
    expect(articles[1].title, '独立密钥');
    expect(articles[0].link, 'http://gedem.uaa.cn.mt/');
    expect(articles[0].image, 'http://x/a.png');
    expect(articles[1].image, 'http://x/b.png');
    expect(articles[0].sourceUrl, source.sourceUrl);
  });

  test('分类：mustache 解析 URL 后取文章', () async {
    final cats = RssService().parseCategories(source);
    final articles = await RssService().fetchCategory(source, cats.first);
    expect(articles.length, 2);
    expect(articles.first.title, '首页');
  });

  test('@js 请求头求值为 JSON', () async {
    final h = await RssService().fetchRss(source);
    expect(h, isNotEmpty); // 头求值失败不应中断
  });

  test('ruleContent：独立密钥产出 HTML 正文', () async {
    final article = RssArticle(
      title: '独立密钥',
      link: 'http://gedem.uaa.cn.mt/miyao.html',
      sourceName: source.sourceName,
      sourceUrl: source.sourceUrl,
    );
    final content = await RssService()
        .fetchArticleContent(source, article);
    expect(content, isNotNull);
    expect(content!.contains('密钥123'), isTrue);
    expect(content.contains('<html'), isTrue);
  });

  testWidgets('RSS 登录页按 loginUi 渲染输入框与按钮', (tester) async {
    await tester.pumpWidget(
        MaterialApp(home: RssSourceLoginScreen(source: source)));
    await tester.pump();
    expect(find.text('密钥：'), findsOneWidget);
    expect(find.text('✐密钥✐'), findsOneWidget);
  });
}
