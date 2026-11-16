/// 书源引擎的可复用纯函数集合。
///
/// 这里只放无 I/O、无运行时依赖的纯逻辑：URL 绝对化、请求方法规范化、
/// 参数编码、请求头清洗、选项读取、发现分类解析、去重与分页上限、
/// 正文呈现选项、登录检测判定、JS 变量前缀生成。主链路与测试共用同一份
/// 实现，保证行为可直接验证。
library;

import 'dart:convert';

// ==================== URL 绝对化 ====================

/// 把 [url] 按 [baseUrl] 解析为绝对地址。
///
/// 覆盖：绝对 http(s)、协议相对 `//`、data:/javascript: 直通、空 base、
/// data: 型 base 不作为解析基准、根相对 `/path`、一般相对路径。
String resolveUrlBase(String url, String baseUrl) {
  if (url.isEmpty) return '';
  final low = url.toLowerCase();
  if (low.startsWith('http://') || low.startsWith('https://')) return url;
  if (url.startsWith('//')) return 'https:$url';
  if (low.startsWith('data:') || low.startsWith('javascript:')) return url;
  if (baseUrl.isEmpty) return url;
  if (baseUrl.toLowerCase().startsWith('data:')) return url;
  try {
    final base = Uri.parse(baseUrl);
    if (!base.hasScheme || !base.hasAuthority) return url;
    return base.resolve(url).toString();
  } catch (_) {
    if (url.startsWith('/')) {
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

/// 优先以 [redirectUrl]（最近一次响应的最终地址）作为相对地址基准；
/// 没有重定向时回退 [baseUrl]。302 之后的目录/正文相对链接由此解析到
/// 重定向后的域名。
String resolveWithRedirect(String url, String baseUrl, String? redirectUrl) {
  final base =
      (redirectUrl != null && redirectUrl.isNotEmpty) ? redirectUrl : baseUrl;
  return resolveUrlBase(url, base);
}

// ==================== 请求方法 ====================

const Set<String> kSupportedMethods = <String>{
  'GET',
  'POST',
  'PUT',
  'DELETE',
  'HEAD',
  'PATCH',
  'OPTIONS',
};

/// 规范化请求方法：未知/空值回退 GET，支持 HEAD 分支。
String normalizeMethod(String raw) {
  final m = raw.trim().toUpperCase();
  return kSupportedMethods.contains(m) ? m : 'GET';
}

/// 无请求体的方法（GET/HEAD/DELETE 等）。
bool isBodylessMethod(String method) =>
    method == 'GET' ||
    method == 'HEAD' ||
    method == 'DELETE' ||
    method == 'OPTIONS';

// ==================== 选项读取（大小写兼容） ====================

/// 大小写不敏感读取选项值。
///
/// URL 选项里 `{{webView=true}}` 会被解析为小写键 `webview`，而
/// `,{"webView":true}` JSON 选项保留驼峰键；两类写法都要取到。
dynamic optCI(Map<String, dynamic> opts, String key) {
  if (opts.containsKey(key)) return opts[key];
  final lower = key.toLowerCase();
  for (final e in opts.entries) {
    if (e.key.toLowerCase() == lower) return e.value;
  }
  return null;
}

/// 布尔选项：true / 1 / yes 视为真，其余为假。
bool optFlag(Map<String, dynamic> opts, String key) {
  final v = optCI(opts, key);
  if (v == null) return false;
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = v.toString().toLowerCase();
  return s == 'true' || s == '1' || s == 'yes';
}

/// 字符串选项（不存在返回 null）。
String? optString(Map<String, dynamic> opts, String key) {
  final v = optCI(opts, key);
  return v?.toString();
}

// ==================== 参数编码 ====================

/// JS escape 保留集：`A-Za-z0-9@*_+-./` 不编码。
bool _escapeSafe(int code) {
  if (code >= 0x41 && code <= 0x5A) return true;
  if (code >= 0x61 && code <= 0x7A) return true;
  if (code >= 0x30 && code <= 0x39) return true;
  return '@*_+-./'.codeUnits.contains(code);
}

bool _isHex(int code) =>
    (code >= 0x30 && code <= 0x39) ||
    (code >= 0x41 && code <= 0x46) ||
    (code >= 0x61 && code <= 0x66);

String _hex2(int v) => v.toRadixString(16).toUpperCase().padLeft(2, '0');
String _hex4(int v) => v.toRadixString(16).toUpperCase().padLeft(4, '0');

/// JS escape 编码：ASCII 非保留字符转 `%XX`，BMP 字符转 `%uXXXX`，
/// 增补平面字符按 UTF-16 代理对转两个 `%uXXXX`。
String escapeParam(String input) {
  final sb = StringBuffer();
  for (final rune in input.runes) {
    if (rune < 0x80) {
      if (_escapeSafe(rune)) {
        sb.writeCharCode(rune);
      } else {
        sb.write('%${_hex2(rune)}');
      }
    } else if (rune <= 0xFFFF) {
      sb.write('%u${_hex4(rune)}');
    } else {
      final v = rune - 0x10000;
      final hi = 0xD800 + (v >> 10);
      final lo = 0xDC00 + (v & 0x3FF);
      sb.write('%u${_hex4(hi)}%u${_hex4(lo)}');
    }
  }
  return sb.toString();
}

/// 判定一个值是否已完成百分号编码（避免重复编码）。
///
/// 接受：ASCII 字母数字、`*-._+`、合法 `%XX`、`%uXXXX`。出现中文、
/// 空格或其它未编码符号时返回 false。
bool isPercentEncoded(String s) {
  var i = 0;
  while (i < s.length) {
    final c = s.codeUnitAt(i);
    if ((c >= 0x41 && c <= 0x5A) ||
        (c >= 0x61 && c <= 0x7A) ||
        (c >= 0x30 && c <= 0x39) ||
        '*-._+'.codeUnits.contains(c)) {
      i++;
      continue;
    }
    if (c == 0x25) {
      // %uXXXX
      if (i + 5 < s.length &&
          (s.codeUnitAt(i + 1) == 0x75 || s.codeUnitAt(i + 1) == 0x55) &&
          _isHex(s.codeUnitAt(i + 2)) &&
          _isHex(s.codeUnitAt(i + 3)) &&
          _isHex(s.codeUnitAt(i + 4)) &&
          _isHex(s.codeUnitAt(i + 5))) {
        i += 6;
        continue;
      }
      // %XX
      if (i + 2 < s.length &&
          _isHex(s.codeUnitAt(i + 1)) &&
          _isHex(s.codeUnitAt(i + 2))) {
        i += 3;
        continue;
      }
      return false;
    }
    return false;
  }
  return true;
}

/// 可注入的字符集编码器（GBK/GB18030 等 SDK 未内置编码由外部提供编码表）。
/// 未注入时按 SDK 已注册编码处理，未知字符集回退 UTF-8。
typedef CharsetBytesEncoder = List<int> Function(String value, String charset);
CharsetBytesEncoder? charsetBytesEncoder;

List<int> _bytesFor(String value, String charset) {
  final injected = charsetBytesEncoder;
  if (injected != null) {
    try {
      return injected(value, charset);
    } catch (_) {}
  }
  final enc = Encoding.getByName(charset);
  if (enc != null) {
    try {
      return enc.encode(value);
    } catch (_) {}
  }
  return utf8.encode(value);
}

String _percentEncodeBytes(List<int> bytes) =>
    bytes.map((b) => '%${_hex2(b & 0xFF)}').join();

String _encodeValue(String value, String? charset) {
  if (value.isEmpty) return value;
  if (isPercentEncoded(value)) return value; // 已编码不重复
  final cs = (charset ?? '').trim();
  if (cs.toLowerCase() == 'escape') return escapeParam(value);
  return _percentEncodeBytes(_bytesFor(value, cs.isEmpty ? 'utf-8' : cs));
}

/// 对 `k=v&k2=v2` 形式的 GET 查询 / POST 表单按 [charset] 编码值部分。
///
/// - `charset=escape` 走 JS escape 语义；
/// - 其它字符集按字节逐字节百分号编码（已编码的 `%XX`/`%uXXXX` 不重复）；
/// - 键保持原样，值按 `&` 切分后逐个处理。
String encodeParams(String raw, String? charset) {
  if (raw.isEmpty) return raw;
  return raw.split('&').map((pair) {
    final eq = pair.indexOf('=');
    if (eq < 0) return _encodeValue(pair, charset);
    return '${pair.substring(0, eq)}=${_encodeValue(pair.substring(eq + 1), charset)}';
  }).join('&');
}

// ==================== 请求头清洗 ====================

/// 请求头处理计划。
class HeaderPlan {
  /// 可直接发送的静态头（已剔除动态脚本头、proxy、null UA）。
  final Map<String, dynamic> headers;

  /// 需要异步求值的动态脚本头（`<js>…</js>` / `@js:`），值为脚本文本。
  final List<MapEntry<String, String>> jsHeaders;

  /// 剥离出的代理地址（供代理层消费）。
  final String? proxy;

  /// 是否发生 `User-Agent: null` 删除。
  final bool nullUaRemoved;

  final List<String> notes;

  const HeaderPlan({
    required this.headers,
    required this.jsHeaders,
    required this.proxy,
    required this.nullUaRemoved,
    required this.notes,
  });
}

/// 从请求头值里提取动态脚本：`<js>…</js>` 或 `@js:…`，否则返回 null。
String? headerScriptOf(String value) {
  final t = value.trim();
  final m =
      RegExp(r'^<js>([\s\S]*?)</js>$', caseSensitive: false).firstMatch(t);
  if (m != null) return m.group(1);
  if (t.toLowerCase().startsWith('@js:')) return t.substring(4);
  return null;
}

/// 清洗请求头：
/// - `<js>…</js>` / `@js:` 头抽到 [HeaderPlan.jsHeaders] 待求值；
/// - `proxy` 头剥离到 [HeaderPlan.proxy]；
/// - `User-Agent: null`（字符串 null）删除默认 UA；
/// - 叠加 ua/cookie/referer 覆盖项（覆盖后再判定 null UA）。
HeaderPlan planHeaders(
  Map<String, dynamic> raw, {
  String? ua,
  String? cookie,
  String? referer,
}) {
  final headers = <String, dynamic>{};
  final jsHeaders = <MapEntry<String, String>>[];
  final notes = <String>[];
  String? proxy;

  raw.forEach((k, v) {
    final name = k.toString();
    final val = v?.toString() ?? '';
    if (name.toLowerCase() == 'proxy') {
      proxy = val;
      notes.add('proxy 头已识别，交代理层处理');
      return;
    }
    final script = headerScriptOf(val);
    if (script != null) {
      jsHeaders.add(MapEntry(name, script));
      return;
    }
    headers[name] = v;
  });

  if (ua != null && ua.isNotEmpty) headers['User-Agent'] = ua;
  if (cookie != null && cookie.isNotEmpty) headers['Cookie'] = cookie;
  if (referer != null && referer.isNotEmpty) headers['Referer'] = referer;

  var nullUaRemoved = false;
  final uaVal = headers['User-Agent']?.toString();
  if (uaVal != null && uaVal.toLowerCase() == 'null') {
    headers.remove('User-Agent');
    nullUaRemoved = true;
    notes.add('User-Agent 为 null，删除默认 UA');
  }

  return HeaderPlan(
    headers: headers,
    jsHeaders: jsHeaders,
    proxy: proxy,
    nullUaRemoved: nullUaRemoved,
    notes: notes,
  );
}

// ==================== type 与 Content-Type 分离 ====================

/// `type` 选项只用于响应体 hex 化，不参与 Content-Type 推断。
String? responseHexType(Map<String, dynamic> opts) {
  final t = optString(opts, 'type');
  return (t != null && t.isNotEmpty) ? t : null;
}

/// 请求 Content-Type：显式请求头 > `contentType` 选项 > null。
/// 与 [responseHexType] 完全分离，避免 `type` 被误当成请求媒体类型。
String? requestContentType(
    Map<String, dynamic> opts, Map<String, dynamic> headers) {
  for (final e in headers.entries) {
    if (e.key.toLowerCase() == 'content-type') {
      final v = e.value?.toString() ?? '';
      if (v.isNotEmpty) return v;
    }
  }
  final ct = optString(opts, 'contentType') ?? optString(opts, 'content-type');
  if (ct != null && ct.isNotEmpty) return ct;
  return null;
}

// ==================== 发现分类 ====================

/// 单个发现分类的完整字段集合（文本分支与 JSON 分支统一结构）。
Map<String, String> exploreKindFullMap(String title, String url,
    {Map<String, dynamic>? extras}) {
  final chars = extras?['chars'];
  final charsStr = chars is List
      ? chars.map((e) => e?.toString() ?? '').join(',')
      : (chars?.toString() ?? '');
  final style = extras?['style'];
  return <String, String>{
    'title': title,
    'url': url,
    'type': (extras?['type'] ?? 'url').toString(),
    'action': (extras?['action'] ?? '').toString(),
    'chars': charsStr,
    'default': (extras?['default'] ?? '').toString(),
    'viewName': (extras?['viewName'] ?? '').toString(),
    'style': style == null ? '' : jsonEncode(style),
  };
}

/// 解析发现分类，返回全字段 Map 列表。
///
/// - JSON 数组：保留 type/action/chars/default/viewName/style；
/// - 旧文本格式（`标题::地址`，`&&&`/换行分隔）：补齐全部默认字段。
List<Map<String, String>> parseExploreKindsFull(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return const <Map<String, String>>[];
  if (t.startsWith('[')) {
    try {
      final arr = jsonDecode(t);
      if (arr is List) {
        final out = <Map<String, String>>[];
        for (final e in arr) {
          if (e is Map) {
            final m = Map<String, dynamic>.from(e);
            final url = (m['url'] ?? m['link'] ?? '').toString();
            if (url.isEmpty && (m['title'] ?? '').toString().isEmpty) continue;
            out.add(exploreKindFullMap(
              (m['title'] ?? m['name'] ?? url).toString(),
              url,
              extras: m,
            ));
          }
        }
        if (out.isNotEmpty) return out;
      }
    } catch (_) {}
  }
  final out = <Map<String, String>>[];
  for (final line in t.split('\n')) {
    final l = line.trim();
    if (l.isEmpty) continue;
    for (final opt in l.split('&&&')) {
      final o = opt.trim();
      if (o.isEmpty) continue;
      final sep3 = o.indexOf(':::');
      if (sep3 >= 0) {
        out.add(exploreKindFullMap(
            o.substring(0, sep3).trim(), o.substring(sep3 + 3).trim()));
        continue;
      }
      final sep2 = o.indexOf('::');
      if (sep2 >= 0) {
        out.add(exploreKindFullMap(
            o.substring(0, sep2).trim(), o.substring(sep2 + 2).trim()));
        continue;
      }
      out.add(exploreKindFullMap(o, o));
    }
  }
  return out;
}

/// 发现分类缓存键：含 [exploreUrl] 内容哈希，分类配置变更自动失效。
String exploreKindsCacheKey(String sourceUrl, String exploreUrl) {
  return 'exploreKinds_${sourceUrl}_${contentHash(exploreUrl)}';
}

/// 稳定的 32 位内容哈希（FNV-1a 变体，基于 UTF-16 码元）。
int contentHash(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}

// ==================== 去重与分页上限 ====================

/// 目录翻页默认上限（防 nextTocUrl 死循环）。
const int kDefaultTocPageLimit = 100;

/// 正文分页默认上限。
const int kDefaultContentPageLimit = 100;

/// 搜索结果按 bookUrl 去重（可配置开关）。
List<Map<String, String>> dedupSearchBooks(List<Map<String, String>> books,
    {bool enabled = true}) {
  if (!enabled) return books;
  final seen = <String>{};
  final out = <Map<String, String>>[];
  for (final b in books) {
    final u = b['bookUrl'] ?? '';
    if (u.isEmpty) {
      out.add(b);
      continue;
    }
    if (seen.add(u)) out.add(b);
  }
  return out;
}

/// 通用按 URL 去重（目录章节等）。
List<T> dedupByUrl<T>(List<T> items, String Function(T) urlOf,
    {bool skipEmpty = true}) {
  final seen = <String>{};
  final out = <T>[];
  for (final it in items) {
    final u = urlOf(it);
    if (skipEmpty && u.isEmpty) {
      out.add(it);
      continue;
    }
    if (seen.add(u)) out.add(it);
  }
  return out;
}

/// 把分页上限约束到 [max]（默认 100），非法/未配置回退 [fallback]。
int clampPageLimit(int? requested, {int max = 100, int? fallback}) {
  final f = fallback ?? max;
  if (requested == null || requested <= 0) return f;
  return requested > max ? max : requested;
}

/// 正文分页重复内容检测：分块已出现在累计正文中则视为重复。
bool isDuplicateContent(String accumulated, String part) {
  final p = part.trim();
  if (p.isEmpty) return true;
  return accumulated.contains(p);
}

// ==================== 正文呈现选项 ====================

class ContentPresentation {
  /// 是否保留 <img>（图片/漫画正文）。
  final bool keepImage;

  /// 归一化后的 imageStyle：full / center / default / 尺寸串。
  final String imageStyle;

  /// 附加到图片的样式（居中/默认尺寸/自定义尺寸）。
  final String? imageCss;

  const ContentPresentation({
    required this.keepImage,
    required this.imageStyle,
    this.imageCss,
  });
}

bool _isSizeStyle(String s) =>
    RegExp(r'^\d+(%|px)?(x\d+(%|px)?)?$', caseSensitive: false).hasMatch(s);

/// 解析 imageStyle：除 `full` 外支持 `center`（居中）、`default`（自适应）、
/// 以及 `宽x高`/百分比等尺寸语义；这些取值都会保留图片并附加样式。
ContentPresentation parseImageStyle(String? imageStyle,
    {bool imageContentFlag = false}) {
  final s = (imageStyle ?? '').trim().toLowerCase();
  final disabled = s == 'none' || s == 'false' || s == '0';
  final keep = imageContentFlag || (!disabled && s.isNotEmpty);
  String? css;
  if (s == 'center') {
    css = 'display:block;margin:0 auto;';
  } else if (s == 'default') {
    css = 'max-width:100%;height:auto;';
  } else if (_isSizeStyle(s)) {
    final x = s.indexOf('x');
    if (x > 0) {
      css =
          'width:${_unit(s.substring(0, x))};height:${_unit(s.substring(x + 1))};';
    } else {
      css = 'width:${_unit(s)};';
    }
  }
  return ContentPresentation(
    keepImage: keep,
    imageStyle: s.isEmpty ? 'default' : s,
    imageCss: css,
  );
}

String _unit(String v) => RegExp(r'^\d+$').hasMatch(v) ? '${v}px' : v;

/// payAction 是否含需要求值的 JS（`{{js}}` / `<js>` / `@js:`）。
bool payActionNeedsJs(String payAction) {
  final s = payAction.toLowerCase();
  return s.contains('{{js') || s.contains('<js>') || s.contains('@js:');
}

/// 提取 payAction 中的 JS 片段：`{{js=脚本}}` / `<js>…</js>` / `@js:…`。
String? payActionScript(String payAction) {
  final t = payAction.trim();
  final mustache =
      RegExp(r'\{\{js=?([\s\S]*?)\}\}', caseSensitive: false).firstMatch(t);
  if (mustache != null) {
    final inner = mustache.group(1)!.trim();
    return inner.isEmpty ? null : inner;
  }
  final tag =
      RegExp(r'<js>([\s\S]*?)</js>', caseSensitive: false).firstMatch(t);
  if (tag != null) return tag.group(1)!.trim();
  if (t.toLowerCase().startsWith('@js:')) return t.substring(4).trim();
  return null;
}

/// 组合购买提示：静态 payAction 文本去掉 JS 占位后，拼接 JS 求值结果。
String buildPurchaseHint(String payAction, String? jsResult) {
  final staticText = payAction
      .replaceAll(RegExp(r'\{\{js=?([\s\S]*?)\}\}', caseSensitive: false), '')
      .replaceAll(RegExp(r'<js>[\s\S]*?</js>', caseSensitive: false), '')
      .trim();
  final parts = <String>[
    if (staticText.isNotEmpty) staticText,
    if (jsResult != null && jsResult.trim().isNotEmpty) jsResult.trim(),
  ];
  return parts.isEmpty ? '本章需要购买后阅读' : parts.join('\n');
}

// ==================== 横切登录检测 ====================

/// loginCheckJs 结果/响应体中表示「需要重新登录」的标记。
const String kReloginMarker = '__NEED_RELOGIN__';

/// 判定是否需要重新登录：
/// - JS 结果含标记、或为 false/0/未登录/needLogin；
/// - 响应体含显式标记。
bool loginCheckNeedsRelogin(String? jsResult, {String body = ''}) {
  if (jsResult != null) {
    final s = jsResult.trim();
    final low = s.toLowerCase();
    if (s.contains(kReloginMarker) ||
        low == 'false' ||
        s == '0' ||
        s == '未登录' ||
        low == 'needlogin') {
      return true;
    }
  }
  return body.contains(kReloginMarker);
}

class LoginCheckOutcome {
  /// 是否触发重新登录信号。
  final bool needRelogin;

  /// 是否配置了并执行了 loginCheckJs。
  final bool evaluated;

  /// JS 求值结果（失败时为空）。
  final String? detail;

  const LoginCheckOutcome({
    required this.needRelogin,
    required this.evaluated,
    this.detail,
  });
}

/// 纯判定入口：把脚本存在性、响应体、JS 结果组合为登录检测结论。
LoginCheckOutcome evaluateLoginCheckPure(
    String? script, String body, String? jsResult) {
  return LoginCheckOutcome(
    needRelogin: loginCheckNeedsRelogin(jsResult, body: body),
    evaluated: (script ?? '').trim().isNotEmpty,
    detail: jsResult,
  );
}

// ==================== JS 注入变量 ====================

String _jsLiteral(Object? v) {
  if (v is bool || v is num) return v.toString();
  final s = jsonEncode(v.toString());
  // 防止脚本里的 `</...` 提前闭合宿主脚本标签
  return s.replaceAll('<', r'\u003C');
}

/// 生成一段 JS 前缀，把额外变量绑定到 globalThis。
///
/// 书源脚本可直接读到 src/title/nextChapterUrl/fromBookInfo/speakText/
/// speakSpeed/content。只声明非 null 的变量，空输入返回空串（不改动原脚本
/// 的「最后一个表达式」求值语义）。
String buildJsVarPrelude({
  String? src,
  String? title,
  String? nextChapterUrl,
  bool? fromBookInfo,
  String? speakText,
  num? speakSpeed,
  String? content,
}) {
  final sb = StringBuffer();
  void put(String name, Object? v) {
    if (v == null) return;
    sb.write('globalThis.$name = ${_jsLiteral(v)};');
  }

  put('src', src);
  put('title', title);
  put('nextChapterUrl', nextChapterUrl);
  put('fromBookInfo', fromBookInfo);
  put('speakText', speakText);
  put('speakSpeed', speakSpeed);
  put('content', content);
  return sb.toString();
}

/// 重新登录/重取详情能力的 JS 前缀标记。
const String kReGetBookMarker = '__LEGADO_REGET_BOOK__';
const String kRefreshTocUrlMarker = '__LEGADO_REFRESH_TOC_URL__';

/// preUpdateJs 场景注入的等价能力：定义 reGetBook()/refreshTocUrl()，
/// 调用后返回约定标记，由 Dart 侧重取详情并回写变量表。
String buildPreUpdateJsPrelude() =>
    'globalThis.reGetBook = function(){ return ${_jsLiteral(kReGetBookMarker)}; };'
    'globalThis.refreshTocUrl = function(){ return ${_jsLiteral(kRefreshTocUrlMarker)}; };';

/// preUpdateJs 结果是否请求重取详情。
bool preUpdateRequestsReGetBook(String? result) =>
    result != null && result.contains(kReGetBookMarker);
