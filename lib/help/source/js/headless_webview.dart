import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as iw;

/// 无头 WebView 抓取工具。
///
/// 用于书源 `webJs` 规则与 `{{webView=true}}` URL 选项：先尝试用无头
/// WebView 加载页面、执行 JS 渲染，取渲染后的结果；任何失败（超时/异常/
/// 设备不支持）都返回空串，由调用方降级为普通 HTTP 请求，绝不抛异常。
///
/// 设计约束：
/// * 串行队列：同时只允许 1 个 headless 实例，避免内存暴涨；
/// * 一次性熔断：创建/运行失败后置位 [_broken]，后续调用直接返回空串，
///   不再反复走超时；
/// * 单元测试环境（flutter_test）没有平台实现，平台调用抛
///   MissingPluginException，被 try/catch 兜住，不会真的创建 WebView；
/// * 用完必须 dispose（幂等，超时/失败/成功三条路径都会走到）。
class HeadlessWebViewFetcher {
  HeadlessWebViewFetcher._();

  /// 串行队列（mutex）：前一个抓取结束后才启动下一个。
  static Future<void> _queue = Future<void>.value();

  /// 熔断标志：创建/运行失败过一次后不再尝试。
  static bool _broken = false;

  /// 页面加载完成后、取值前的额外等待，给 JS 渲染留时间
  static const Duration _renderDelay = Duration(milliseconds: 800);

  static const String _defaultUserAgent =
      'Mozilla/5.0 (Linux; Android 13; Pixel 6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  /// 测试/调试用：重置熔断与队列状态。
  static void resetForTest() {
    _broken = false;
    _queue = Future<void>.value();
  }

  /// 用无头 WebView 加载 [url]，可选先执行 [injectJs]（DOM 就绪后、页面
  /// load 完成前注入运行，非空结果暂存到 `window.__legadoWebJsResult`），
  /// 加载完成后执行 [evalJs] 取结果（默认取
  /// `document.documentElement.outerHTML`），超时 [timeoutMs] 毫秒后返回
  /// 空串。任何失败都返回空串，绝不抛异常。
  static Future<String> fetch({
    required String url,
    String? injectJs,
    String? evalJs,
    int timeoutMs = 15000,
    Map<String, String>? headers,
    String? userAgent,
  }) {
    if (_broken || kIsWeb || url.trim().isEmpty) return Future.value('');
    final completer = Completer<String>();
    final previous = _queue;
    // 链式串行：前一个任务结束后才启动当前任务；任何一环出问题都不影响后续排队。
    _queue = previous
        .catchError((_) {})
        .then((_) => _guardedRun(
              url: url,
              injectJs: injectJs,
              evalJs: evalJs,
              timeoutMs: timeoutMs,
              headers: headers,
              userAgent: userAgent,
            ))
        .then((v) {
          if (!completer.isCompleted) completer.complete(v);
        })
        .catchError((_) {});
    return completer.future;
  }

  static Future<String> _guardedRun({
    required String url,
    String? injectJs,
    String? evalJs,
    required int timeoutMs,
    Map<String, String>? headers,
    String? userAgent,
  }) async {
    try {
      return await _run(
        url: url,
        injectJs: injectJs,
        evalJs: evalJs,
        timeoutMs: timeoutMs,
        headers: headers,
        userAgent: userAgent,
      );
    } catch (e) {
      debugPrint('HeadlessWebViewFetcher 失败: $e');
      return '';
    }
  }

