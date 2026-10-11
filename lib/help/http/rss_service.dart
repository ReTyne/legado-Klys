import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:enough_convert/enough_convert.dart';
import 'package:legado_md3/data/model/rss_source.dart';
import 'package:legado_md3/data/model/rss_article.dart';
import 'package:legado_md3/help/source/rule_pipeline.dart';
import 'package:legado_md3/help/source/js/legado_js_runtime.dart';

/// RSS 分类（sortUrl 解析结果）
class RssCategory {
  final String name;
  final String rawUrl;
  RssCategory(this.name, this.rawUrl);
}

/// RSS订阅服务
class RssService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
    responseType: ResponseType.bytes,
    followRedirects: true,
    validateStatus: (s) => s != null && s < 400,
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    },
  ));

  final RulePipeline _pipeline = RulePipeline();
  static final RegExp _mustacheRe = RegExp(r'\{\{([\s\S]*?)\}\}');

  // ============================ 入口 ============================

  /// 获取RSS源内容
  Future<List<RssArticle>> fetchRss(RssSource source) async {
    try {
      if (_needsJs(source)) {
        return await _fetchJsArticles(source, baseUrl: source.jsHttpUrl);
      }
      final articles = <RssArticle>[];
      final content = await _httpGet(source.url, source.header);
      if (content.isEmpty) return articles;
      articles.addAll(_parseRss(content, source));
      if (articles.isEmpty) articles.addAll(_parseAtom(content, source));
      if (articles.isEmpty &&
          (source.ruleArticles?.trim().isNotEmpty ?? false)) {
        articles.addAll(await _parseByRules(source, content));
      }
      if (articles.isEmpty) articles.addAll(_parseHtml(content, source));
      return articles;
    } catch (_) {
      return [];
    }
  }

  /// 源 / 规则是否需要真实 JS 引擎
  bool _needsJs(RssSource s) {
    if (!s.sourceUrl.startsWith('http')) return true; // data: 逻辑源
    if (s.enableJs) return true;
    for (final r in [s.ruleArticles, s.header, s.ruleContent]) {
      if (r != null && ruleNeedsRealJs(r)) return true;
    }
    return false;
  }

  // ============================ JS 链路 ============================

  /// 解析 sortUrl 为分类列表（`名称::URL`，多个用换行分隔）
  List<RssCategory> parseCategories(RssSource s) {
    final raw = (s.sortUrl ?? '').trim();
    if (raw.isEmpty) return [];
    final out = <RssCategory>[];
    for (final line in raw.split(RegExp(r'[\r\n]+'))) {
      final seg = line.trim();
      if (seg.isEmpty) continue;
      final idx = seg.indexOf('::');
      if (idx < 0) {
        out.add(RssCategory(seg, seg));
      } else {
        out.add(RssCategory(seg.substring(0, idx).trim(),
            seg.substring(idx + 2).trim()));
      }
    }
    return out;
  }

  /// 取某个分类的文章（解析分类 URL 中的 mustache，再以该 URL 为基址跑文章规则）
  Future<List<RssArticle>> fetchCategory(
      RssSource s, RssCategory category) async {
    var url = category.rawUrl;
    if (url.contains('{{')) {
      url = await _applyMustache(s, url,
          result: '', baseUrl: s.jsHttpUrl);
    }
    return _fetchJsArticles(s, baseUrl: url.startsWith('http') ? url : s.jsHttpUrl);
  }

  /// JS 方式取文章列表。
  /// [baseUrl] 为实际页面地址（分类 URL / http 源地址；逻辑源可能为空）。
  Future<List<RssArticle>> _fetchJsArticles(RssSource s,
      {required String baseUrl}) async {
    final rule = (s.ruleArticles ?? '').trim();
    if (rule.isEmpty) return [];
    final rt = await JsRuntimeManager.instance.forSource(s);

    // 抓取页面（best effort；部分逻辑源不依赖页面）
    var pageContent = '';
    if (baseUrl.startsWith('http')) {
      pageContent = await _httpGet(baseUrl, await _resolveHeader(s));
    }

    var body = _stripJs(rule);
    body = await _applyMustache(s, body,
        result: pageContent, baseUrl: baseUrl);
    final res = await rt.eval(JsEvalRequest(
        source: s, script: body, result: pageContent, baseUrl: baseUrl));

    final val = res.value;
    List<dynamic> list = [];
    if (val is List) {
      list = val;
    } else if (val is String && val.trim().isNotEmpty) {
      final parsed = _tryJson(val);
      if (parsed is List) list = parsed;
    }

    final out = <RssArticle>[];
    for (final o in list) {
      if (o is! Map) continue;
      String field(String? rule) => _fieldFromJsObject(o, rule, baseUrl);
      final title = field(s.ruleTitle).trim();
      final link = field(s.ruleLink).trim();
      if (title.isEmpty) continue;
      final img = field(s.ruleImage).trim();
      final desc = field(s.ruleDescription).trim();
      out.add(RssArticle(
        title: title,
        link: _resolveUrl(baseUrl, link),
        description: desc.isEmpty ? null : desc,
        image: img.isEmpty ? null : _resolveUrl(baseUrl, img),
        pubDate: _parseDate(field(s.rulePubDate)),
        sourceName: s.name,
        sourceUrl: s.url,
      ));
    }
    return out;
  }

  /// 从 JS 返回的文章对象里按字段规则取值（简单 key 直接取，否则 JSONPath）。
  String _fieldFromJsObject(dynamic o, String? rule, String baseUrl) {
    final r = (rule ?? '').trim();
    if (r.isEmpty) return '';
    if (!ruleNeedsRealJs(r) && !r.contains('.') && !r.contains('[')) {
      return (o[r] ?? '').toString();
    }
    try {
      return _pipeline.jsonPathFirst(o, r)?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }

  /// 计算文章正文（ruleContent），返回正文（可能是 HTML）。
  Future<String?> fetchArticleContent(RssSource s, RssArticle article) async {
    final rule = (s.ruleContent ?? '').trim();
    if (rule.isEmpty) return article.description ?? article.content ?? '';
    final rt = await JsRuntimeManager.instance.forSource(s);

    var pageHtml = '';
    if (article.link.startsWith('http')) {
      pageHtml = await _httpGet(article.link, await _resolveHeader(s));
    }
    final am = article.jsContext();
    var body = _stripJs(rule);
    body = await _applyMustache(s, body,
        result: pageHtml, baseUrl: article.link, rssArticle: am);
    final res = await rt.eval(JsEvalRequest(
        source: s,
        script: body,
        result: pageHtml,
        baseUrl: article.link,
        rssArticle: am));
    return res.stringValue;
  }

  /// 解析请求头：@js 规则求值为 JSON 字符串，普通头原样返回。
  Future<String?> _resolveHeader(RssSource s) async {
    var h = (s.header ?? '').trim();
    if (h.isEmpty) return null;
    if (h.startsWith('@js:') || h.contains('<js') || h.contains('{{')) {
      final rt = await JsRuntimeManager.instance.forSource(s);
      var body = _stripJs(h);
      body = await _applyMustache(s, body,
          result: '', baseUrl: s.jsHttpUrl);
      final res = await rt.eval(JsEvalRequest(
          source: s, script: body, result: '', baseUrl: s.jsHttpUrl));
      return res.stringValue;
    }
    return h;
  }

  /// 替换文本中的 {{...}}（逐个求值，从后往前替换以保持索引）。
  Future<String> _applyMustache(RssSource s, String text,
      {dynamic result, String? baseUrl, Map<String, dynamic>? rssArticle}) async {
    final matches = _mustacheRe.allMatches(text).toList();
    if (matches.isEmpty) return text;
    final rt = await JsRuntimeManager.instance.forSource(s);
    var out = text;
    for (final m in matches.reversed) {
      final inner = m.group(1)!.trim();
      final r = await rt.eval(JsEvalRequest(
          source: s,
          script: inner,
          result: result ?? '',
          baseUrl: baseUrl,
          rssArticle: rssArticle));
      final v = r.stringValue ?? '';
      out = out.replaceRange(m.start, m.end, v);
    }
    return out;
  }

  /// 去掉 @js: / <js></js> 包裹，返回纯 JS。
  String _stripJs(String rule) {
    var r = rule.trim();
    if (r.startsWith('@js:')) r = r.substring(4);
    if (r.startsWith('<js>')) {
      r = r.substring(4);
      if (r.endsWith('</js>')) r = r.substring(0, r.length - 5);
    }
    return r.trim();
  }

  dynamic _tryJson(String s) {
    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  // ============================ HTTP / 编码 ============================

  /// 抓取原始页面文本（编辑页“规则补全”与测试复用），按 header/编码处理
  Future<String> fetchRaw(String url, {String? header}) =>
      _httpGet(url, header);

  Future<String> _httpGet(String url, String? headerJson) async {
    if (!url.startsWith('http')) return '';
    try {
      final headers = <String, dynamic>{};
      if (headerJson != null && headerJson.trim().isNotEmpty) {
        try {
          final v = jsonDecode(headerJson);
          if (v is Map) {
            headers.addAll(
                v.map((k, val) => MapEntry(k.toString(), val)));
          }
        } catch (_) {}
      }
      final resp = await _dio.get(url, options: Options(headers: headers));
      return _decode(resp.data ?? const <int>[], resp.headers.map);
    } catch (_) {
      return '';
    }
  }

  String _decode(List<int> bytes, Map<String, List<String>> headers) {
    var cs = '';
    final ct = (headers['content-type'] ?? headers['Content-Type'] ?? []).join(';').toLowerCase();
    final m = RegExp(r'charset=([a-z0-9\-]+)').firstMatch(ct);
    if (m != null) cs = m.group(1)!;
    if (cs.isEmpty) {
      final head = String.fromCharCodes(bytes.take(2048).map((b) => b & 0xff)).toLowerCase();
      final mm = RegExp(r'''charset=["']?([a-z0-9\-]+)''').firstMatch(head);
      if (mm != null) cs = mm.group(1)!;
    }
    cs = cs.toLowerCase();
    try {
      if (cs == 'gbk' || cs == 'gb2312' || cs == 'gb18030') return GbkCodec().decode(bytes);
      if (cs == 'big5') return Big5Codec().decode(bytes);
      if (cs == 'latin1' || cs == 'iso-8859-1') return latin1.decode(bytes);
      return utf8.decode(bytes, allowMalformed: false);
    } catch (_) {
      try {
        return utf8.decode(bytes, allowMalformed: true);
      } catch (_) {
        try {
          return GbkCodec().decode(bytes);
        } catch (_) {
          return latin1.decode(bytes);
        }
      }
    }
  }

  /// 依据用户自定义规则抓取文章列表（支持 ruleNextPage 翻页，最多 5 页）
  Future<List<RssArticle>> _parseByRules(RssSource source, String firstContent) async {
    final out = <RssArticle>[];
    final seen = <String>{};
    var content = firstContent;
    var currentUrl = source.url;
    _pipeline.baseUrl = currentUrl;

    for (var page = 0; page < 5; page++) {
      final doc = html_parser.parse(content);
      final elements = _pipeline.selectElements(doc, source.ruleArticles!);
      for (final el in elements) {
        String? f(String? rule) =>
            (rule == null || rule.trim().isEmpty) ? null : _pipeline.fieldFromElement(el, rule);
        final title = (f(source.ruleTitle) ?? '').trim();
        var link = _resolveUrl(currentUrl, (f(source.ruleLink) ?? '').trim());
        if (title.isEmpty) continue;
        if (link.isEmpty) link = _resolveUrl(currentUrl, el.attributes['href'] ?? '');
        if (link.isNotEmpty && !seen.add(link)) continue;
        final desc = (f(source.ruleDescription) ?? '').trim();
        final img = _resolveUrl(currentUrl, (f(source.ruleImage) ?? '').trim());
        final pubRaw = f(source.rulePubDate);
        out.add(RssArticle(
          title: title,
          link: link,
          description: desc.isEmpty ? null : _cleanHtml(desc),
          image: img.isEmpty ? null : img,
          pubDate: _parseDate(pubRaw),
          sourceName: source.name,
          sourceUrl: source.url,
        ));
      }

      final nextRule = source.ruleNextPage;
      if (nextRule == null || nextRule.trim().isEmpty) break;
      final next = _pipeline.extractStringFromRaw(content, nextRule);
      if (next == null || next.trim().isEmpty || next == currentUrl) break;
      final nextUrl = _resolveUrl(currentUrl, next.trim());
      if (nextUrl == currentUrl) break;
      currentUrl = nextUrl;
      _pipeline.baseUrl = currentUrl;
      content = await _httpGet(currentUrl, source.header);
      if (content.isEmpty) break;
    }
    return out;
  }

  /// 解析RSS 2.0
  List<RssArticle> _parseRss(String content, RssSource source) {
    final articles = <RssArticle>[];
    try {
      final doc = html_parser.parse(content);
      final items = doc.querySelectorAll('item');
      for (final item in items) {
        final title = _getElementText(item, 'title');
        final link = _getElementText(item, 'link');
        final description = _getElementText(item, 'description');
        final pubDate = _getElementText(item, 'pubDate');
        final author = _getElementText(item, 'author');
        final category = _getElementText(item, 'category');

        if (title != null && title.isNotEmpty) {
          articles.add(RssArticle(
            title: title,
            link: link ?? '',
            description: _cleanHtml(description ?? ''),
            pubDate: _parseDate(pubDate),
            author: author,
            category: category,
            sourceName: source.name,
            sourceUrl: source.url,
          ));
        }
      }
    } catch (_) {}
    return articles;
  }

  /// 解析Atom
  List<RssArticle> _parseAtom(String content, RssSource source) {
    final articles = <RssArticle>[];
    try {
      final doc = html_parser.parse(content);
      final entries = doc.querySelectorAll('entry');
      for (final entry in entries) {
        final title = _getElementText(entry, 'title');
        final linkEl = entry.querySelector('link');
        final link = linkEl?.attributes['href'] ?? '';
        final summary = _getElementText(entry, 'summary');
        final content = _getElementText(entry, 'content');
        final updated = _getElementText(entry, 'updated');
        final authorEl = entry.querySelector('author name');
        final author = authorEl?.text;

        if (title != null && title.isNotEmpty) {
          articles.add(RssArticle(
            title: title,
            link: link,
            description: _cleanHtml(summary ?? content ?? ''),
            pubDate: _parseDate(updated),
            author: author,
            sourceName: source.name,
            sourceUrl: source.url,
          ));
        }
      }
    } catch (_) {}
    return articles;
  }

  /// 解析HTML（通用网页抓取）
  List<RssArticle> _parseHtml(String content, RssSource source) {
    final articles = <RssArticle>[];
    try {
      final doc = html_parser.parse(content);
      final selectors = [
        'article', '.article-item', '.post-item', '.list-item',
        'li.article', 'div.item', '.news-item',
      ];
      for (final selector in selectors) {
        final items = doc.querySelectorAll(selector);
        if (items.isNotEmpty) {
          for (final item in items.take(20)) {
            final titleEl = item.querySelector('h1, h2, h3, h4, a.title, .title a');
            final title = titleEl?.text.trim();
            final link = titleEl?.attributes['href'] ?? item.querySelector('a')?.attributes['href'] ?? '';
            final desc = item.querySelector('.summary, .description, .excerpt, p')?.text.trim();

            if (title != null && title.isNotEmpty) {
              articles.add(RssArticle(
                title: title,
                link: _resolveUrl(source.url, link),
                description: desc ?? '',
                sourceName: source.name,
                sourceUrl: source.url,
              ));
            }
          }
          break;
        }
      }
    } catch (_) {}
    return articles;
  }

  String? _getElementText(dynamic element, String tag) {
    try {
      final el = element.querySelector(tag);
      return el?.text.trim();
    } catch (_) {
      return null;
    }
  }

  String _cleanHtml(String text) {
    return text
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .trim();
  }

  int? _parseDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return null;
    if (RegExp(r'^\d+$').hasMatch(dateStr.trim())) {
      var n = int.parse(dateStr.trim());
      if (n < 1e12) n = n * 1000;
      return n;
    }
    try {
      return DateTime.parse(dateStr).millisecondsSinceEpoch;
    } catch (_) {
      return null;
    }
  }

  String _resolveUrl(String base, String url) {
    if (url.isEmpty) return '';
    if (url.startsWith('http')) return url;
    if (url.startsWith('//')) return 'https:$url';
    if (base.isEmpty) return url;
    try {
      return Uri.parse(base).resolve(url).toString();
    } catch (_) {
      return url;
    }
  }

  /// 测试RSS源是否可用
  Future<bool> testSource(RssSource source) async {
    try {
      final articles = await fetchRss(source);
      return articles.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
