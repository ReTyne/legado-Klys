import 'dart:convert';

/// 一次书源发起的网络请求记录。
///
/// 覆盖两条彼此独立的通道：
/// * `engine` —— [BookSourceEngine] 自身的 `_fetch`（搜索/发现/详情等主请求）；
/// * `js-ajax` —— 书源 JS 里 `java.ajax` / `java.get` 发出的同步 XHR，由
///   WebViewLegadoJs 的 shouldInterceptRequest 原生拦截，**不经过引擎**。
///
/// 聚合类书源（大灰狼 / 书山等）的详情、目录、正文几乎全部走第二条通道。
/// 此前调试页只能看到 `data:` 书址被 hex 编码后的中间产物，看不到任何真实
/// 请求与响应，是这个日志要解决的核心问题。
class SourceNetworkEntry {
  const SourceNetworkEntry({
    required this.time,
    required this.url,
    required this.method,
    required this.origin,
    this.statusCode,
    this.durationMs = 0,
    this.responseBytes = 0,
    this.error,
    this.responsePreview,
    this.requestHeaders,
    this.responseHeaders,
    this.finalUrl,
    this.redirects = const <String>[],
  });

  final DateTime time;
  final String url;
  final String method;

  /// 'engine' / 'js-ajax' / 'data'
  final String origin;
  final int? statusCode;
  final int durationMs;
  final int responseBytes;
  final String? error;
  final String? responsePreview;

  /// 实际发出的请求头（含自动附加的 Cookie / User-Agent）。
  final Map<String, String>? requestHeaders;

  /// 服务端返回的响应头（含 Set-Cookie / Content-Type / Location 等）。
  final Map<String, String>? responseHeaders;

  /// 重定向后的最终落地地址；无重定向时等于 [url]。
  final String? finalUrl;

  /// 重定向链（含起始地址，末项为 [finalUrl]）。
  final List<String> redirects;

  bool get hasRedirect =>
      redirects.length > 1 ||
      (finalUrl != null && finalUrl!.isNotEmpty && finalUrl != url);

  bool get ok =>
      error == null &&
      statusCode != null &&
      statusCode! >= 200 &&
      statusCode! < 400;

  String get statusLabel {
    if (error != null) return '失败';
    final s = statusCode;
    return s == null ? '—' : s.toString();
  }

  String get clock =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}:'
      '${time.second.toString().padLeft(2, '0')}';

  String get shortUrl => url.length > 200 ? '${url.substring(0, 200)}…' : url;

  Map<String, dynamic> toJson() => {
        'time': time.toIso8601String(),
        'url': url,
        'method': method,
        'origin': origin,
        'statusCode': statusCode,
        'durationMs': durationMs,
        'responseBytes': responseBytes,
        'error': error,
        'responsePreview': responsePreview,
        if (requestHeaders != null) 'requestHeaders': requestHeaders,
        if (responseHeaders != null) 'responseHeaders': responseHeaders,
        if (finalUrl != null) 'finalUrl': finalUrl,
        if (redirects.isNotEmpty) 'redirects': redirects,
      };
}

/// 原始源码的可读化结果。
class RawResponseView {
  const RawResponseView(this.text, {this.note});

  final String text;

  /// 说明文字，例如「hex 中间产物，已解码」/「已格式化 JSON」。
  final String? note;
}

/// 书源网络请求环形日志（全局单例）。
///
/// 调试页、登录页、书源诊断面板共用；只保留最近 [_max] 条，响应预览最多
/// 4 KB，避免把整本正文塞进内存。
class SourceNetworkLog {
  SourceNetworkLog._();

  static final SourceNetworkLog instance = SourceNetworkLog._();
  static const int _max = 200;
  static const int _previewLimit = 4000;

  final List<SourceNetworkEntry> _entries = <SourceNetworkEntry>[];

  /// 书源 jsLib / loginUrl 初始化脚本的加载错误。这类错误此前只打到
  /// debugPrint，登录页点按钮报「xxx is not defined」时用户无从定位。
  final List<String> scriptErrors = <String>[];

  List<SourceNetworkEntry> get entries => List.unmodifiable(_entries);
  bool get isEmpty => _entries.isEmpty;
  SourceNetworkEntry? get last =>
      _entries.isEmpty ? null : _entries[_entries.length - 1];

  /// 最近一次失败记录（登录页据此给出「服务器不可用 / 建议切换」提示）。
  SourceNetworkEntry? get lastFailure {
    for (var i = _entries.length - 1; i >= 0; i--) {
      if (!_entries[i].ok) return _entries[i];
    }
    return null;
  }

  void clear() => _entries.clear();

  void addScriptError(String message) {
    scriptErrors.add(message);
    if (scriptErrors.length > 20) {
      scriptErrors.removeRange(0, scriptErrors.length - 20);
    }
  }

  void clearScriptErrors() => scriptErrors.clear();

  void add(SourceNetworkEntry entry) {
    _entries.add(entry);
    if (_entries.length > _max) {
      _entries.removeRange(0, _entries.length - _max);
    }
  }

  void record({
    required String url,
    required String method,
    required String origin,
    int? statusCode,
    int durationMs = 0,
    String? error,
    List<int>? body,
    String? text,
    Map<String, String>? requestHeaders,
    Map<String, String>? responseHeaders,
    String? finalUrl,
    List<String>? redirects,
  }) {
    String? preview;
    final bytes = body?.length ?? text?.length ?? 0;
    if (text != null && text.isNotEmpty) {
      preview = text.length > _previewLimit
          ? text.substring(0, _previewLimit)
          : text;
    } else if (body != null && body.isNotEmpty) {
      final slice = body.length > _previewLimit
          ? body.sublist(0, _previewLimit)
          : body;
      preview = utf8.decode(slice, allowMalformed: true);
    }
    add(SourceNetworkEntry(
      time: DateTime.now(),
      url: url,
      method: method,
      origin: origin,
      statusCode: statusCode,
      durationMs: durationMs,
      responseBytes: bytes,
      error: error,
      responsePreview: preview,
      requestHeaders: requestHeaders,
      responseHeaders: responseHeaders,
      finalUrl: finalUrl,
      redirects: redirects ?? const <String>[],
    ));
  }

  /// 把调试页拿到的「原始源码」整理成可读文本：
  /// * 纯 hex（legado `type` 选项 / `data:` 书址的产物）自动解码；
  /// * 合法 JSON 自动缩进美化；
  /// * 其余原样返回。
  static RawResponseView readable(String raw) {
    var text = raw;
    var notes = <String>[];
    final t = raw.trim();
    if (t.length >= 2 &&
        t.length.isEven &&
        RegExp(r'^[0-9a-fA-F]+$').hasMatch(t)) {
      try {
        final bytes = <int>[];
        for (var i = 0; i < t.length; i += 2) {
          bytes.add(int.parse(t.substring(i, i + 2), radix: 16));
        }
        final decoded = utf8.decode(bytes, allowMalformed: true);
        if (decoded.contains('\uFFFD') == false || decoded.isNotEmpty) {
          text = decoded;
          notes.add('hex 中间产物（已解码）');
        }
      } catch (_) {}
    }
    final trimmed = text.trim();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      try {
        final obj = jsonDecode(trimmed);
        text = const JsonEncoder.withIndent('  ').convert(obj);
        notes.add('JSON 已格式化');
      } catch (_) {}
    }
    return RawResponseView(text,
        note: notes.isEmpty ? null : notes.join(' · '));
  }
}
