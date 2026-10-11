import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as iw;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:legado_md3/common/app_navigator.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/rss_source.dart';
import 'package:legado_md3/help/http/cookie_manager.dart';
import 'package:legado_md3/ui/browser/browser_screen.dart';
import 'legado_bridge_js.dart';
import 'aes_js_lib.dart';
import '../js_mini_eval.dart';

import 'js_source.dart';
export 'js_source.dart';

/// 一次 JS 求值的入参。
class JsEvalRequest {
  JsEvalRequest({
    required this.source,
    required this.script,
    this.result,
    this.key,
    this.page,
    this.baseUrl,
    this.book,
    this.chapter,
    this.rssArticle,
    this.isUrlRule = false,
  });

  final JsSource source;
  final String script; // 纯 JS（不含 <js></js>）
  final dynamic result; // String（响应正文）或 Map/List（JSON 节点）
  final String? key;
  final int? page;
  final String? baseUrl;
  final Map<String, dynamic>? book;
  final Map<String, dynamic>? chapter;
  final Map<String, dynamic>? rssArticle; // RSS 当前文章（rssArticle）
  final bool isUrlRule;
}

/// 一次 JS 求值的结果。
class JsEvalResult {
  JsEvalResult({
    this.value,
    this.variable,
    this.loginInfo,
    this.cookies = const {},
    this.kv = const {},
    this.logs = const [],
    this.toasts = const [],
    this.error,
  });

  /// 脚本完成值（对象/数组转 Map/List，其余为 String/num/bool）
  final dynamic value;
  final String? variable;
  final String? loginInfo;
  final Map<String, dynamic> cookies;
  final Map<String, dynamic> kv;
  final List<String> logs;
  final List<String> toasts;
  final String? error;

  String? get stringValue {
    final v = value;
    if (v == null) return null;
    if (v is String) return v;
    return jsonEncode(v);
  }
}

/// JS 运行时抽象（WebView 真引擎 / 迷你回退共用接口）。
abstract class LegadoJs {
  Future<void> loadSource(JsSource source);
  Future<JsEvalResult> eval(JsEvalRequest req);
  Future<void> dispose();
}

/// 判断规则是否包含需要 JS 引擎的写法。
bool ruleNeedsRealJs(String? rule) {
  if (rule == null || rule.isEmpty) return false;
  return rule.contains('<js>') ||
      rule.contains('@js:') ||
      rule.contains('{{');
}

/// 运行时管理器：每个书源一个无头 WebView（LRU 上限 4）。
class JsRuntimeManager {
  JsRuntimeManager._();
  static final JsRuntimeManager instance = JsRuntimeManager._();

  /// 测试可注入假运行时。
  LegadoJs? Function(JsSource source)? factoryOverride;

  final Map<String, LegadoJs> _runtimes = {};
  final List<String> _order = [];
  static const int _max = 4;

  Future<LegadoJs> forSource(JsSource source) async {
    final key = source.jsUrl;
    final existing = _runtimes[key];
    if (existing != null) {
      _order.remove(key);
      _order.add(key);
      return existing;
    }
    LegadoJs rt;
    if (factoryOverride != null) {
      rt = factoryOverride!(source) ?? MiniLegadoJs();
    } else if (_webViewSupported) {
      rt = WebViewLegadoJs(source);
    } else {
      rt = MiniLegadoJs();
    }
    await rt.loadSource(source);
    _runtimes[key] = rt;
    _order.add(key);
    while (_order.length > _max) {
      final old = _order.removeAt(0);
      final r = _runtimes.remove(old);
      try {
        await r?.dispose();
      } catch (_) {}
    }
    return rt;
  }

  bool get _webViewSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  Future<void> invalidate(String sourceUrl) async {
    final rt = _runtimes.remove(sourceUrl);
    _order.remove(sourceUrl);
    try {
      await rt?.dispose();
    } catch (_) {}
  }

  Future<void> disposeAll() async {
    for (final rt in _runtimes.values) {
      try {
        await rt.dispose();
      } catch (_) {}
    }
    _runtimes.clear();
    _order.clear();
  }
}

