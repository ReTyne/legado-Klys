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
import 'package:legado_md3/help/source/url_option.dart';
import 'package:legado_md3/help/source/ttf_parser.dart';
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

  /// 书源级请求头（来自 source.header 字段，JSON 格式或 JS 求值结果）
  Map<String, dynamic> _sourceHeaders = {};
  BookSource? _currentSource;

  /// 当前书源是否启用持久化 CookieJar（由各公共入口按书源设置写入）
  bool _persistCookieJar = false;
  final DatabaseService _cookieDb = DatabaseService();

  /// 请求节流：书源并发率 concurrentRate（纯数字=最小间隔毫秒；n/ms=每 ms 内 n 次）
  int _minIntervalMs = 0;
  DateTime? _lastFetchAt;
  void _applySourceFlags(BookSource source) {
    _currentSource = source;
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
    // 书源级请求头（JSON 格式，支持 @js: 前缀的 JS 求值）
    _sourceHeaders = {};
    final hdr = source.header?.trim() ?? '';
    if (hdr.isNotEmpty) {
      try {
        if (hdr.toLowerCase().startsWith('@js:')) {
          // JS 求值头（异步，延迟到请求时处理）
          _sourceHeaders = {'__js__': hdr.substring(4)};
        } else {
          final parsed = jsonDecode(hdr);
          if (parsed is Map) {
            _sourceHeaders = parsed.map((k, v) => MapEntry(k.toString(), v));
          }
        }
      } catch (_) {}
    }
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


  /// 取一个 URL 选项的字符串值（不存在或为 null 时返回 null）
  static String? _optStr(Map<String, dynamic>? opts, String key) {
    if (opts == null) return null;
    final v = opts[key];
    if (v == null) return null;
    final s = v.toString();
    return s;
  }

  /// 发送HTTP请求，[baseUrl] 用于解析相对地址
  Future<String> _fetch(String url, {Map<String, dynamic>? options, String? body, String? baseUrl}) async {
    // URL 里的 `{{...}}` / `,{json}` / `,POST:body` 选项统一由 UrlOptions 解析
    final parsed = UrlOptions.parse(url);
    var finalUrl = parsed.url;
    final opts = parsed.options;

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

    // 合并书源级 header（URL 选项中的 header 优先级更高）
    if (_sourceHeaders.isNotEmpty) {
      final jsHdr = _sourceHeaders['__js__'];
      if (jsHdr != null && _currentSource != null) {
        // JS 型 header：求值后合并
        try {
          final evaluated = await _evalJs(_currentSource!, jsHdr.toString(),
              baseUrl: baseUrl);
          if (evaluated != null && evaluated.isNotEmpty) {
            final parsed = jsonDecode(evaluated);
            if (parsed is Map) {
              for (final e in parsed.entries) {
                headers.putIfAbsent(e.key.toString(), () => e.value);
              }
            }
          }
        } catch (_) {}
      } else {
        for (final e in _sourceHeaders.entries) {
          if (e.key != '__js__') {
            headers.putIfAbsent(e.key, () => e.value);
          }
        }
      }
    }

    headers.putIfAbsent('User-Agent',
        () => 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36');

    // URL 选项：charset（响应编码覆盖）、type（POST Content-Type）、retry（重试次数）
    final optCharset = (opts['charset'] ?? options?['charset'])?.toString();
    final optType = (opts['type'] ?? options?['type'])?.toString();
    final optRetry = int.tryParse((opts['retry'] ?? options?['retry'] ?? '0').toString()) ?? 0;

    // URL 选项：UA / Cookie / Referer（legado {{ua=}} {{cookie=}} {{referer=}}）
    final optUa = _optStr(opts, 'ua') ?? _optStr(options, 'ua');
    if (optUa != null && optUa.isNotEmpty) headers['User-Agent'] = optUa;
    final optCookie = _optStr(opts, 'cookie') ?? _optStr(options, 'cookie');
    if (optCookie != null && optCookie.isNotEmpty) headers['Cookie'] = optCookie;
    final optReferer = _optStr(opts, 'referer') ?? _optStr(options, 'referer');
    if (optReferer != null && optReferer.isNotEmpty) headers['Referer'] = optReferer;

    // URL 选项：超时与严格状态码
    final optTimeout = int.tryParse((_optStr(opts, 'timeout') ?? _optStr(options, 'timeout') ?? ''));
    final optStrict = opts['strict'] ?? options?['strict'];

    // URL 选项：{{host=xxx}} 多域名切换（用于源里定义的备用域名）
    final optHost = _optStr(opts, 'host') ?? _optStr(options, 'host');
    if (optHost != null && optHost.isNotEmpty) {
      try {
        final u = Uri.parse(finalUrl);
        final h = optHost.replaceFirst(RegExp(r'^https?://'), '');
        final seg = h.split('/').where((s) => s.isNotEmpty).toList();
        final rest = seg.skip(1).join('/');
        final pathTail = rest.isEmpty ? '' : (rest.startsWith('/') ? rest : '/$rest');
        final newPath = u.path.isEmpty ? pathTail : (pathTail.isEmpty ? u.path : '${u.path.replaceAll(RegExp(r'/$'), '')}$pathTail');
        final q = u.query.isEmpty ? '' : '?${u.query}';
        final frag = u.fragment.isEmpty ? '' : '#${u.fragment}';
        final rebuilt = '${u.scheme}://${seg.first}$newPath$q$frag';
        _log('host 切换: ${u.host} -> ${seg.first}');
        finalUrl = rebuilt;
      } catch (e) {
        _log('host 选项解析失败: $e');
      }
    }

    // URL 选项：{{webView=true}} —— 本项目无无头 WebView 能力，降级为普通请求
    if ((opts['webview'] ?? options?['webview']) == true) {
      _log('webView 选项：无头 WebView 不可用，降级为普通请求');
    }

    var optBody = body ?? opts['body'] ?? options?['body'] ?? '';
    // bodyJs：用 JS 生成请求体
    final bodyJs = (opts['bodyJs'] ?? options?['bodyJs'])?.toString() ?? '';
    if (bodyJs.isNotEmpty && _currentSource != null) {
      try {
        final jsBody = await _evalJs(_currentSource!, bodyJs,
            baseUrl: baseUrl, result: optBody);
        if (jsBody != null && jsBody.isNotEmpty) optBody = jsBody;
      } catch (_) {}
    }
    // POST type：form 表单编码
    if (method == 'POST' && optType != null && optType.isNotEmpty) {
      if (optType.toLowerCase().contains('form') && optBody is String && optBody.isNotEmpty) {
        headers.putIfAbsent('Content-Type', () => 'application/x-www-form-urlencoded');
      } else if (optType.toLowerCase().contains('json')) {
        headers.putIfAbsent('Content-Type', () => 'application/json');
      }
    }
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
        receiveTimeout: optTimeout != null && optTimeout > 0 ? Duration(milliseconds: optTimeout) : null,
        validateStatus: optStrict == false ? (s) => s != null && s < 500 : (s) => s != null && s < 400);

    await _throttle();
    _log('$method $finalUrl');
    Response<List<int>> response;
    var attempt = 0;
    while (true) {
      try {
        if (method == 'POST' || method == 'PUT') {
          response = method == 'PUT'
              ? await _dio.put(finalUrl, data: optBody, options: dioOptions)
              : await _dio.post(finalUrl, data: optBody, options: dioOptions);
        } else if (method == 'DELETE') {
          response = await _dio.delete(finalUrl, options: dioOptions);
        } else {
          response = await _dio.get(finalUrl, options: dioOptions);
        }
        break;
      } catch (e) {
        if (attempt < optRetry) {
          attempt++;
          _log('请求失败，第 $attempt 次重试: $e');
          await Future.delayed(Duration(milliseconds: 500 * attempt));
          continue;
        }
        _log('请求失败: $e');
        rethrow;
      }
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
    // URL 选项中的 charset 优先级最高
    final originalForced = forcedCharset;
    if (optCharset != null && optCharset.isNotEmpty) {
      forcedCharset = optCharset;
    }
    final text = _decodeBytes(response.data ?? [], response.headers.map);
    forcedCharset = originalForced;
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
    // data: 型源地址无法作为相对URL解析基准，直接返回（JS应已构造完整URL）
    if (baseUrl.startsWith('data:')) return url;
    try {
      final base = Uri.parse(baseUrl);
      if (!base.hasScheme || !base.hasAuthority) return url;
      return base.resolve(url).toString();
    } catch (_) {
      if (url.startsWith('/') && baseUrl.isNotEmpty) {
        try {
          final uri = Uri.parse(baseUrl);
          if (uri.hasScheme && uri.hasAuthority) {
            return '${uri.scheme}://${uri.authority}$url';
          }
        } catch (_) {}
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
        // 脚本失败/为空：若规则本身由 JS 驱动，绝不能把 <js> 字面量当 URL 请求
        if (t.contains('<js>') || t.contains('@js:')) return '';
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
    // checkKeyWord：校验关键字是否符合源要求（正则）
    final checkKw = source.checkKeyWord?.trim() ?? '';
    if (checkKw.isNotEmpty) {
      try {
        if (!RegExp(checkKw).hasMatch(keyword)) {
          _log('关键字不符合校验规则: $checkKw');
          return [];
        }
      } catch (_) {}
    }
    try {
      final url = await _resolveUrlRule(source, source.searchUrl!,
          key: keyword, page: page, baseUrl: source.bookSourceUrl);
      if (url.trim().isEmpty) {
        _log('searchUrl 执行失败或为空（检查 JS 依赖的 source/cookie 状态）');
        return [];
      }
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

  /// 解析发现页分类列表（exploreUrl 配置）
  /// 返回 [{title, url}]，兼容三冒号/两冒号、多行、&&& 多选项
  List<Map<String, String>> getExploreKinds(BookSource source) {
    final raw = source.exploreUrl?.trim() ?? '';
    if (raw.isEmpty) return [];
    final kinds = <Map<String, String>>[];
    for (final line in raw.split('\n')) {
      final l = line.trim();
      if (l.isEmpty) continue;
      // 同行多选项用 &&& 分隔
      for (final opt in l.split('&&&')) {
        final o = opt.trim();
        if (o.isEmpty) continue;
        final sep3 = o.indexOf(':::');
        if (sep3 >= 0) {
          kinds.add({'title': o.substring(0, sep3).trim(), 'url': o.substring(sep3 + 3).trim()});
          continue;
        }
        final sep2 = o.indexOf('::');
        if (sep2 >= 0) {
          kinds.add({'title': o.substring(0, sep2).trim(), 'url': o.substring(sep2 + 2).trim()});
          continue;
        }
        kinds.add({'title': o, 'url': o});
      }
    }
    return kinds;
  }

  /// 检查登录状态（执行 loginCheckJs，返回非空表示已登录）
  Future<bool> checkLogin(BookSource source) async {
    final js = source.loginCheckJs?.trim() ?? '';
    if (js.isEmpty) return false;
    _applySourceFlags(source);
    try {
      final result = await _evalJs(source, js, baseUrl: source.bookSourceUrl);
      return result != null && result.trim().isNotEmpty && result.trim() != 'false' && result.trim() != '0';
    } catch (_) {
      return false;
    }
  }

  /// 检查书籍 URL 是否匹配该书源的 bookUrlPattern
  bool matchBookUrl(BookSource source, String bookUrl) {
    final pattern = source.bookUrlPattern?.trim() ?? '';
    if (pattern.isEmpty) return false;
    try {
      return RegExp(pattern).hasMatch(bookUrl);
    } catch (_) {
      return false;
    }
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

      // ruleBookInfo.init：支持 <js> 脚本（可返回新内容或新URL）或纯 URL 规则
      final initRule = rule['init']?.toString() ?? '';
      if (initRule.trim().isNotEmpty) {
        final init = await _evalRuleContent(source, content, initRule,
            baseUrl: bookUrl, book: seed);
        if (init != null && init.isNotEmpty) {
          // init 返回的可能是新 URL（需要二次请求）或新内容
          final trimmed = init.trim();
          if ((trimmed.startsWith('http://') || trimmed.startsWith('https://') ||
                  trimmed.startsWith('/')) &&
              !_isJson(trimmed) &&
              !trimmed.contains('<')) {
            final newUrl = _resolveUrl(trimmed, bookUrl);
            _log('init 跳转: $newUrl');
            content = await _fetch(newUrl, baseUrl: source.bookSourceUrl);
          } else {
            content = init;
          }
        }
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
      // coverDecodeJs：封面解密（对 coverUrl 执行 JS）
      final coverDecode = source.coverDecodeJs?.trim() ?? '';
      if (coverDecode.isNotEmpty && coverUrl.isNotEmpty) {
        try {
          final decoded = await _evalJs(source, coverDecode,
              result: coverUrl, baseUrl: bookUrl, book: seed);
          if (decoded != null && decoded.isNotEmpty) {
            coverUrl = _resolveUrl(decoded, source.bookSourceUrl);
          }
        } catch (_) {}
      }
      final intro = await field('intro') ?? '';
      final kind = await field('kind') ?? '';
      final lastChapter = await field('lastChapter') ?? '';
      final wordCountStr = await field('wordCount');
      final canReName = await field('canReName');
      final downloadUrl = await field('downloadUrl');
      final relatedBooks = await field('relatedBooks');
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
      // 把扩展信息存入 infoHtml（JSON 格式，供后续使用）
      final extra = <String, dynamic>{};
      if (canReName != null && canReName.isNotEmpty) extra['canReName'] = canReName;
      if (downloadUrl != null && downloadUrl.isNotEmpty) extra['downloadUrl'] = downloadUrl;
      if (relatedBooks != null && relatedBooks.isNotEmpty) extra['relatedBooks'] = relatedBooks;
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
        wordCount: int.tryParse(wordCountStr?.replaceAll(RegExp(r'[^0-9]'), '') ?? ''),
        infoHtml: extra.isNotEmpty ? jsonEncode(extra) : null,
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

  /// 获取章节目录（支持 nextTocUrl 翻页拼接、前置 <js>、preUpdateJs、formatJs）
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

        // preUpdateJs：目录更新前执行的 JS（可修改 content 或返回新 URL）
        final preUpdate = rule['preUpdateJs']?.toString() ?? '';
        if (preUpdate.trim().isNotEmpty) {
          final pre = await _evalJs(source, preUpdate,
              result: content, baseUrl: currentUrl, book: seed);
          if (pre != null && pre.isNotEmpty) {
            final trimmed = pre.trim();
            if ((trimmed.startsWith('http://') || trimmed.startsWith('https://') ||
                    trimmed.startsWith('/')) &&
                !_isJson(trimmed) &&
                !trimmed.contains('<')) {
              currentUrl = _resolveUrl(trimmed, currentUrl);
              content = await _fetch(currentUrl, baseUrl: source.bookSourceUrl);
            } else {
              content = pre;
            }
          }
        }

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
            final isVip = await _fieldFromJsonAsync(
                    source, item, rule['isVip']?.toString() ?? '',
                    baseUrl: currentUrl, book: seed) ??
                '';
            final isPay = await _fieldFromJsonAsync(
                    source, item, rule['isPay']?.toString() ?? '',
                    baseUrl: currentUrl, book: seed) ??
                '';
            final updateTime = await _fieldFromJsonAsync(
                    source, item, rule['updateTime']?.toString() ??
                        rule['chapterInfo']?.toString() ?? '',
                    baseUrl: currentUrl, book: seed) ??
                '';
            pageChapters.add({
              'title': title,
              'url': _resolveUrl(url ?? '', currentUrl),
              'isVolume': isVolume,
              'isVip': isVip,
              'isPay': isPay,
              'updateTime': updateTime,
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
            final isVip = await f('isVip') ?? '';
            final isPay = await f('isPay') ?? '';
            var updateTime = await f('updateTime');
            if (updateTime == null || updateTime.isEmpty) {
              updateTime = await f('chapterInfo') ?? '';
            }
            pageChapters.add({
              'title': title,
              'url': url,
              'isVolume': isVolume,
              'isVip': isVip,
              'isPay': isPay,
              'updateTime': updateTime,
            });
          }
        }

        // formatJs：对每个章节标题/URL 执行格式化 JS
        final formatJs = rule['formatJs']?.toString() ?? '';
        if (formatJs.trim().isNotEmpty) {
          for (var i = 0; i < pageChapters.length; i++) {
            final chCtx = {
              'index': chapters.length + i,
              'title': pageChapters[i]['title'],
              'url': pageChapters[i]['url'],
              'isVolume': pageChapters[i]['isVolume'],
            };
            try {
              final formatted = await _evalJs(source, formatJs,
                  result: jsonEncode(chCtx), baseUrl: currentUrl, book: seed, chapter: chCtx);
              if (formatted != null && formatted.isNotEmpty) {
                // formatJs 可返回 JSON {title, url} 或纯文本标题
                if (_isJson(formatted)) {
                  try {
                    final obj = jsonDecode(formatted);
                    if (obj is Map) {
                      if (obj['title'] != null) pageChapters[i]['title'] = obj['title'].toString();
                      if (obj['url'] != null) pageChapters[i]['url'] = obj['url'].toString();
                    }
                  } catch (_) {}
                } else {
                  pageChapters[i]['title'] = formatted;
                }
              }
            } catch (_) {}
          }
        }

        for (final c in pageChapters) {
          chapters.add(BookChapter(
            index: chapters.length,
            title: c['title'] ?? '',
            url: c['url'] ?? '',
            isVolume: (c['isVolume'] ?? '') == '1' ||
                (c['isVolume'] ?? '').toLowerCase() == 'true',
            isVip: (c['isVip'] ?? '') == '1' ||
                (c['isVip'] ?? '').toLowerCase() == 'true',
            isPay: (c['isPay'] ?? '') == '1' ||
                (c['isPay'] ?? '').toLowerCase() == 'true',
            updateTime: (c['updateTime'] ?? '').isEmpty ? null : c['updateTime'],
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

      // webJs：需要 WebView 渲染的页面（记录日志，降级为普通解析）
      final webJs = rule['webJs']?.toString() ?? '';
      if (webJs.trim().isNotEmpty) {
        _log('webJs 规则存在，当前使用普通解析（WebView 渲染需前端配合）');
      }

      var result = await _evalRuleContent(source, raw, contentRule,
          baseUrl: contentUrl, book: seed, chapter: ch);
      if (result == null || result.isEmpty) {
        _log('正文：规则未匹配到内容');
        return null;
      }
      var text = result; // 非空提升

      // subContent：副文规则（追加到正文后）
      final subRule = rule['subContent']?.toString() ?? '';
      if (subRule.trim().isNotEmpty) {
        final sub = await _evalRuleContent(source, raw, subRule,
            baseUrl: contentUrl, book: seed, chapter: ch);
        if (sub != null && sub.isNotEmpty) {
          text = '$text\n$sub';
        }
      }

      // sourceRegex：正则截取正文区域（先于选择器结果的二次过滤）
      final srcRe = rule['sourceRegex']?.toString() ?? '';
      if (srcRe.trim().isNotEmpty) {
        try {
          final m = RegExp(srcRe, dotAll: true).firstMatch(text);
          if (m != null) {
            text = m.groupCount > 0 ? (m.group(1) ?? text) : m.group(0)!;
          }
        } catch (_) {}
      }

      // 正文分页：递归抓取 nextContentUrl 拼接（最多 10 页）
      final nextRule = rule['nextContentUrl']?.toString() ?? '';
      if (nextRule.isNotEmpty) {
        text = await _appendNextPages(source, raw, text, nextRule, contentUrl, 1,
            book: seed, chapter: ch);
      }

      // 图片正文：规则为 imageContent 时保留 <img>
      final keepImage = rule['imageContent']?.toString() == '1' ||
          rule['imageContent']?.toString() == 'true' ||
          rule['imageStyle']?.toString() == 'full';

      // imageDecode：图片解密 JS（对提取到的图片 URL 执行解密）
      final imageDecode = rule['imageDecode']?.toString() ?? '';
      if (imageDecode.trim().isNotEmpty && keepImage) {
        text = await _decodeImages(source, text, imageDecode, contentUrl, seed, ch);
      }

      // replaceRegex：书源内联替换规则（格式：正则##替换 或 JSON 数组）
      final repRe = rule['replaceRegex']?.toString() ?? '';
      if (repRe.trim().isNotEmpty) {
        text = _applySourceReplaceRegex(text, repRe);
      }

      // 应用替换净化
      if (replaceRules != null && replaceRules.isNotEmpty) {
        text = _replaceService.applyRules(text, replaceRules, scope: source.bookSourceUrl);
      }

      // callBackJs：正文获取完成后的回调 JS
      final callBack = rule['callBackJs']?.toString() ?? '';
      if (callBack.trim().isNotEmpty) {
        try {
          await _evalJs(source, callBack,
              result: text, baseUrl: contentUrl, book: seed, chapter: ch);
        } catch (_) {}
      }

      text = keepImage ? _cleanHtmlKeepImages(text) : _cleanHtml(text);
      return text.trim();
    } catch (e) {
      _log('正文异常: $e');
      return null;
    }
  }

  /// 对正文中的图片 URL 执行解密 JS
  Future<String> _decodeImages(BookSource source, String html, String decodeJs,
      String baseUrl, Map<String, dynamic> book, Map<String, dynamic> chapter) async {
    final imgUrls = <String>[];
    final replaced = html.replaceAllMapped(RegExp(r'<img[^>]*>', caseSensitive: false), (m) {
      final tag = m.group(0)!;
      final src = RegExp(r'''(?:src|data-src)=["']?([^"'\s>]+)''').firstMatch(tag)?.group(1);
      if (src != null) imgUrls.add(src);
      return tag;
    });
    if (imgUrls.isEmpty) return html;
    final decodedMap = <String, String>{};
    for (final url in imgUrls) {
      try {
        final decoded = await _evalJs(source, decodeJs,
            result: url, baseUrl: baseUrl, book: book, chapter: chapter);
        if (decoded != null && decoded.isNotEmpty) {
          decodedMap[url] = _resolveUrl(decoded, baseUrl);
        }
      } catch (_) {}
    }    var result = replaced;
    decodedMap.forEach((old, neu) {
      result = result.replaceAll(old, neu);
    });
    return result;
  }

  /// 应用书源内联 replaceRegex：支持 "正则##替换" 多行或 JSON 数组
  String _applySourceReplaceRegex(String content, String rule) {
    var result = content;
    final trimmed = rule.trim();
    // JSON 数组格式：[{"regex":"...","replacement":"..."}]
    if (trimmed.startsWith('[')) {
      try {
        final arr = jsonDecode(trimmed);
        if (arr is List) {
          for (final item in arr) {
            if (item is Map) {
              final re = item['regex']?.toString() ?? item['rule']?.toString() ?? '';
              final rep = item['replacement']?.toString() ?? item['to']?.toString() ?? '';
              if (re.isNotEmpty) {
                try {
                  result = result.replaceAll(RegExp(re, dotAll: true), rep);
                } catch (_) {}
              }
            }
          }
        }
        return result;
      } catch (_) {}
    }
    // 多行格式：每行 "正则##替换"
    for (final line in trimmed.split('\n')) {
      final l = line.trim();
      if (l.isEmpty) continue;
      final idx = l.indexOf('##');
      if (idx > 0) {
        final re = l.substring(0, idx);
        final rep = l.substring(idx + 2);
        try {
          result = result.replaceAll(RegExp(re, dotAll: true), rep);
        } catch (_) {}
      } else {
        // 无 ## 时视为删除匹配
        try {
          result = result.replaceAll(RegExp(l, dotAll: true), '');
        } catch (_) {}
      }
    }
    return result;
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

  // ==================== 字体反爬 (TTF) ====================

  /// 下载 TTF 字体并构建字符替换映射（供 java.replaceFont 调用）
  Future<Map<String, String>> loadFontReplacementMap(String fontUrl,
      {String? baseUrl}) async {
    try {
      final resolved = _resolveUrl(fontUrl, baseUrl ?? '');
      final resp = await _dio.get(resolved,
          options: Options(responseType: ResponseType.bytes));
      if (resp.data is List<int>) {
        final parser = TtfParser.fromBytes(resp.data as List<int>);
        return parser.buildReplacementMap();
      }
    } catch (e) {
      _log('字体加载失败: $e');
    }
    return {};
  }

  /// 应用字体替换映射到文本
  String applyFontReplacement(String text, Map<String, String> map) {
    if (map.isEmpty) return text;
    var result = text;
    map.forEach((from, to) {
      result = result.replaceAll(from, to);
    });
    return result;
  }

  // ==================== 书源类型 ====================

  /// 是否为文本书源（bookSourceType=0）
  bool isTextSource(BookSource source) => source.bookSourceType == 0;

  /// 是否为音频书源（bookSourceType=1）
  bool isAudioSource(BookSource source) => source.bookSourceType == 1;

  /// 是否为图片/漫画书源（bookSourceType=2）
  bool isImageSource(BookSource source) => source.bookSourceType == 2;

  /// 是否为文件/下载站书源（bookSourceType=3）
  bool isFileSource(BookSource source) => source.bookSourceType == 3;

  /// 是否为视频书源（bookSourceType=4）
  bool isVideoSource(BookSource source) => source.bookSourceType == 4;

  /// 获取图片书源内容（返回图片 URL 列表，每行一个）
  Future<String?> getImageContent(BookSource source, String contentUrl,
      {Map<String, dynamic>? bookInfo, Map<String, dynamic>? chapter}) async {
    _applySourceFlags(source);
    final rule = source.ruleImage ?? source.ruleContent;
    if (rule == null) return null;
    try {
      final raw = await _fetch(contentUrl, baseUrl: source.bookSourceUrl);
      _pipeline.baseUrl = contentUrl;
      final imageRule = (rule['imageList'] ?? rule['content'] ?? '').toString();
      if (imageRule.isEmpty) return null;

      final seed = bookInfo ?? _bookSeed(bookUrl: chapter?['bookUrl']?.toString());
      final ch = chapter ?? {'index': 0, 'title': '', 'url': contentUrl};

      var result = await _evalRuleContent(source, raw, imageRule,
          baseUrl: contentUrl, book: seed, chapter: ch);
      if (result == null || result.isEmpty) return null;

      // 图片下一页
      final nextRule = rule['nextContentUrl']?.toString() ?? '';
      if (nextRule.isNotEmpty) {
        result = await _appendNextPages(source, raw, result, nextRule, contentUrl, 1,
            book: seed, chapter: ch);
      }

      // 提取所有图片 URL
      final urls = <String>[];
      final imgMatches = RegExp(r'<img[^>]*>', caseSensitive: false).allMatches(result);
      for (final m in imgMatches) {
        final tag = m.group(0)!;
        final src = RegExp(r'''(?:src|data-src)=["']?([^"'\s>]+)''').firstMatch(tag)?.group(1);
        if (src != null) urls.add(_resolveUrl(src, contentUrl));
      }
      // 如果没有 img 标签，按行分割作为 URL
      if (urls.isEmpty) {
        for (final line in result.split('\n')) {
          final l = line.trim();
          if (l.isNotEmpty && (l.startsWith('http') || l.startsWith('/'))) {
            urls.add(_resolveUrl(l, contentUrl));
          }
        }
      }
      return urls.join('\n');
    } catch (e) {
      _log('图片内容异常: $e');
      return null;
    }
  }

  /// 获取音频书源内容（返回音频 URL）
  Future<String?> getAudioContent(BookSource source, String contentUrl,
      {Map<String, dynamic>? bookInfo, Map<String, dynamic>? chapter}) async {
    _applySourceFlags(source);
    if (source.ruleContent == null) return null;
    try {
      final rule = source.ruleContent!;
      final raw = await _fetch(contentUrl, baseUrl: source.bookSourceUrl);
      _pipeline.baseUrl = contentUrl;
      final seed = bookInfo ?? _bookSeed(bookUrl: chapter?['bookUrl']?.toString());
      final ch = chapter ?? {'index': 0, 'title': '', 'url': contentUrl};

      // 优先用 content 规则，其次用 sourceRegex 提取音频 URL
      final contentRule = (rule['content'] ?? '').toString();
      if (contentRule.isNotEmpty) {
        final result = await _evalRuleContent(source, raw, contentRule,
            baseUrl: contentUrl, book: seed, chapter: ch);
        if (result != null && result.isNotEmpty) {
          // 尝试从结果中提取音频 URL
          final urlMatch = RegExp(r'https?://[^\s<>"]+\.(?:mp3|m4a|aac|wav|ogg|flac)', caseSensitive: false)
              .firstMatch(result);
          if (urlMatch != null) return urlMatch.group(0);
          return result.trim();
        }
      }
      // sourceRegex 提取
      final srcRe = rule['sourceRegex']?.toString() ?? '';
      if (srcRe.isNotEmpty) {
        try {
          final m = RegExp(srcRe, dotAll: true).firstMatch(raw);
          if (m != null) {
            return (m.groupCount > 0 ? m.group(1) : m.group(0))?.trim();
          }
        } catch (_) {}
      }
      return null;
    } catch (e) {
      _log('音频内容异常: $e');
      return null;
    }
  }

  /// 解析视频内容（视频书源）：从正文规则提取视频 URL（mp4/m3u8/webm 等）。
  Future<String?> getVideoContent(BookSource source, String contentUrl,
      {Map<String, dynamic>? bookInfo, Map<String, dynamic>? chapter}) async {
    _applySourceFlags(source);
    if (source.ruleContent == null) return null;
    try {
      final rule = source.ruleContent!;
      final raw = await _fetch(contentUrl, baseUrl: source.bookSourceUrl);
      _pipeline.baseUrl = contentUrl;
      final seed = bookInfo ?? _bookSeed(bookUrl: chapter?['bookUrl']?.toString());
      final ch = chapter ?? {'index': 0, 'title': '', 'url': contentUrl};

      final contentRule = (rule['content'] ?? '').toString();
      if (contentRule.isNotEmpty) {
        final result = await _evalRuleContent(source, raw, contentRule,
            baseUrl: contentUrl, book: seed, chapter: ch);
        if (result != null && result.isNotEmpty) {
          final urlMatch = RegExp(r'https?://[^\s<>"]+\.(?:mp4|m3u8|webm|flv|ts|mkv|mov|avi)',
                  caseSensitive: false)
              .firstMatch(result);
          if (urlMatch != null) return urlMatch.group(0);
          // 若结果本身即纯 URL（如 m3u8 无扩展名结尾）
          final pure = result.trim();
          if (pure.startsWith('http') && !pure.contains('\n') && !pure.contains('<')) {
            return pure;
          }
        }
      }
      final srcRe = rule['sourceRegex']?.toString() ?? '';
      if (srcRe.isNotEmpty) {
        try {
          final m = RegExp(srcRe, dotAll: true).firstMatch(raw);
          if (m != null) {
            return (m.groupCount > 0 ? m.group(1) : m.group(0))?.trim();
          }
        } catch (_) {}
      }
      return null;
    } catch (e) {
      _log('视频内容异常: $e');
      return null;
    }
  }
}
