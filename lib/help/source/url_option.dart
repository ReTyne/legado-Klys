import 'dart:convert';

/// Legado 书源 URL 与请求选项解析（对齐原版 `AnalyzeUrl`）。
///
/// 书源的 URL 字段支持在同一行里附带请求选项，本项目此前只支持
/// `url,{json}` 与 `url,POST:body` 两种，导致大量使用 legado 标准
/// `{{key=value}}` 写法的书源（换域名、自定义 UA、指定编码、POST 表单等）
/// 解析失败。这里补全完整语法：
///
/// * `url,{"method":"POST","body":"x","charset":"gbk","headers":{...}}`
/// * `url,POST:body`
/// * `url,{{method=POST}},{{charset=gbk}},{{header.X-Token=abc}}`
/// * `url,{{host=backup.example.com}}` —— 多域名切换
/// * `url#注释` —— 注释剥除
///
/// 三类写法可任意组合。只有**已知选项名**才会被当成选项从 URL 中剥离，
/// 未知名（例如没替换完的 `{{key}}`/`{{page}}`）原样保留在 URL 里。
class UrlOptions {
  /// 解析后的干净 URL（不含选项与注释）
  final String url;

  /// 解析出的请求选项。常见 key：
  /// `method` / `body` / `headers` / `charset` / `type` / `retry` /
  /// `ua` / `cookie` / `referer` / `host` / `timeout` / `strict` / `webview`
  final Map<String, dynamic> options;

  const UrlOptions({required this.url, required this.options});

  String? str(String key) => options[key]?.toString();

  String get method => (str('method') ?? 'GET').toUpperCase();

  bool get isPost => method == 'POST' || method == 'PUT';

  /// 已知的 URL 选项名（legado AnalyzeUrl 支持）
  static const knownOptions = <String>{
    'method', 'headers', 'body', 'charset', 'type', 'retry', 'webview',
    'decode', 'cache', 'enforce', 'ua', 'cookie', 'referer', 'host',
    'js', 'java', 'bodyjs', 'callback', 'strict', 'concurrency',
    'timeout', 'override', 'needdecode', 'needparse', 'multithread',
    'webviewasset', 'weblock', 'webviewusejs', 'raw', 'noredirect',
  };

  static UrlOptions parse(String urlStr) {
    var url = urlStr.trim();
    final options = <String, dynamic>{};

    // `#` 注释：data: URI 本身可能含 #，不剥
    final hashIdx = url.indexOf('#');
    if (hashIdx > 0 && !url.startsWith('data:')) {
      url = url.substring(0, hashIdx).trim();
    }

    // 1) `url,{json}` —— 从 `,{` 开始做括号配平（body 里可能有逗号）
    // 注意：`,{{` 是 legado 的 `{{key=value}}` 选项语法而非 JSON，
    // 必须跳过本分支交给第 3 步处理，否则 JSON 解码失败会把选项吞掉。
    final commaJson = url.indexOf(',{');
    if (commaJson > 0) {
      final optStr = _balancedBrace(url, commaJson + 1);
      if (optStr != null && !optStr.startsWith('{{')) {
        // 只摘除 JSON 段本身，保留其后的 `{{key=value}}` 选项
        url = (url.substring(0, commaJson) +
                url.substring(commaJson + 1 + optStr.length))
            .trim();
        try {
          final o = jsonDecode(optStr);
          if (o is Map) options.addAll(o.map((k, v) => MapEntry(k.toString(), v)));
        } catch (_) {
          // json 非法时忽略选项，URL 仍照常请求
        }
      }
    }

    // 2) `url,POST:body`
    if (!options.containsKey('method')) {
      final m = RegExp(r'^(.+?),(POST|GET|PUT|DELETE)(?::(.*))?$', caseSensitive: false).firstMatch(url);
      if (m != null) {
        url = m.group(1)!.trim();
        options['method'] = m.group(2)!.toUpperCase();
        final b = m.group(3);
        if (b != null && b.isNotEmpty) options['body'] = b;
      }
    }

    // 3) `{{key=value}}` / `{{key}}` / `{{header.X=Y}}`
    final optReg = RegExp(r'\{\{([^{}]*)\}\}');
    var guard = 0;
    while (guard++ < 64) {
      final mm = optReg.firstMatch(url);
      if (mm == null) break;
      final expr = mm.group(1)!.trim();
      final eq = expr.indexOf('=');
      final key = (eq < 0 ? expr : expr.substring(0, eq)).trim().toLowerCase();
      // `header.X=Y` 前缀不在 knownOptions 表里，需放行
      if (!knownOptions.contains(key) && !key.startsWith('header.')) {
        break; // 不是选项：保留（可能是未替换的模板）
      }
      url = url.replaceRange(mm.start, mm.end, '').trim();
      if (expr.isEmpty) continue;
      if (eq < 0) {
        options[key] = true;
        continue;
      }
      var v = expr.substring(eq + 1).trim();
      if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) {
        v = v.substring(1, v.length - 1);
      }
      if (key.startsWith('header.')) {
        final hk = expr.substring(0, eq).trim().substring(7);
        final h = options['headers'] is Map
            ? Map<String, dynamic>.from(options['headers'] as Map)
            : <String, dynamic>{};
        h[hk] = v;
        options['headers'] = h;
        continue;
      }
      final lv = v.toLowerCase();
      if (lv == 'true') {
        options[key] = true;
      } else if (lv == 'false') {
        options[key] = false;
      } else {
        options[key] = v;
      }
    }

    while (url.endsWith(',')) url = url.substring(0, url.length - 1).trim();
    return UrlOptions(url: url, options: options);
  }

  /// 从 [start]（`{` 的位置）取一段配平的 `{...}` 子串；不配平返回 null。
  static String? _balancedBrace(String s, int start) {
    if (start >= s.length || s[start] != '{') return null;
    var depth = 0;
    var inStr = false;
    var quote = '';
    for (var i = start; i < s.length; i++) {
      final c = s[i];
      if (inStr) {
        if (c == quote && s[i - 1] != '\\') inStr = false;
        continue;
      }
      if (c == '"' || c == "'") {
        inStr = true;
        quote = c;
        continue;
      }
      if (c == '{') {
        depth++;
      } else if (c == '}') {
        depth--;
        if (depth == 0) return s.substring(start, i + 1);
      }
    }
    return null;
  }
}