/// 迷你回退运行时（桌面/测试/不支持平台）。
class MiniLegadoJs implements LegadoJs {
  @override
  Future<void> loadSource(JsSource source) async {}

  @override
  Future<JsEvalResult> eval(JsEvalRequest req) async {
    final r = req.result;
    final out = JsMiniEvaluator.eval(
      req.script,
      result: r is String ? r : (r == null ? null : jsonEncode(r)),
      key: req.key,
      page: req.page,
      baseUrl: req.baseUrl,
    );
    return JsEvalResult(value: out, variable: req.source.variable);
  }

  @override
  Future<void> dispose() async {}
}

/// 无头 WebView 真 JS 运行时。
class WebViewLegadoJs implements LegadoJs {
  WebViewLegadoJs(this.source);

  JsSource source;
  iw.HeadlessInAppWebView? _headless;
  iw.InAppWebViewController? _controller;
  final Completer<void> _ready = Completer<void>();
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 40),
    followRedirects: true,
    validateStatus: (s) => s != null && s < 600,
    responseType: ResponseType.bytes,
  ));
  final DatabaseService _db = DatabaseService();

  String? _loadedSourceUrl;
  String? _deviceId;

  bool get _persistCookie => source.enabledCookieJar;

  Future<void> _ensure() async {
    if (_headless != null) {
      await _ready.future;
      return;
    }
    final settings = iw.InAppWebViewSettings(
      javaScriptEnabled: true,
      domStorageEnabled: true,
      databaseEnabled: true,
      allowFileAccess: true,
      useShouldInterceptRequest: true,
      javaScriptCanOpenWindowsAutomatically: true,
      mixedContentMode: iw.MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
      userAgent:
          'Mozilla/5.0 (Linux; Android 13; Pixel 6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
    );
    _headless = iw.HeadlessInAppWebView(
      initialSettings: settings,
      initialUrlRequest: iw.URLRequest(url: iw.WebUri('about:blank')),
      onWebViewCreated: (controller) {
        _controller = controller;
        controller.addJavaScriptHandler(
            handlerName: 'legadoBrowser', callback: _onBrowserRequest);
      },
      onLoadStop: (controller, url) async {
        try {
          await controller.evaluateJavascript(source: AesJsLib.code);
          await controller.evaluateJavascript(source: LegadoBridgeJs.code);
          if (!_ready.isCompleted) _ready.complete();
        } catch (e) {
          if (!_ready.isCompleted) _ready.completeError(e);
        }
      },
      shouldInterceptRequest: (controller, request) => _intercept(request),
    );
    await _headless!.run();
    await _ready.future;
  }

  @override
  Future<void> loadSource(JsSource src) async {
    source = src;
    await _ensure();
    if (_loadedSourceUrl == src.jsUrl) return;
    final c = _controller!;
    final seed = '''
      __state.meta = {url: ${_js(src.jsUrl)}, name: ${_js(src.jsName)}, httpUrl: ${_js(src.jsHttpUrl)}};
      __state.variable = ${_js(src.variable ?? '')};
      __state.variableComment = ${_js(src.variableComment ?? '')};
      __state.lastUpdateTime = ${src.lastUpdateTime ?? 0};
      globalThis.result = {}; globalThis.key = ''; globalThis.page = 1; globalThis.baseUrl = '';
      globalThis.book = {}; globalThis.chapter = {}; globalThis.rssArticle = {}; globalThis.\$ = globalThis.result;
    ''';
    await c.evaluateJavascript(source: seed);
    final lib = (src.jsLib ?? '').trim();
    if (lib.isNotEmpty) {
      try {
        await c.evaluateJavascript(source: lib);
      } catch (e) {
        debugPrint('jsLib 求值失败: $e');
      }
    }
    final login = (src.loginUrl ?? '').trim();
    if (login.isNotEmpty) {
      try {
        await c.evaluateJavascript(source: login);
      } catch (e) {
        debugPrint('loginUrl 初始化失败: $e');
      }
    }
    _loadedSourceUrl = src.jsUrl;
  }

  /// JS→原生：网页登录请求（startBrowserAwait 等）。
  Future<dynamic> _onBrowserRequest(List<dynamic> args) async {
    try {
      final m = jsonDecode(args.first.toString()) as Map<String, dynamic>;
      final id = m['id']?.toString() ?? '';
      final url = m['url']?.toString() ?? '';
      final title = m['title']?.toString() ?? '登录';
      final nav = appNavigatorKey.currentState;
      String cookieStr = '';
      final finalUrl = url;
      if (nav != null && url.isNotEmpty) {
        await nav.push(MaterialPageRoute(
            builder: (_) => BrowserScreen(url: url, title: title)));
        try {
          final cookies =
              await iw.CookieManager.instance().getCookies(url: iw.WebUri(url));
          cookieStr = cookies
              .where((ck) => ck.name.isNotEmpty && ck.value != null)
              .map((ck) => '${ck.name}=${ck.value}')
              .join('; ');
          if (cookieStr.isNotEmpty) {
            CookieManager().saveFromResponse(url, [cookieStr]);
            final host = Uri.tryParse(url)?.host ?? '';
            if (_persistCookie && host.isNotEmpty) {
              await _db.saveCookie(host, cookieStr);
            }
          }
        } catch (_) {}
      }
      await _controller?.evaluateJavascript(
          source: '__resolveBrowser(${_js(id)}, ${_js(cookieStr)}, ${_js(finalUrl)});');
    } catch (_) {}
    return null;
  }

  /// 原生接管书源 JS 发起的所有 XHR（绕过 CORS、统一 Cookie/编码）。
  Future<iw.WebResourceResponse?> _intercept(iw.WebResourceRequest request) async {
    final uri = request.url;
    final url = uri.toString();
    if (!url.startsWith('http')) return null;
    final method = (request.method ?? 'GET').toUpperCase();

    if (method == 'OPTIONS') {
      return iw.WebResourceResponse(
        statusCode: 200,
        reasonPhrase: 'OK',
        contentType: 'text/plain',
        contentEncoding: 'utf-8',
        data: Uint8List(0),
        headers: _corsHeaders(),
      );
    }

    final headers = <String, String>{};
    (request.headers ?? <String, String>{}).forEach((k, v) {
      headers[k] = v;
    });

    // POST body 通过自定义请求头携带（WebResourceRequest 不暴露 body）
    Uint8List? bodyBytes;
    final b64body = headers.remove('X-Legado-Body');
    if (b64body != null && b64body.isNotEmpty) {
      try {
        bodyBytes = base64Decode(b64body);
      } catch (_) {}
    }

    final hasCookie =
        headers.keys.any((k) => k.toLowerCase() == 'cookie');
    if (!hasCookie) {
      final ck = CookieManager().cookieHeader(url);
      if (ck != null && ck.isNotEmpty) headers['Cookie'] = ck;
    }

    try {
      final resp = await _dio.request<List<int>>(
        url,
        data: bodyBytes,
        options: Options(
          method: method,
          headers: headers,
          responseType: ResponseType.bytes,
        ),
      );
      final setCookies = resp.headers.map['set-cookie'] ?? const <String>[];
      CookieManager().saveFromResponse(url, setCookies);
      if (_persistCookie) {
        final ck = CookieManager().cookieHeader(url);
        if (ck != null && ck.isNotEmpty) {
          await _db.saveCookie(uri.host, ck);
        }
      }
      final outHeaders = _corsHeaders();
      var contentType = 'text/plain; charset=utf-8';
      resp.headers.map.forEach((k, vals) {
        if (k.toLowerCase() == 'content-type') contentType = vals.join(';');
      });
      if (setCookies.isNotEmpty) {
        outHeaders['X-Set-Cookie'] = setCookies.join('\n');
      }
      outHeaders['Content-Type'] = contentType;
      return iw.WebResourceResponse(
        statusCode: resp.statusCode ?? 200,
        reasonPhrase: _reason(resp.statusCode ?? 200),
        contentType: contentType,
        contentEncoding: 'utf-8',
        data: Uint8List.fromList(resp.data ?? const <int>[]),
        headers: outHeaders,
      );
    } catch (e) {
      return iw.WebResourceResponse(
        statusCode: 502,
        reasonPhrase: 'Bad Gateway',
        contentType: 'text/plain; charset=utf-8',
        contentEncoding: 'utf-8',
        data: Uint8List.fromList(utf8.encode('请求失败: $e')),
        headers: _corsHeaders(),
      );
    }
  }

  Map<String, String> _corsHeaders() => const {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Credentials': 'true',
        'Access-Control-Allow-Headers': '*',
        'Access-Control-Expose-Headers': '*',
        'Access-Control-Allow-Methods':
            'GET,POST,PUT,DELETE,HEAD,OPTIONS,PATCH'
      };

  String _reason(int code) {
    if (code < 300) return 'OK';
    if (code < 400) return 'Found';
    if (code < 500) return 'Bad Request';
    return 'Server Error';
  }

  @override
  Future<JsEvalResult> eval(JsEvalRequest req) async {
    source = req.source;
    await _ensure();
    await loadSource(req.source);
    final c = _controller!;

    final prefs = await SharedPreferences.getInstance();
    _deviceId ??= prefs.getString('legado_device_id');
    if (_deviceId == null || _deviceId!.isEmpty) {
      _deviceId = _genDeviceId();
      await prefs.setString('legado_device_id', _deviceId!);
    }
    final srcUrl = req.source.jsUrl;
    final loginInfo = prefs.getString('loginInfo_$srcUrl') ?? '';
    final kvJson = prefs.getString('jsKv_$srcUrl') ?? '{}';
    final cookies = await _collectCookies(req);

    var script = req.script;
    if (req.isUrlRule) {
      script = _urlPlaceholders(script, req.key ?? '', req.page ?? 1);
    }
    final hasReturn = RegExp(r'(^|[\s;{}])return\s').hasMatch(script);

    final args = <String, dynamic>{
      'resultArg': req.result,
      'keyArg': req.key,
      'pageArg': req.page,
      'baseUrlArg': req.baseUrl ?? '',
      'bookArg': req.book ?? const <String, dynamic>{},
      'chapterArg': req.chapter ?? const <String, dynamic>{},
      'rssArticleArg': req.rssArticle ?? const <String, dynamic>{},
      'variableArg': req.source.variable ?? '',
      'loginInfoArg': loginInfo,
      'cookiesArg': cookies,
      'kvArg': _tryJson(kvJson) ?? <String, dynamic>{},
      'deviceIdArg': _deviceId!,
      'scriptArg': script,
    };

    final functionBody = '''
      __resetTransient();
      globalThis.result = resultArg;
      globalThis.\$ = resultArg;
      globalThis.key = keyArg;
      globalThis.page = pageArg;
      globalThis.baseUrl = baseUrlArg;
      globalThis.book = bookArg;
      globalThis.chapter = chapterArg;
      globalThis.rssArticle = rssArticleArg;
      __state.variable = variableArg || '';
      __state.loginInfo = loginInfoArg || '';
      __state.cookies = cookiesArg || {};
      __state.kv = kvArg || {};
      __state.deviceId = deviceIdArg;
      var __ret, __err = null;
      try {
        if ($hasReturn) {
          __ret = await (async function() {
            ${hasReturn ? script : ''}
          }).call(globalThis);
        } else {
          __ret = await (async function() {
            return eval(scriptArg);
          }).call(globalThis);
        }
      } catch (e) {
        __err = e;
      }
      if (__ret === undefined) { try { __ret = globalThis.result; } catch (e1) { __ret = null; } }
      return __envelope(__ret, __err);
    ''';

    iw.CallAsyncJavaScriptResult? res;
    try {
      res = await c.callAsyncJavaScript(
          functionBody: functionBody, arguments: args);
    } catch (e) {
      return JsEvalResult(error: 'JS 执行异常: $e', variable: req.source.variable);
    }
    if (res?.error != null && res?.value == null) {
      return JsEvalResult(
          error: res!.error.toString(), variable: req.source.variable);
    }
    Map<String, dynamic> env;
    try {
      env =
          jsonDecode(res?.value?.toString() ?? '{}') as Map<String, dynamic>;
    } catch (e) {
      return JsEvalResult(
          value: res?.value?.toString(), variable: req.source.variable);
    }

    final newVar = env['variable']?.toString();
    if (newVar != null && newVar.isNotEmpty && newVar != req.source.variable) {
      req.source.variable = newVar;
      try {
        // 书源 / 订阅源分别落各自的表
        if (req.source is RssSource) {
          await _db.updateRssSourceVariable(req.source.jsUrl, newVar);
        } else {
          await _db.updateSourceVariable(req.source.jsUrl, newVar);
        }
      } catch (_) {}
    }
    final newLogin = env['loginInfo']?.toString() ?? '';
    if (newLogin.isNotEmpty && newLogin != loginInfo) {
      await prefs.setString('loginInfo_$srcUrl', newLogin);
    }
    final kv = env['kv'];
    if (kv is Map && kv.isNotEmpty) {
      await prefs.setString('jsKv_$srcUrl', jsonEncode(kv));
    }
    await _persistBridgeCookies(env['cookies']);

    return JsEvalResult(
      value: env['ret'],
      variable: newVar ?? req.source.variable,
      loginInfo: newLogin.isEmpty ? null : newLogin,
      cookies: env['cookies'] is Map
          ? Map<String, dynamic>.from(env['cookies'] as Map)
          : const {},
      kv: env['kv'] is Map
          ? Map<String, dynamic>.from(env['kv'] as Map)
          : const {},
      logs: (env['logs'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      toasts: (env['toasts'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      error: env['error']?.toString(),
    );
  }

  Future<Map<String, dynamic>> _collectCookies(JsEvalRequest req) async {
    final out = <String, dynamic>{};
    final hosts = <String>{};
    for (final u in [req.baseUrl, req.source.jsUrl].whereType<String>()) {
      final h = Uri.tryParse(u)?.host;
      if (h != null && h.isNotEmpty) hosts.add(h);
    }
    for (final h in hosts) {
      final ck = CookieManager().cookieHeader('https://$h/');
      if (ck != null && ck.isNotEmpty) out[h] = ck;
      if (_persistCookie) {
        final saved = await _db.getCookie(h);
        if (saved != null && saved.isNotEmpty && !out.containsKey(h)) {
          out[h] = saved;
        }
      }
    }
    return out;
  }

  Future<void> _persistBridgeCookies(dynamic cookies) async {
    if (cookies is! Map) return;
    for (final entry in cookies.entries) {
      final h = entry.key.toString();
      final v = entry.value.toString();
      if (v.isEmpty) continue;
      final url = h.startsWith('http') ? h : 'https://$h/';
      CookieManager().saveFromResponse(url, [v]);
      if (_persistCookie) {
        try {
          await _db.saveCookie(h, v);
        } catch (_) {}
      }
      try {
        for (final pair in v.split(';')) {
          final idx = pair.indexOf('=');
          if (idx > 0) {
            await iw.CookieManager.instance().setCookie(
                  url: iw.WebUri(url),
                  name: pair.substring(0, idx).trim(),
                  value: pair.substring(idx + 1).trim(),
                );
          }
        }
      } catch (_) {}
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await _headless?.dispose();
    } catch (_) {}
    _headless = null;
    _controller = null;
  }

  static String _js(String? s) => jsonEncode(s ?? '');

  dynamic _tryJson(String s) {
    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  String _urlPlaceholders(String script, String key, int page) {
    var r = script.replaceAll('{{key}}', Uri.encodeComponent(key));
    r = r.replaceAll('{{searchKey}}', Uri.encodeComponent(key));
    r = r.replaceAll('{{page}}', page.toString());
    r = r.replaceAllMapped(RegExp(r'\{\{\(page-1\)\*(\d+)\}\}'),
        (m) => ((page - 1) * int.parse(m.group(1)!)).toString());
    return r;
  }

  String _genDeviceId() {
    const chars = '0123456789abcdef';
    final sb = StringBuffer();
    var seed = DateTime.now().microsecondsSinceEpoch;
    for (var i = 0; i < 16; i++) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      sb.write(chars[seed % 16]);
    }
    return sb.toString();
  }
}