  static Future<String> _run({
    required String url,
    String? injectJs,
    String? evalJs,
    required int timeoutMs,
    Map<String, String>? headers,
    String? userAgent,
  }) async {
    final done = Completer<String>();
    var settled = false;
    var disposed = false;
    iw.HeadlessInAppWebView? headless;

    void finish(String value) {
      if (settled) return;
      settled = true;
      if (!done.isCompleted) done.complete(value);
    }

    Future<void> safeDispose() async {
      if (disposed) return;
      disposed = true;
      final h = headless;
      if (h == null) return;
      try {
        await h.dispose();
      } catch (_) {}
    }

    final scripts = <iw.UserScript>[];
    final inject = injectJs?.trim() ?? '';
    if (inject.isNotEmpty) {
      scripts.add(iw.UserScript(
        source: _wrapInjectScript(inject),
        injectionTime: iw.UserScriptInjectionTime.AT_DOCUMENT_END,
      ));
    }

    try {
      headless = iw.HeadlessInAppWebView(
        initialSettings: iw.InAppWebViewSettings(
          javaScriptEnabled: true,
          domStorageEnabled: true,
          databaseEnabled: true,
          // 不弹新窗口（headless 场景一律禁用）
          supportMultipleWindows: false,
          javaScriptCanOpenWindowsAutomatically: false,
          // 禁止自动播放音视频，省资源
          mediaPlaybackRequiresUserGesture: true,
          userAgent: userAgent ?? _defaultUserAgent,
        ),
        initialUrlRequest: iw.URLRequest(url: iw.WebUri(url), headers: headers),
        initialUserScripts:
            scripts.isEmpty ? null : UnmodifiableListView(scripts),
        onWebViewCreated: (controller) {
          // 控制器在回调里已可用；此处无需额外处理
        },
        onLoadStop: (controller, loadedUrl) async {
          try {
            // 等 JS 渲染（部分站点在 load 后才异步填充 DOM）
            await Future<void>.delayed(_renderDelay);
            final script = (evalJs == null || evalJs.trim().isEmpty)
                ? 'document.documentElement.outerHTML'
                : evalJs;
            final res = await controller.evaluateJavascript(source: script);
            finish(res?.toString() ?? '');
          } catch (_) {
            finish('');
          } finally {
            await safeDispose();
          }
        },
        onReceivedError: (controller, request, error) async {
          // 仅主帧加载失败视为致命；子资源失败（图片/JS 404）不中断
          if (request.isForMainFrame == false) return;
          finish('');
          await safeDispose();
        },
      );
      await headless.run();
    } catch (_) {
      // 创建/运行失败（设备不支持、测试环境无平台实现等）：熔断，不再尝试
      _broken = true;
      finish('');
      await safeDispose();
      return '';
    }

    final result = await done.future.timeout(
      Duration(milliseconds: timeoutMs <= 0 ? 15000 : timeoutMs),
      onTimeout: () {
        settled = true;
        safeDispose();
        return '';
      },
    );
    await safeDispose();
    return result;
  }

  /// 用无头 WebView 加载 [url]，捕获页面导航/资源请求中第一个匹配
  /// [urlRegex] 的地址（
  /// `webViewGetOverrideUrl`）；未匹配则返回页面最终落地 URL（重定向结果）。
  /// 任何失败/超时返回空串，绝不抛异常；与 [fetch] 共用串行队列与熔断。
  static Future<String> fetchOverrideUrl({
    required String url,
    String html = '',
    String urlRegex = '',
    String injectJs = '',
    bool cacheFirst = false,
    int delayMs = 0,
    int timeoutMs = 25000,
    Map<String, String>? headers,
    String? userAgent,
  }) {
    if (_broken || kIsWeb || url.trim().isEmpty) return Future.value('');
    final completer = Completer<String>();
    final previous = _queue;
    // 与 fetch 相同的串行链式：前一个抓取结束后才启动当前任务。
    _queue = previous
        .catchError((_) {})
        .then((_) => _guardedCapture(
              url: url,
              html: html,
              urlRegex: urlRegex,
              injectJs: injectJs,
              cacheFirst: cacheFirst,
              delayMs: delayMs,
              timeoutMs: timeoutMs,
              headers: headers,
              userAgent: userAgent,
            ))
        .then((v) {
          if (!completer.isCompleted) completer.complete(v);
        })
        .catchError((_) {});
    return completer.future;
  }

  static Future<String> _guardedCapture({
    required String url,
    required String html,
    required String urlRegex,
    required String injectJs,
    required bool cacheFirst,
    required int delayMs,
    required int timeoutMs,
    Map<String, String>? headers,
    String? userAgent,
  }) async {
    try {
      return await _captureOverride(
        url: url,
        html: html,
        urlRegex: urlRegex,
        injectJs: injectJs,
        cacheFirst: cacheFirst,
        delayMs: delayMs,
        timeoutMs: timeoutMs,
        headers: headers,
        userAgent: userAgent,
      );
    } catch (e) {
      debugPrint('HeadlessWebViewFetcher.fetchOverrideUrl 失败: $e');
      return '';
    }
  }

