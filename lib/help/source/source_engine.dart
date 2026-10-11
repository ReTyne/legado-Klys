import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/data/model/search_book.dart';
import 'package:legado_md3/data/model/book_chapter.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/replace_rule.dart';
import 'package:legado_md3/help/source/replace_rule_service.dart';
import 'package:legado_md3/help/source/rule_pipeline.dart';
import 'package:legado_md3/help/source/js/legado_js_runtime.dart';
import 'js_mini_eval.dart';
import 'package:legado_md3/help/http/cookie_manager.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:enough_convert/enough_convert.dart';

/// Legado书源引擎 - 对齐原版规则格式（CSS / XPath / JSONPath / 正则 / JS子集）
class BookSourceEngine {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 30),
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    },
  ));

  final ReplaceRuleService _replaceService = ReplaceRuleService();
  late final RulePipeline _pipeline = RulePipeline();

  /// 强制编码（阅读页可切换），null 时自动探测
  String? forcedCharset;
  void setCharset(String? cs) => forcedCharset = cs;

  /// 当前书源是否启用持久化 CookieJar（由各公共入口按书源设置写入）
  bool _persistCookieJar = false;
  final DatabaseService _cookieDb = DatabaseService();

  /// 请求节流：书源并发率 concurrentRate（纯数字=最小间隔毫秒；n/ms=每 ms 内 n 次）
  int _minIntervalMs = 0;
  DateTime? _lastFetchAt;
  void _applySourceFlags(BookSource source) {
    _persistCookieJar = source.enabledCookieJar;
    var interval = 0;
    final raw = source.concurrentRate?.trim() ?? '';
    if (raw.isNotEmpty) {
      final m = RegExp(r'^\s*(\d+)\s*/\s*(\d+)\s*$').firstMatch(raw);
      if (m != null) {
        final n = int.parse(m.group(1)!);
        final ms = int.parse(m.group(2)!);
        interval = n <= 0 ? ms : ms ~/ n;
      } else {
        interval = int.tryParse(raw) ?? 0;
      }
    }
    _minIntervalMs = interval;
    // 书源级编码（utf-8/gbk/gb18030…），留空则自动探测
    final cs = source.charset?.trim() ?? '';
    forcedCharset = cs.isEmpty ? null : cs;
  }

  // ==================== 编辑期智能补全专用 ====================

  /// 供书源编辑页“规则补全”抓取页面：应用书源标志、URL 模板、请求头、编码与 Cookie。
  /// [urlTpl] 可为搜索/发现 URL 模板（含 {{key}}/{{page}}）或任意绝对/相对地址。
  Future<String> editFetch(BookSource source, String urlTpl,
      {String keyword = '', int page = 1}) async {
    _applySourceFlags(source);
    final url = await _resolveUrlRule(source, urlTpl,
        key: keyword, page: page, baseUrl: source.bookSourceUrl);
    return _fetch(url, baseUrl: source.bookSourceUrl);
  }

  /// 解析相对地址为绝对地址（编辑页推导下一跳用）
  String resolveEditUrl(String url, String base) => _resolveUrl(url, base);

  /// 取发现配置中的第一条分类 URL 模板
  String firstExploreUrlOf(String exploreUrl) => _firstExploreUrl(exploreUrl);

  Future<void> _throttle() async {
    if (_minIntervalMs <= 0) return;
    final last = _lastFetchAt;
    if (last != null) {
      final elapsed = DateTime.now().difference(last).inMilliseconds;
      final wait = _minIntervalMs - elapsed;
      if (wait > 0) await Future.delayed(Duration(milliseconds: wait));
    }
    _lastFetchAt = DateTime.now();
  }

  /// 调试日志（环形，最近 120 条）
  final List<String> debugLog = [];
  void _log(String msg) {
    final t = DateTime.now().toIso8601String().substring(11, 19);
    debugLog.add('$t  $msg');
    if (debugLog.length > 120) debugLog.removeAt(0);
  }
  void clearDebugLog() => debugLog.clear();

  // ==================== URL / 请求 ====================

  /// 处理URL中的{{key}}/{{page}}/{{(page-1)*n}}模板
  String _processUrlTemplate(String url, String keyword, int page) {
    var result = url.replaceAll('{{key}}', Uri.encodeComponent(keyword));
    // 未编码的 key（部分站点需要原始中文）
    result = result.replaceAll('{{key}}', keyword);
    result = result.replaceAll('{{page}}', page.toString());
    final pageCalc = RegExp(r'\{\{\(page-1\)\*(\d+)\}\}');
    result = result.replaceAllMapped(pageCalc, (m) => ((page - 1) * int.parse(m.group(1)!)).toString());
    // searchKey 别名
    result = result.replaceAll('{{searchKey}}', Uri.encodeComponent(keyword));
    return result;
  }

  /// 解析URL和选项（原版格式：url,{options} / url,POST:body）
  Map<String, dynamic> _parseUrlWithOptions(String urlStr) {
    var url = urlStr.trim();
    final options = <String, dynamic>{};
    final commaJson = url.indexOf(',{');
    if (commaJson > 0) {
      final optStr = url.substring(commaJson + 1);
      url = url.substring(0, commaJson);
      try {
        final o = jsonDecode(optStr);
        if (o is Map) options.addAll(o.map((k, v) => MapEntry(k.toString(), v)));
      } catch (_) {}
      return {'url': url, 'options': options};
    }
    final m = RegExp(r'^(.+?),(POST|GET|PUT|DELETE)(?::(.*))?$', caseSensitive: false).firstMatch(url);
    if (m != null) {
      url = m.group(1)!.trim();
      options['method'] = m.group(2)!.toUpperCase();
      final b = m.group(3);
      if (b != null && b.isNotEmpty) options['body'] = b;
    }
    return {'url': url, 'options': options};
  }

  /// 发送HTTP请求，[baseUrl] 用于解析相对地址
  Future<String> _fetch(String url, {Map<String, dynamic>? options, String? body, String? baseUrl}) async {
    final parsed = _parseUrlWithOptions(url);
    var finalUrl = parsed['url'] as String;
    final opts = parsed['options'] as Map<String, dynamic>;

    // data: URI（书源用 data:;base64,<状态码> 在书址里携带上下文，不发起网络请求）
    if (finalUrl.startsWith('data:')) {
      final decoded = _decodeDataUri(finalUrl);
      _log('data: 书址解码，${decoded.length} 字符');
      return decoded;
    }

    finalUrl = _resolveUrl(finalUrl, baseUrl ?? '');

    final method = (opts['method'] ?? options?['method'] ?? 'GET').toString().toUpperCase();
    Map<String, dynamic>? headers;
    final rawHeaders = opts['headers'] ?? options?['headers'];
    if (rawHeaders is Map) {
      headers = Map<String, dynamic>.from(rawHeaders);
    } else if (rawHeaders is String && rawHeaders.trim().isNotEmpty) {
      try {
        headers = Map<String, dynamic>.from(jsonDecode(rawHeaders));
      } catch (_) {}
    }
    headers ??= {};
    headers.putIfAbsent('User-Agent',
        () => 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36');
    // 自动携带同域已保存的 Cookie（搜索->详情->目录->正文 之间保持会话）
    final cookieManager = CookieManager();
    var existCookie = cookieManager.cookieHeader(finalUrl);
    // 开启持久化 CookieJar 时，内存里没有则尝试从数据库恢复同域 Cookie
    if ((existCookie == null || existCookie.isEmpty) && _persistCookieJar) {
      try {
        final host = Uri.parse(finalUrl).host;
        final saved = await _cookieDb.getCookie(host);
        if (saved != null && saved.isNotEmpty) {
          for (final pair in saved.split(';')) {
            final idx = pair.indexOf('=');
            if (idx > 0) {
              cookieManager.saveFromResponse(finalUrl, ['${pair.trimLeft()};']);
            }
          }
          existCookie = cookieManager.cookieHeader(finalUrl);
        }
      } catch (_) {}
    }
    if (existCookie != null && existCookie.isNotEmpty) {
      headers.putIfAbsent('Cookie', () => existCookie);
    }
    // 书源级 charset 作为默认
    final dioOptions = Options(
        method: method,
        headers: headers,
        responseType: ResponseType.bytes,
        followRedirects: true,
        validateStatus: (s) => s != null && s < 400);

    await _throttle();
    _log('$method $finalUrl');
    Response<List<int>> response;
    try {
      if (method == 'POST' || method == 'PUT') {
        final postBody = body ?? opts['body'] ?? options?['body'] ?? '';
        response = method == 'PUT'
            ? await _dio.put(finalUrl, data: postBody, options: dioOptions)
            : await _dio.post(finalUrl, data: postBody, options: dioOptions);
      } else if (method == 'DELETE') {
        response = await _dio.delete(finalUrl, options: dioOptions);
      } else {
        response = await _dio.get(finalUrl, options: dioOptions);
      }
    } catch (e) {
      _log('请求失败: $e');
      rethrow;
    }
    // 保存服务器下发的 Set-Cookie，供后续同域请求使用
    cookieManager.saveFromResponse(finalUrl, response.headers.map['set-cookie']);
    // 开启持久化 CookieJar 时，把同域 Cookie 落库（跨启动/登录后保持会话）
    if (_persistCookieJar) {
      try {
        final header = cookieManager.cookieHeader(finalUrl);
        if (header != null && header.isNotEmpty) {
          await _cookieDb.saveCookie(Uri.parse(finalUrl).host, header);
        }
      } catch (_) {}
    }
    _log('响应 ${response.statusCode}, ${(response.data ?? []).length} 字节');
    final text = _decodeBytes(response.data ?? [], response.headers.map);
    _log('解码完成，文本 ${text.length} 字符');
    return text;
  }

  /// 按编码解码字节：强制编码 > Content-Type > HTML meta > utf-8（失败回退 GBK）
  String _decodeBytes(List<int> bytes, Map<String, List<String>> respHeaders) {
    String? cs = forcedCharset;
    final ct = (respHeaders['content-type'] ?? respHeaders['Content-Type'] ?? []).join(';').toLowerCase();
    final m = RegExp(r'charset=([a-z0-9\-]+)').firstMatch(ct);
    if (m != null) cs ??= m.group(1);
    if (cs == null) {
      final head = String.fromCharCodes(bytes.take(2048).map((b) => b & 0xff)).toLowerCase();
      final mm = RegExp(r"""charset=["']?([a-z0-9\-]+)""").firstMatch(head);
      if (mm != null) cs = mm.group(1);
    }
    cs = cs?.toLowerCase();
    try {
      if (cs == 'gbk' || cs == 'gb2312' || cs == 'gb18030') return GbkCodec().decode(bytes);
      if (cs == 'big5' || cs == 'big-5') return Big5Codec().decode(bytes);
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

  /// 解析相对URL
  String _resolveUrl(String url, String baseUrl) {
    if (url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    if (url.startsWith('//')) return 'https:$url';
    if (url.startsWith('data:') || url.startsWith('javascript:')) return url;
    if (baseUrl.isEmpty) return url;
    try {
      final base = Uri.parse(baseUrl);
      return base.resolve(url).toString();
    } catch (_) {
      if (url.startsWith('/') && baseUrl.isNotEmpty) {
        final uri = Uri.parse(baseUrl);
        return '${uri.scheme}://${uri.host}$url';
      }
      return url;
    }
  }

  /// 解析 data:[;base64],<payload> URI 为文本。
  /// 兼容书源在 base64 末尾额外挂载的 URL 选项，如
  /// `data:;base64,<b64>,{"type":"qingtian"}`（base64 字符集不含 `,{`）。
  String _decodeDataUri(String uri) {
    final comma = uri.indexOf(',');
    if (comma < 0) return '';
    final meta = uri.substring(5, comma);
    var payload = uri.substring(comma + 1);
    try {
      if (meta.contains('base64')) {
        final optIdx = payload.indexOf(',{');
        if (optIdx >= 0) payload = payload.substring(0, optIdx);
        var b64 = payload.trim();
        final pad = b64.length % 4;
        if (pad != 0) b64 = b64.padRight(b64.length + (4 - pad), '=');
        return utf8.decode(base64Decode(b64), allowMalformed: true);
      }
      return Uri.decodeComponent(payload);
    } catch (_) {
      return '';
    }
  }

  bool _isJson(String content) {
    final t = content.trim();
    return t.startsWith('{') || t.startsWith('[');
  }

  // ==================== JS 运行时集成 ====================

  static final RegExp _leadingJs = RegExp(r'^\s*<js>([\s\S]*?)</js>');
  static final RegExp _wholeJs = RegExp(r'^\s*<js>([\s\S]*?)</js>\s*$');
  static final RegExp _mustache = RegExp(r'\{\{([\s\S]*?)\}\}');

  /// 求值一段书源脚本，返回字符串结果（任何异常都安全降级为 null）。
  Future<String?> _evalJs(
    BookSource source,
    String script, {
    dynamic result,
    String? key,
    int? page,
    String? baseUrl,
    Map<String, dynamic>? book,
    Map<String, dynamic>? chapter,
    bool isUrlRule = false,
  }) async {
    final s = script.trim();
    if (s.isEmpty) return null;
    try {
      final rt = await JsRuntimeManager.instance.forSource(source);
      final out = await rt.eval(JsEvalRequest(
        source: source,
        script: s,
        result: result,
        key: key,
        page: page,
        baseUrl: baseUrl,
        book: book,
        chapter: chapter,
        isUrlRule: isUrlRule,
      ));
      for (final l in out.logs) {
        if (l.trim().isNotEmpty) _log('[JS] $l');
      }
      for (final t in out.toasts) {
        if (t.trim().isNotEmpty) _log('[JS提示] $t');
      }
      if (out.error != null && out.error!.isNotEmpty) {
        final first = out.error!.split('\n').take(3).join(' ');
        _log('[JS异常] $first');
      }
      return out.stringValue;
    } catch (e) {
      _log('[JS运行时不可用] $e');
      // 降级到迷你求值器
      return JsMiniEvaluator.eval(s,
          result: result is String ? result : (result == null ? null : jsonEncode(result)),
          key: key,
          page: page,
          baseUrl: baseUrl);
    }
  }

  /// 解析 URL 规则：`<js>` 脚本求值（可返回 `url,{options}`），否则走模板替换。
  Future<String> _resolveUrlRule(
    BookSource source,
    String urlTpl, {
    String? key,
    int? page,
    String? baseUrl,
    Map<String, dynamic>? book,
  }) async {
    final t = urlTpl.trim();
    final m = _leadingJs.firstMatch(t);
    if (m != null) {
      final script = m.group(1)!;
      final tail = t.substring(m.end).trim();
      var v = await _evalJs(source, script,
          key: key, page: page, baseUrl: baseUrl, book: book, isUrlRule: true);
      if (v == null || v.trim().isEmpty) {
        return _processUrlTemplate(urlTpl, key ?? '', page ?? 1);
      }
      v = v.trim();
      if (tail.isNotEmpty) v = '$v$tail';
      return _processUrlTemplate(v, key ?? '', page ?? 1);
    }
    return _processUrlTemplate(urlTpl, key ?? '', page ?? 1);
  }

  /// 异步解析 JSON 节点字段（支持 `<js>`、`{{$.x}}`、`$.x`、## 后处理、尾部 @js）。
  Future<String?> _fieldFromJsonAsync(
    BookSource source,
    dynamic item,
    String rule, {
    String? baseUrl,
    String? key,
    int? page,
    Map<String, dynamic>? book,
    Map<String, dynamic>? chapter,
  }) async {
    final r = rule.trim();
    if (r.isEmpty) return null;
    final parts = _pipeline.parseFieldParts(r);
    var selector = parts.selector.trim();
    String? value;

    final lead = _leadingJs.firstMatch(selector);
    if (lead != null) {
      final v = await _evalJs(source, lead.group(1)!,
          result: item, baseUrl: baseUrl, key: key, page: page, book: book, chapter: chapter);
      final suffix = selector.substring(lead.end).trim();
      if (v == null) {
        value = null;
      } else if (suffix.isNotEmpty) {
        value = _fieldFromMixed(v, suffix);
      } else {
        value = v;
      }
    } else if (selector.contains('{{')) {
      value = await _mustacheAsync(source, selector, item,
          baseUrl: baseUrl, key: key, page: page, book: book, chapter: chapter);
    } else if (selector.toLowerCase().startsWith('@js:')) {
      value = await _evalJs(source, selector.substring(4),
          result: item, baseUrl: baseUrl, key: key, page: page, book: book, chapter: chapter);
    } else if (selector.isNotEmpty) {
      value = _pipeline.fieldFromJson(item, selector);
    } else {
      value = item?.toString();
    }

    if (value == null) return null;
    value = _pipeline.applyFieldOps(value, parts.ops);
    if (parts.tailJs != null && value.isNotEmpty) {
      value = await _evalJs(source, parts.tailJs!,
          result: value, baseUrl: baseUrl, key: key, page: page, book: book, chapter: chapter) ??
          value;
    }
    return value.isEmpty ? null : value;
  }

  /// JS 产出的字符串可能是 JSON / HTML，按剩余选择器再取一次。
  String? _fieldFromMixed(String jsOutput, String suffix) {
    final s = suffix.trim();
    if (s.isEmpty) return jsOutput;
    if (_isJson(jsOutput)) {
      try {
        return _pipeline.fieldFromJson(jsonDecode(jsOutput), s);
      } catch (_) {}
    }
    return _pipeline.extractStringFromRaw(jsOutput, s);
  }

  /// 处理 `{{...}}` mustache（内部为 JS，`$`/result 绑定为当前 JSON 节点）。
  Future<String> _mustacheAsync(
    BookSource source,
    String template,
    dynamic node, {
    String? baseUrl,
    String? key,
    int? page,
    Map<String, dynamic>? book,
    Map<String, dynamic>? chapter,
  }) async {
    final sb = StringBuffer();
    var last = 0;
    for (final m in _mustache.allMatches(template).toList()) {
      sb.write(template.substring(last, m.start));
      final expr = m.group(1)!.trim();
      final v = await _evalJs(source, expr,
          result: node, baseUrl: baseUrl, key: key, page: page, book: book, chapter: chapter);
      sb.write(v ?? '');
      last = m.end;
    }
    sb.write(template.substring(last));
    return sb.toString();
  }

  /// 异步解析 HTML 元素字段（含 JS 时用 outerHtml 作为 result）。
  Future<String?> _fieldFromElementAsync(
    BookSource source,
    dom.Element el,
    String rule, {
    String? baseUrl,
    String? key,
    int? page,
    Map<String, dynamic>? book,
    Map<String, dynamic>? chapter,
  }) async {
    final r = rule.trim();
    if (r.isEmpty) return null;
    if (ruleNeedsRealJs(r)) {
      final parts = _pipeline.parseFieldParts(r);
      var selector = parts.selector.trim();
      String? value;
      final lead = _leadingJs.firstMatch(selector);
      if (lead != null) {
        final v = await _evalJs(source, lead.group(1)!,
            result: el.outerHtml, baseUrl: baseUrl, key: key, page: page, book: book, chapter: chapter);
        final suffix = selector.substring(lead.end).trim();
        value = (v == null) ? null : (suffix.isEmpty ? v : (_fieldFromMixed(v, suffix) ?? v));
      } else if (selector.contains('{{')) {
        value = await _mustacheAsync(source, selector, el.outerHtml,
            baseUrl: baseUrl, key: key, page: page, book: book, chapter: chapter);
      } else if (selector.toLowerCase().startsWith('@js:')) {
        value = await _evalJs(source, selector.substring(4),
            result: el.outerHtml, baseUrl: baseUrl, key: key, page: page, book: book, chapter: chapter);
      } else {
        value = _pipeline.fieldFromElement(el, selector);
      }
      if (value == null) return null;
      value = _pipeline.applyFieldOps(value, parts.ops);
      if (parts.tailJs != null && value.isNotEmpty) {
        value = await _evalJs(source, parts.tailJs!,
            result: value, baseUrl: baseUrl, key: key, page: page, book: book, chapter: chapter) ??
            value;
      }
      return value.isEmpty ? null : value;
    }
    return _pipeline.fieldFromElement(el, r);
  }

  Map<String, dynamic> _bookSeed({String? bookUrl, String? name, String? author, int? durChapterIndex}) {
    return {
      'bookUrl': bookUrl ?? '',
      'name': name ?? '',
      'author': author ?? '',
      'durChapterIndex': durChapterIndex ?? 0,
      'durChapterTitle': '',
      'tocUrl': bookUrl ?? '',
      'coverUrl': '',
      'intro': '',
    };
  }

  // ==================== 列表提取 ====================

  /// 统一提取书籍列表（自动 HTML / JSON，支持前置 <js>）。
  Future<List<Map<String, String>>> _extractBookList(
    BookSource source,
    String content,
    Map<String, dynamic> rule,
    String baseUrl, {
    String? key,
    int? page,
  }) async {
    var listRule = (rule['bookList'] ?? '').toString();
    if (listRule.isEmpty) return [];
    _pipeline
      ..baseUrl = baseUrl
      ..page = null
      ..keyword = null;

    final reverse = listRule.trim().startsWith('-');
    if (reverse) listRule = listRule.trim().substring(1).trim();

    // 前置 <js>：脚本产出新内容（JSON 字符串/对象/HTML），剩余选择器继续取列表。
    final lead = _leadingJs.firstMatch(listRule.trim());
    if (lead != null) {
      final v = await _evalJs(source, lead.group(1)!,
          result: content, key: key, page: page, baseUrl: baseUrl);
      final suffix = listRule.trim().substring(lead.end).trim();
      if (v != null && v.isNotEmpty) {
        content = v;
        listRule = suffix.isEmpty ? '' : suffix;
      }
    }

    final result = <Map<String, String>>[];
    final isJson = _isJson(content);

    if (isJson) {
      dynamic json;
      try {
        json = jsonDecode(content);
      } catch (_) {
        return [];
      }
      // <js> 直接返回数组且无后续选择器
      List<dynamic> nodes;
      if (listRule.isEmpty) {
        nodes = json is List ? json : (json is Map && json['data'] is List ? json['data'] as List : const []);
      } else {
        nodes = _pipeline.selectJsonNodes(json, listRule);
      }
      for (final item in nodes) {
        if (item is! Map) continue;
        final b = await _bookFromJsonItem(source, item, rule, baseUrl, key: key, page: page);
        if (b['name']!.isNotEmpty) result.add(b);
      }
    } else {
      if (listRule.isEmpty) return [];
      final doc = html_parser.parse(content);
      var elements = _pipeline.selectElements(doc, listRule);
      if (reverse) elements = elements.reversed.toList();
      for (final el in elements) {
        final b = await _bookFromElement(source, el, rule, baseUrl, key: key, page: page);
        if (b['name']!.isNotEmpty) result.add(b);
      }
      if (reverse) return result;
      return result;
    }

    if (reverse) return result.reversed.toList();
    return result;
  }

  Future<Map<String, String>> _bookFromElement(
    BookSource source,
    dom.Element el,
    Map<String, dynamic> rule,
    String baseUrl, {
    String? key,
    int? page,
  }) async {
    Future<String?> f(String fieldKey) async {
      final r = rule[fieldKey]?.toString() ?? '';
      if (r.isEmpty) return null;
      return _fieldFromElementAsync(source, el, r, baseUrl: baseUrl, key: key, page: page);
    }

    return {
      'name': (await f('name') ?? '').trim(),
      'author': (await f('author') ?? '').trim(),
      'coverUrl': _resolveUrl(await f('coverUrl') ?? '', baseUrl),
      'bookUrl': _resolveUrl(await f('bookUrl') ?? '', baseUrl),
      'intro': (await f('intro') ?? '').trim(),
      'kind': (await f('kind') ?? '').trim(),
      'lastChapter': (await f('lastChapter') ?? '').trim(),
      'wordCount': (await f('wordCount') ?? '').trim(),
    };
  }

  Future<Map<String, String>> _bookFromJsonItem(
    BookSource source,
    dynamic item,
    Map<String, dynamic> rule,
    String baseUrl, {
    String? key,
    int? page,
  }) async {
    Future<String?> f(String fieldKey) async {
      final r = rule[fieldKey]?.toString() ?? '';
      if (r.isEmpty) return null;
      return _fieldFromJsonAsync(source, item, r, baseUrl: baseUrl, key: key, page: page);
    }

    return {
      'name': (await f('name') ?? '').trim(),
      'author': (await f('author') ?? '').trim(),
      'coverUrl': _resolveUrl(await f('coverUrl') ?? '', baseUrl),
      'bookUrl': _resolveUrl(await f('bookUrl') ?? '', baseUrl),
      'intro': (await f('intro') ?? '').trim(),
      'kind': (await f('kind') ?? '').trim(),
      'lastChapter': (await f('lastChapter') ?? '').trim(),
      'wordCount': (await f('wordCount') ?? '').trim(),
    };
  }

  List<SearchBook> _toSearchBooks(List<Map<String, String>> books, BookSource source) => books
      .map((b) => SearchBook(
            name: b['name'] ?? '',
            author: b['author'] ?? '',
            coverUrl: b['coverUrl'] ?? '',
            bookUrl: b['bookUrl'] ?? '',
            intro: b['intro'] ?? '',
            kind: b['kind'] ?? '',
            lastChapter: b['lastChapter'] ?? '',
            originName: source.bookSourceName,
            origin: source.bookSourceUrl,
          ))
      .toList();

  // ==================== 公开 API ====================

  /// 搜索书籍
  Future<List<SearchBook>> search(BookSource source, String keyword, {int page = 1}) async {
    _applySourceFlags(source);
    if (source.searchUrl == null || source.searchUrl!.isEmpty) return [];
    if (source.ruleSearch == null) return [];
    try {
      final url = await _resolveUrlRule(source, source.searchUrl!,
          key: keyword, page: page, baseUrl: source.bookSourceUrl);
      _log('搜索关键字: $keyword');
      final content = await _fetch(url, baseUrl: source.bookSourceUrl);
      final books = await _extractBookList(source, content, source.ruleSearch!,
          source.bookSourceUrl, key: keyword, page: page);
      _log('搜索到 ${books.length} 本');
      return _toSearchBooks(books, source);
    } catch (e) {
      _log('搜索异常: $e');
      return [];
    }
  }

  /// 发现书籍（使用第一个发现分类）
  Future<List<SearchBook>> explore(BookSource source, {int page = 1}) async {
    _applySourceFlags(source);
    if (source.exploreUrl == null || source.exploreUrl!.isEmpty) return [];
    final firstUrl = _firstExploreUrl(source.exploreUrl!);
    return exploreByUrl(source, firstUrl, page: page);
  }

  /// 按指定发现分类 URL 探索
  Future<List<SearchBook>> exploreByUrl(BookSource source, String exploreUrl, {int page = 1}) async {
    _applySourceFlags(source);
    if (source.ruleExplore == null || exploreUrl.isEmpty) return [];
    try {
      final url = await _resolveUrlRule(source, exploreUrl,
          key: '', page: page, baseUrl: source.bookSourceUrl);
      final content = await _fetch(url, baseUrl: source.bookSourceUrl);
      final books = await _extractBookList(source, content, source.ruleExplore!,
          source.bookSourceUrl, page: page);
      return _toSearchBooks(books, source);
    } catch (e) {
      _log('发现异常: $e');
      return [];
    }
  }

  /// 从 exploreUrl 配置取第一条具体 URL。
  /// 兼容 "名称:::url"（三冒号）与 "名称::url"（两冒号），
  /// 多行分隔，同行多选项用 &&& 连接（与发现页解析保持一致）。
  String _firstExploreUrl(String exploreUrl) {
    final line = exploreUrl
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    if (line.isEmpty) return '';
    final firstOpt = line.split('&&&').first.trim();
    final sep3 = firstOpt.indexOf(':::');
    if (sep3 >= 0) return firstOpt.substring(sep3 + 3).trim();
    final sep2 = firstOpt.indexOf('::');
    if (sep2 >= 0) return firstOpt.substring(sep2 + 2).trim();
    return firstOpt;
  }

  /// 获取书籍详情
  Future<Book?> getBookInfo(BookSource source, String bookUrl,
      {String? presetName, String? presetAuthor}) async {
    _applySourceFlags(source);
    try {
      final rule = source.ruleBookInfo ?? {};
      var content = await _fetch(bookUrl, baseUrl: source.bookSourceUrl);
      _pipeline.baseUrl = source.bookSourceUrl;
      final seed = _bookSeed(
          bookUrl: bookUrl, name: presetName, author: presetAuthor);

      // ruleBookInfo.init：可发起二次请求并替换正文
      final initRule = rule['init']?.toString() ?? '';
      if (initRule.trim().isNotEmpty) {
        final init = await _evalRuleContent(source, content, initRule,
            baseUrl: bookUrl, book: seed);
        if (init != null && init.isNotEmpty) content = init;
      }

      final isJson = _isJson(content);
      final jsonNode = isJson ? jsonDecode(content) : null;

      Future<String?> field(String key) async {
        final r = rule[key]?.toString() ?? '';
        if (r.isEmpty) return null;
        if (ruleNeedsRealJs(r)) {
          return _fieldFromJsonAsync(source, jsonNode ?? content, r,
              baseUrl: bookUrl, book: seed);
        }
        return isJson
            ? _pipeline.fieldFromJson(jsonNode, r)
            : _pipeline.extractStringFromRaw(content, r);
      }

      final name = ((await field('name')) ?? presetName ?? '').trim();
      final author = ((await field('author')) ?? presetAuthor ?? '').trim();
      var coverUrl = _resolveUrl(await field('coverUrl') ?? '', source.bookSourceUrl);
      final intro = await field('intro') ?? '';
      final kind = await field('kind') ?? '';
      final lastChapter = await field('lastChapter') ?? '';
      var tocUrl = bookUrl;
      final toc = await field('tocUrl');
      if (toc != null && toc.isNotEmpty) tocUrl = _resolveUrl(toc, bookUrl);

      if (name.isEmpty) {
        _log('详情：未解析到书名');
        return null;
      }
      seed['name'] = name;
      seed['author'] = author;
      seed['tocUrl'] = tocUrl;
      return Book(
        name: name,
        author: author,
        coverUrl: coverUrl,
        intro: intro,
        kind: kind,
        lastChapter: lastChapter,
        noteUrl: tocUrl,
        bookUrl: bookUrl,
        originName: source.bookSourceName,
        origin: source.bookSourceUrl,
      );
    } catch (e) {
      _log('详情异常: $e');
      return null;
    }
  }

  /// 处理一段「以内容为 result」的规则：支持前置 <js>（输出替换内容）或纯选择器。
  Future<String?> _evalRuleContent(
    BookSource source,
    String content,
    String rule, {
    String? baseUrl,
    Map<String, dynamic>? book,
    Map<String, dynamic>? chapter,
  }) async {
    final r = rule.trim();
    if (r.isEmpty) return null;
    final lead = _leadingJs.firstMatch(r);
    if (lead != null) {
      final v = await _evalJs(source, lead.group(1)!,
          result: content, baseUrl: baseUrl, book: book, chapter: chapter);
      final suffix = r.substring(lead.end).trim();
      if (v == null) return null;
      if (suffix.isEmpty) return v;
      return _fieldFromMixed(v, suffix) ?? v;
    }
    final whole = _wholeJs.firstMatch(r);
    if (whole != null) {
      return _evalJs(source, whole.group(1)!,
          result: content, baseUrl: baseUrl, book: book, chapter: chapter);
    }
    return _pipeline.extractStringFromRaw(content, r);
  }

  /// 获取章节目录（支持 nextTocUrl 翻页拼接、前置 <js>）
  Future<List<BookChapter>> getToc(BookSource source, String tocUrl,
      {Map<String, dynamic>? bookInfo}) async {
    _applySourceFlags(source);
    if (source.ruleToc == null) return [];
    final chapters = <BookChapter>[];
    var currentUrl = tocUrl;
    final visited = <String>{};
    final seed = bookInfo ?? _bookSeed(bookUrl: tocUrl);
    try {
      for (var page = 0; page < 20; page++) {
        if (visited.contains(currentUrl)) break;
        visited.add(currentUrl);

        var content = await _fetch(currentUrl, baseUrl: source.bookSourceUrl);
        final rule = source.ruleToc!;
        var listRule = (rule['chapterList'] ?? '').toString();
        if (listRule.isEmpty) break;
        final reverse = listRule.trim().startsWith('-');
        if (reverse) listRule = listRule.trim().substring(1).trim();
        _pipeline.baseUrl = currentUrl;

        // 前置 <js>（如 hex 解码、二次 ajax 后返回 JSON/HTML）
        final lead = _leadingJs.firstMatch(listRule.trim());
        String jsSuffix = '';
        if (lead != null) {
          final v = await _evalJs(source, lead.group(1)!,
              result: content, baseUrl: currentUrl, book: seed);
          jsSuffix = listRule.trim().substring(lead.end).trim();
          if (v != null && v.isNotEmpty) content = v;
          listRule = jsSuffix;
        }

        final isJson = _isJson(content);
        final pageChapters = <Map<String, String>>[];
        if (isJson) {
          final json = jsonDecode(content);
          final nodes = listRule.isEmpty
              ? (json is List ? json : const [])
              : _pipeline.selectJsonNodes(json, listRule);
          for (final item in nodes) {
            if (item is! Map) continue;
            final title = (await _fieldFromJsonAsync(
                    source, item, rule['chapterName']?.toString() ?? '',
                    baseUrl: currentUrl, book: seed) ??
                '').trim();
            var url = await _fieldFromJsonAsync(
                source, item, rule['chapterUrl']?.toString() ?? '',
                baseUrl: currentUrl, book: seed);
            final isVolume = await _fieldFromJsonAsync(
                    source, item, rule['isVolume']?.toString() ?? '',
                    baseUrl: currentUrl, book: seed) ??
                '';
            pageChapters.add({
              'title': title,
              'url': _resolveUrl(url ?? '', currentUrl),
              'isVolume': isVolume,
            });
          }
        } else {
          if (listRule.isEmpty) break;
          final doc = html_parser.parse(content);
          var elements = _pipeline.selectElements(doc, listRule);
          if (reverse) elements = elements.reversed.toList();
          for (final el in elements) {
            Future<String?> f(String key) async {
              final r = rule[key]?.toString() ?? '';
              if (r.isEmpty) return null;
              return _fieldFromElementAsync(source, el, r,
                  baseUrl: currentUrl, book: seed);
            }
            final title = (await f('chapterName') ?? el.text.trim()).trim();
            final url = _resolveUrl(
                await f('chapterUrl') ?? el.attributes['href'] ?? '', currentUrl);
            final isVolume = await f('isVolume') ?? '';
            pageChapters.add({'title': title, 'url': url, 'isVolume': isVolume});
          }
        }

        for (final c in pageChapters) {
          chapters.add(BookChapter(
            index: chapters.length,
            title: c['title'] ?? '',
            url: c['url'] ?? '',
            isVolume: (c['isVolume'] ?? '') == '1' ||
                (c['isVolume'] ?? '').toLowerCase() == 'true',
          ));
        }

        // 目录下一页
        final nextRule = rule['nextTocUrl']?.toString() ?? '';
        if (nextRule.isEmpty) break;
        String? next;
        if (ruleNeedsRealJs(nextRule)) {
          next = await _evalRuleContent(source, content, nextRule,
              baseUrl: currentUrl, book: seed);
        } else {
          next = isJson
              ? _pipeline.fieldFromJson(jsonDecode(content), nextRule)
              : _pipeline.extractStringFromRaw(content, nextRule);
        }
        if (next == null || next.isEmpty || next == currentUrl) break;
        currentUrl = _resolveUrl(next, currentUrl);
      }

      return chapters.where((c) => c.title.isNotEmpty).toList();
    } catch (e) {
      _log('目录异常: $e');
      return chapters;
    }
  }

  /// 获取正文内容
  Future<String?> getContent(BookSource source, String contentUrl,
      {List<ReplaceRule>? replaceRules,
      Map<String, dynamic>? bookInfo,
      Map<String, dynamic>? chapter}) async {
    _applySourceFlags(source);
    if (source.ruleContent == null) return null;
    try {
      final rule = source.ruleContent!;
      final raw = await _fetch(contentUrl, baseUrl: source.bookSourceUrl);
      _pipeline.baseUrl = contentUrl;
      final contentRule = (rule['content'] ?? '').toString();
      if (contentRule.isEmpty) return null;

      final seed = bookInfo ?? _bookSeed(bookUrl: chapter?['bookUrl']?.toString());
      if (chapter != null) seed['durChapterIndex'] = chapter['index'] ?? 0;
      final ch = chapter ?? {'index': 0, 'title': '', 'url': contentUrl};

      var result = await _evalRuleContent(source, raw, contentRule,
          baseUrl: contentUrl, book: seed, chapter: ch);
      if (result == null || result.isEmpty) {
        _log('正文：规则未匹配到内容');
        return null;
      }

      // 正文分页：递归抓取 nextContentUrl 拼接（最多 10 页）
      final nextRule = rule['nextContentUrl']?.toString() ?? '';
      if (nextRule.isNotEmpty) {
        result = await _appendNextPages(source, raw, result, nextRule, contentUrl, 1,
            book: seed, chapter: ch);
      }

      // 图片正文：规则为 imageContent 时保留 <img>
      final keepImage = rule['imageContent']?.toString() == '1' ||
          rule['imageContent']?.toString() == 'true' ||
          rule['imageStyle']?.toString() == 'full';

      // 应用替换净化
      if (replaceRules != null && replaceRules.isNotEmpty) {
        result = _replaceService.applyRules(result, replaceRules, scope: source.bookSourceUrl);
      }

      result = keepImage ? _cleanHtmlKeepImages(result) : _cleanHtml(result);
      return result.trim();
    } catch (e) {
      _log('正文异常: $e');
      return null;
    }
  }

  /// 递归拼接分页正文
  Future<String> _appendNextPages(
      BookSource source, String pageContent, String acc, String nextRule, String currentUrl, int depth,
      {Map<String, dynamic>? book, Map<String, dynamic>? chapter}) async {
    if (depth >= 10) return acc;
    try {
      var nextUrl = await _evalRuleContent(source, pageContent, nextRule,
          baseUrl: currentUrl, book: book, chapter: chapter);
      if (nextUrl == null || nextUrl.isEmpty || nextUrl == currentUrl) return acc;
      nextUrl = _resolveUrl(nextUrl, currentUrl);

      final nextContent = await _fetch(nextUrl, baseUrl: source.bookSourceUrl);
      final contentRule = source.ruleContent!['content']?.toString() ?? '';
      final part = await _evalRuleContent(source, nextContent, contentRule,
          baseUrl: nextUrl, book: book, chapter: chapter);
      if (part == null || part.isEmpty) return acc;
      acc = '$acc\n${_cleanHtml(part)}';
      final nnRule = source.ruleContent!['nextContentUrl']?.toString() ?? '';
      if (nnRule.isNotEmpty) {
        return await _appendNextPages(source, nextContent, acc, nnRule, nextUrl, depth + 1,
            book: book, chapter: chapter);
      }
      return acc;
    } catch (_) {
      return acc;
    }
  }

  /// 清理HTML标签（纯文本）
  String _cleanHtml(String html) {
    var h = html;
    h = h.replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true), '');
    h = h.replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true), '');
    h = h.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    h = h.replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n');
    h = h.replaceAll(RegExp(r'<[^>]+>'), '');
    h = _decodeEntities(h);
    h = h.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return h.trim();
  }

  /// 清理HTML但保留图片地址（漫画/图文章节），每张图单独一行
  String _cleanHtmlKeepImages(String html) {
    var h = html;
    h = h.replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true), '');
    h = h.replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true), '');
    final imgs = <String>[];
    h = h.replaceAllMapped(RegExp(r'<img[^>]*>', caseSensitive: false), (m) {
      final tag = m.group(0)!;
      final src = RegExp(r'''(?:src|data-src)=["']?([^"'\s>]+)''').firstMatch(tag)?.group(1);
      if (src != null) imgs.add(src);
      return '\n';
    });
    h = h.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    h = h.replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n');
    h = h.replaceAll(RegExp(r'<[^>]+>'), '');
    h = _decodeEntities(h);
    final text = h.trim();
    final imageLines = imgs.join('\n');
    return [text, imageLines].where((s) => s.isNotEmpty).join('\n');
  }

  String _decodeEntities(String s) => s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&hellip;', '…')
      .replaceAll('&mdash;', '—')
      .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)))
      .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m.group(1)!)));
}
