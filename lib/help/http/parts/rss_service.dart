/// 由 rss_service.dart 按「一类一文件」拆出的 RssService。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../rss_service.dart';


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
      // 起始页：startJs 执行结果 / startHtml 静态 HTML 优先，否则抓取 sourceUrl
      final start = await _resolveStartPage(source, source.url);
      final content = start.html;
      if (content.isEmpty) return articles;
      articles.addAll(_parseRss(content, source));
      if (articles.isEmpty) articles.addAll(_parseAtom(content, source));
      if (articles.isEmpty &&
          (source.ruleArticles?.trim().isNotEmpty ?? false)) {
        articles.addAll(await _parseByRules(source, content,
            startUrl: start.url));
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

  // ============================ 起始页 ============================

  /// 计算取文章列表的起始页。
  /// 优先级：startJs 执行结果（URL 或 HTML）> startHtml 静态 HTML > 抓取 baseUrl。
  /// startJs 依赖 JS 引擎（能执行则执行）；执行失败时容错回退，不阻塞主链路。
  Future<_StartPage> _resolveStartPage(RssSource s, String baseUrl) async {
    // 1) startJs：执行得到起始 URL（http 开头则继续抓取）或直接得到 HTML
    final js = (s.startJs ?? '').trim();
    if (js.isNotEmpty) {
      try {
        final rt = await JsRuntimeManager.instance.forSource(s);
        final res = await rt.eval(JsEvalRequest(
          source: s,
          script: _stripJs(js),
          result: '',
          baseUrl: baseUrl,
        ));
        final v = (res.stringValue ?? '').trim();
        if (v.startsWith('http')) {
          // JS 产出 URL：按该 URL 抓取起始页，并执行 loginCheckJs（对齐 E Rss.kt:57）
          final header = await _resolveHeader(s);
          var html = await _httpGet(v, header, source: s);
          html = await _applyLoginCheck(s, html, v);
          if (html.isNotEmpty) return _StartPage(html, v);
        } else if (v.contains('<')) {
          // JS 直接产出 HTML：作为待解析起始页（相对链接仍按 baseUrl 解析）
          return _StartPage(v, baseUrl);
        }
        // 其它返回值（空 / 非 URL 非 HTML）：按后续逻辑降级
      } catch (_) {
        // JS 引擎不可用或执行异常：忽略，继续走 startHtml / 默认抓取
      }
    }
    // 2) startHtml：直接作为待解析 HTML 起始页（支持 {{}} mustache 求值）
    final sh = (s.startHtml ?? '').trim();
    if (sh.isNotEmpty) {
      final html = sh.contains('{{')
          ? await _applyMustache(s, sh, result: '', baseUrl: baseUrl)
          : sh;
      return _StartPage(html, baseUrl);
    }
    // 3) 默认：抓取页面（逻辑源 / data: 源无页面可抓时返回空）
    var html = baseUrl.startsWith('http')
        ? await _httpGet(baseUrl, await _resolveHeader(s), source: s)
        : '';
    // 对齐 E Rss.kt getArticlesAwait：响应正文经 loginCheckJs 检测/改写
    html = await _applyLoginCheck(s, html, baseUrl);
    return _StartPage(html, baseUrl);
  }

  /// 执行 loginCheckJs（对齐 E Rss.kt:57 / :108「检测源是否已登录」）。
  /// JS 可返回改写后的响应正文（E 中以 StrResponse 形式回写），非空则替换原文；
  /// 求值失败一律保留原文、不阻断主链路。
  Future<String> _applyLoginCheck(
      RssSource s, String body, String baseUrl) async {
    final js = (s.loginCheckJs ?? '').trim();
    if (js.isEmpty || body.isEmpty) return body;
    try {
      final rt = await JsRuntimeManager.instance.forSource(s);
      final script = await _applyMustache(s, _stripJs(js),
          result: body, baseUrl: baseUrl);
      final res = await rt.eval(JsEvalRequest(
          source: s, script: script, result: body, baseUrl: baseUrl));
      final v = (res.stringValue ?? '').trim();
      return v.isEmpty ? body : v;
    } catch (_) {
      return body;
    }
  }

  /// 正文规则：对齐 E ContentRule.kt 的 `content` 字段。
  /// 兼容两种写法：JSON 对象 `{"content":...,"nextContentUrl":...}` 或纯规则字符串。
  String _contentRuleOf(RssSource s) =>
      _contentRuleMap(s)['content'] ?? (s.ruleContent ?? '').trim();

  /// 正文下一页规则：对齐 E ContentRule.kt 的 `nextContentUrl` 字段。
  /// 当前主线 RssSource 无独立字段（lib/data 不改动），故从 ruleContent 的
  /// JSON 对象按新结构解析；纯字符串规则则返回空（不启用多页）。
  String _nextContentRuleOf(RssSource s) =>
      _contentRuleMap(s)['nextContentUrl'] ?? '';

  Map<String, String> _contentRuleMap(RssSource s) {
    final raw = (s.ruleContent ?? '').trim();
    if (!raw.startsWith('{')) return const {};
    try {
      final m = jsonDecode(raw);
      if (m is Map) {
        return m.map((k, v) =>
            MapEntry(k.toString(), v == null ? '' : v.toString().trim()));
      }
    } catch (_) {}
    return const {};
  }

  /// 取正文下一页链接（对齐 E BookContent.kt:254 analyzeContentPage）：
  /// sourceType==0 且 nextContentUrl 规则非空时，逐条解析为绝对地址。
  List<String> _nextContentUrls(
      RssSource s, String html, String baseUrl) {
    final rule = _nextContentRuleOf(s);
    if (s.sourceType != 0 || rule.isEmpty || html.isEmpty) return const [];
    _pipeline.baseUrl = baseUrl;
    try {
      return _pipeline
          .extractListFromRaw(html, rule)
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .map((e) => _resolveUrl(baseUrl, e))
          .toList();
    } catch (_) {
      return const [];
    }
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

    // 抓取页面（best effort；部分逻辑源不依赖页面）。
    // startJs / startHtml 优先：逻辑源常以 startHtml 提供列表页 HTML。
    final start = await _resolveStartPage(s, baseUrl);
    var pageContent = start.html;

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
  /// 对齐 E Rss.getContentAwait + BookContent 正文翻页：单条 nextContentUrl
  /// 串行循环，多条并发取完，各页以 "\n" 拼接后再走白/黑名单过滤。
  Future<String?> fetchArticleContent(RssSource s, RssArticle article) async {
    final rule = _contentRuleOf(s);
    if (rule.isEmpty) return article.description ?? article.content ?? '';
    final rt = await JsRuntimeManager.instance.forSource(s);

    Future<String> contentOfPage(String url, String html) async {
      final am = article.jsContext();
      var body = _stripJs(rule);
      body = await _applyMustache(s, body,
          result: html, baseUrl: url, rssArticle: am);
      final res = await rt.eval(JsEvalRequest(
          source: s,
          script: body,
          result: html,
          baseUrl: url,
          rssArticle: am));
      return res.stringValue ?? '';
    }

    Future<String> htmlOfPage(String url) async {
      final header = await _resolveHeader(s);
      final html = await _httpGet(url, header, source: s);
      // 对齐 E Rss.kt:108：正文响应同样经 loginCheckJs 检测/改写
      return _applyLoginCheck(s, html, url);
    }

    final firstUrl = article.link;
    final firstHtml =
        firstUrl.startsWith('http') ? await htmlOfPage(firstUrl) : '';
    final contents = <String>[await contentOfPage(firstUrl, firstHtml)];

    const maxPages = 50; // 规则写错时防死循环
    final firstNext = _nextContentUrls(s, firstHtml, firstUrl);
    if (firstNext.length == 1) {
      final visited = <String>{firstUrl};
      var nextUrl = firstNext.first;
      while (nextUrl.isNotEmpty &&
          visited.add(nextUrl) &&
          contents.length < maxPages) {
        final html = await htmlOfPage(nextUrl);
        contents.add(await contentOfPage(nextUrl, html));
        final nx = _nextContentUrls(s, html, nextUrl);
        nextUrl = nx.isEmpty ? '' : nx.first;
      }
    } else if (firstNext.length > 1) {
      final pages = await Future.wait(firstNext.map((u) async {
        final html = await htmlOfPage(u);
        return contentOfPage(u, html);
      }));
      contents.addAll(pages);
    }

    // 白名单/黑名单按 CSS 选择器过滤后再返回
    return _applyContentFilter(
        contents.where((e) => e.trim().isNotEmpty).join('\n'),
        s.contentWhitelist,
        s.contentBlacklist);
  }

  /// 内容白名单/黑名单过滤（按 CSS 选择器）。
  /// [whitelist] 非空时只保留选择器命中的内容；[blacklist] 删除选择器命中的内容。
  /// 选择器列表支持逗号/中文逗号/换行分隔。
  /// 解析或选择器异常时保留原 HTML，避免破坏正文。
  String _applyContentFilter(String html, String? whitelist, String? blacklist) {
    final wl = _splitSelectors(whitelist);
    final bl = _splitSelectors(blacklist);
    if (html.isEmpty || (wl.isEmpty && bl.isEmpty)) return html;
    try {
      final doc = html_parser.parse(html);
      // 黑名单：删除匹配节点
      for (final sel in bl) {
        for (final el in doc.querySelectorAll(sel)) {
          el.remove();
        }
      }
      // 白名单：仅保留匹配节点内容；无命中时保留原 HTML，防止误清空正文
      if (wl.isNotEmpty) {
        final kept = <dom.Element>[];
        for (final sel in wl) {
          kept.addAll(doc.querySelectorAll(sel));
        }
        if (kept.isNotEmpty) {
          final sb = StringBuffer();
          for (final el in kept) {
            sb.write(el.outerHtml);
          }
          return sb.toString();
        }
      }
      return doc.body?.innerHtml ?? html;
    } catch (_) {
      // 选择器非法 / 解析异常：保留原 HTML
      return html;
    }
  }

  /// 拆分选择器列表：逗号、中文逗号、换行分隔，去空白、去空项
  List<String> _splitSelectors(String? raw) {
    final r = (raw ?? '').trim();
    if (r.isEmpty) return const [];
    return r
        .split(RegExp(r'[,，\r\n]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
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

  /// 抓取原始页面文本。
  /// [source] 非空且 enabledCookieJar 为真时，按 E AnalyzeUrl 的 cookieJar 语义：
  /// 请求自动带上已保存 Cookie，并把响应的 Set-Cookie 写回 CookieJar
  /// （与书源网络层共用同一 [CookieManager] 单例，登录后会话互通）。
  Future<String> _httpGet(String url, String? headerJson,
      {RssSource? source}) async {
    if (!url.startsWith('http')) return '';
    try {
      final jarEnabled = source?.enabledCookieJar ?? false;
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
      if (jarEnabled) {
        final ck = CookieManager().cookieHeader(url);
        if (ck != null && ck.isNotEmpty) headers['Cookie'] = ck;
      }
      final resp = await _dio.get(url, options: Options(headers: headers));
      if (jarEnabled) {
        CookieManager().saveFromResponse(url, resp.headers.map['set-cookie']);
      }
      return _decode(resp.data ?? const <int>[], resp.headers.map);
    } catch (_) {
      return '';
    }
  }

  /// 委托共享解码器：透明解压 + 去 BOM + 编码优先级（含 HTML meta 与统计探测）
  String _decode(List<int> bytes, Map<String, List<String>> headers) =>
      HttpResponseDecoder.decode(bytes, headers: headers);

  /// 依据用户自定义规则抓取文章列表（支持 ruleNextPage 翻页，最多 5 页）
  /// [startUrl] 起始页实际地址（startJs 可能改写），默认取 source.url
  Future<List<RssArticle>> _parseByRules(RssSource source, String firstContent,
      {String? startUrl}) async {
    final out = <RssArticle>[];
    final seen = <String>{};
    var content = firstContent;
    var currentUrl = startUrl ?? source.url;
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
      content = await _httpGet(currentUrl, source.header, source: source);
      if (content.isEmpty) break;
      // 对齐 E Rss.kt：翻页响应同样经 loginCheckJs
      content = await _applyLoginCheck(source, content, currentUrl);
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