  static Future<String> _captureOverride({
    required String url,
    required String html,
    required String urlRegex,
    required String injectJs,
    required bool cacheFirst,
    required int delayMs,
    required int timeoutMs,
    Map<String, String>? headers,
    String? userAgent,
  }) async {
    final done = Completer<String>();
    var settled = false;
    var disposed = false;
    iw.HeadlessInAppWebView? headless;
    RegExp? regex;
    if (urlRegex.trim().isNotEmpty) {
      try {
        regex = RegExp(urlRegex);
      } catch (_) {}
    }

    void finish(String value) {
      if (settled) return;
      settled = true;
      if (!done.isCompleted) done.complete(value);
    }

    Future<void> safeDispose() async {
      if (disposed) return;
      disposed = true;
      final h = headless;
      if (h == null) return;
      try {
        await h.dispose();
      } catch (_) {}
    }

    final scripts = <iw.UserScript>[];
    final inject = injectJs.trim();
    if (inject.isNotEmpty) {
      scripts.add(iw.UserScript(
        source: _wrapInjectScript(inject),
        injectionTime: iw.UserScriptInjectionTime.AT_DOCUMENT_END,
      ));
    }
    final useHtml = html.trim().isNotEmpty;

    try {
      headless = iw.HeadlessInAppWebView(
        initialSettings: iw.InAppWebViewSettings(
          javaScriptEnabled: true,
          domStorageEnabled: true,
          databaseEnabled: true,
          // 拦截所有资源请求以嗅探 overrideUrlRegex 命中的地址
          useShouldInterceptRequest: true,
          supportMultipleWindows: false,
          javaScriptCanOpenWindowsAutomatically: false,
          mediaPlaybackRequiresUserGesture: true,
          cacheMode: cacheFirst
              ? iw.CacheMode.LOAD_CACHE_ELSE_NETWORK
              : iw.CacheMode.LOAD_DEFAULT,
          userAgent: userAgent ?? _defaultUserAgent,
        ),
        initialUrlRequest: useHtml
            ? null
            : iw.URLRequest(url: iw.WebUri(url), headers: headers),
        initialData: useHtml
            ? iw.InAppWebViewInitialData(
                data: html,
                mimeType: 'text/html',
                encoding: 'utf-8',
                baseUrl: iw.WebUri(url),
              )
            : null,
        initialUserScripts:
            scripts.isEmpty ? null : UnmodifiableListView(scripts),
        // 对齐 SnifferWebClient.onLoadResource / shouldOverrideUrlLoading：
        // 任意一个请求命中正则即作为结果返回（返回 null 表示不真正拦截资源）。
        shouldInterceptRequest: (controller, request) {
          final reqUrl = request.url.toString();
          if (!settled && regex != null && regex.hasMatch(reqUrl)) {
            finish(reqUrl);
            unawaited(safeDispose());
          }
          return Future<iw.WebResourceResponse?>.value(null);
        },
        onLoadStop: (controller, loadedUrl) async {
          try {
            if (delayMs > 0) {
              await Future<void>.delayed(Duration(milliseconds: delayMs));
            }
            await Future<void>.delayed(_renderDelay);
            // 未命中正则：返回页面最终落地 URL（即重定向结果）
            if (!settled) finish(loadedUrl?.toString() ?? url);
          } catch (_) {
            if (!settled) finish('');
          } finally {
            await safeDispose();
          }
        },
        onReceivedError: (controller, request, error) async {
          if (request.isForMainFrame == false) return;
          if (!settled) finish('');
          await safeDispose();
        },
      );
      await headless.run();
    } catch (_) {
      _broken = true;
      finish('');
      await safeDispose();
      return '';
    }

    final result = await done.future.timeout(
      Duration(milliseconds: timeoutMs <= 0 ? 25000 : timeoutMs),
      onTimeout: () {
        settled = true;
        safeDispose();
        return '';
      },
    );
    await safeDispose();
    return result;
  }

  /// 规则 `@webjs:` 求值：把当前内容 [html] 作为页面加载，注入
  /// `window.result`（上一规则结果的 JSON）与书源常用全局，执行 [javaScript]
  /// 并把返回值还原为字符串。加载/执行失败或超时返回空串，绝不抛异常。
  /// 与 [fetch] 共用串行队列与熔断。
  static Future<String> fetchWebJs({
    required String baseUrl,
    required String html,
    required String javaScript,
    String result = '',
    int timeoutMs = 10000,
    Map<String, String>? headers,
    String? userAgent,
    String sourceKey = '',
  }) {
    final origin = _webJsBase(baseUrl);
    if (_broken || kIsWeb || origin.isEmpty || javaScript.trim().isEmpty) {
      return Future.value('');
    }
    final completer = Completer<String>();
    final previous = _queue;
    _queue = previous
        .catchError((_) {})
        .then((_) => _guardedWebJs(
              origin: origin,
              html: html,
              javaScript: javaScript,
              result: result,
              timeoutMs: timeoutMs,
              headers: headers,
              userAgent: userAgent,
              sourceKey: sourceKey,
            ))
        .then((v) {
          if (!completer.isCompleted) completer.complete(v);
        })
        .catchError((_) {});
    return completer.future;
  }

  /// 把 baseUrl 规整为可作为 initialData 页面源的 http(s) 地址，
  /// 避免 about:blank 之类的 opaque origin 让页面脚本受限。
  static String _webJsBase(String baseUrl) {
    final uri = Uri.tryParse(baseUrl.trim());
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return uri.replace(query: '', fragment: '').toString();
    }
    return '';
  }

  static Future<String> _guardedWebJs({
    required String origin,
    required String html,
    required String javaScript,
    required String result,
    required int timeoutMs,
    Map<String, String>? headers,
    String? userAgent,
    String sourceKey = '',
  }) async {
    try {
      return await _runWebJs(
        origin: origin,
        html: html,
        javaScript: javaScript,
        result: result,
        timeoutMs: timeoutMs,
        headers: headers,
        userAgent: userAgent,
        sourceKey: sourceKey,
      );
    } catch (e) {
      debugPrint('HeadlessWebViewFetcher.fetchWebJs 失败: $e');
      return '';
    }
  }

  static Future<String> _runWebJs({
    required String origin,
    required String html,
    required String javaScript,
    required String result,
    required int timeoutMs,
    Map<String, String>? headers,
    String? userAgent,
    String sourceKey = '',
  }) async {
    final done = Completer<String>();
    var settled = false;
    var disposed = false;
    iw.HeadlessInAppWebView? headless;

    void finish(String value) {
      if (settled) return;
      settled = true;
      if (!done.isCompleted) done.complete(value);
    }

    Future<void> safeDispose() async {
      if (disposed) return;
      disposed = true;
      final h = headless;
      if (h == null) return;
      try {
        await h.dispose();
      } catch (_) {}
    }

    // 注入 window.result（JSON 字符串）与 baseUrl / source 常用全局。
    // result 用 JSON 字符串字面量，书源脚本可 JSON.parse(result) 或直接用字符串。
    final inject = <String>[
      'window.result = ${jsonEncode(result)};',
      'window.baseUrl = ${jsonEncode(origin)};',
      'window.sourceKey = ${jsonEncode(sourceKey)};',
      'window.content = ${jsonEncode(html)};',
    ].join('\n');

    final scripts = <iw.UserScript>[
      iw.UserScript(
        source: inject,
        injectionTime: iw.UserScriptInjectionTime.AT_DOCUMENT_START,
      ),
    ];

    try {
      headless = iw.HeadlessInAppWebView(
        initialSettings: iw.InAppWebViewSettings(
          javaScriptEnabled: true,
          domStorageEnabled: true,
          supportMultipleWindows: false,
          javaScriptCanOpenWindowsAutomatically: false,
          mediaPlaybackRequiresUserGesture: true,
          userAgent: userAgent ?? _defaultUserAgent,
        ),
        initialData: iw.InAppWebViewInitialData(
          data: html.isEmpty ? '<html><body></body></html>' : html,
          mimeType: 'text/html',
          encoding: 'utf-8',
          baseUrl: iw.WebUri(origin),
          historyUrl: iw.WebUri(origin),
        ),
        initialUserScripts: UnmodifiableListView(scripts),
        onLoadStop: (controller, loadedUrl) async {
          try {
            final res = await controller.evaluateJavascript(source: javaScript);
            finish(_decodeWebJsValue(res));
          } catch (_) {
            finish('');
          } finally {
            await safeDispose();
          }
        },
        onReceivedError: (controller, request, error) async {
          if (request.isForMainFrame == false) return;
          finish('');
          await safeDispose();
        },
      );
      await headless.run();
    } catch (_) {
      _broken = true;
      finish('');
      await safeDispose();
      return '';
    }

    final value = await done.future.timeout(
      Duration(milliseconds: timeoutMs <= 0 ? 10000 : timeoutMs),
      onTimeout: () {
        settled = true;
        safeDispose();
        return '';
      },
    );
    await safeDispose();
    return value;
  }

  /// evaluateJavascript 返回值：字符串为 JSON 带引号字面量，需去引号反转义；
  /// 数字/布尔/null 直接取字符串；null 视为空。
  static String _decodeWebJsValue(dynamic raw) {
    if (raw == null) return '';
    if (raw is String) {
      if (raw == 'null' || raw.isEmpty) return '';
      if (raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')) {
        try {
          final decoded = jsonDecode(raw);
          return decoded is String ? decoded : decoded.toString();
        } catch (_) {
          return raw.substring(1, raw.length - 1);
        }
      }
      return raw;
    }
    return raw.toString();
  }

  /// 把用户脚本包装为自执行异步函数：非空结果写入
  /// `window.__legadoWebJsResult`，供加载完成后的 evalJs 读取。
  /// 脚本内异常一律吞掉（由调用方按空结果降级）。
  static String _wrapInjectScript(String js) {
    return '''
(function(){
  window.__legadoWebJsResult = '';
  (async function(){
    try {
      var __r = await (async function(){ $js })();
      if (__r !== undefined && __r !== null && __r !== '') {
        window.__legadoWebJsResult = (typeof __r === 'string') ? __r : JSON.stringify(__r);
      }
    } catch (e) {}
  })();
})();
''';
  }
}
