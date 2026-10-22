import 'dart:async';
import 'dart:collection';

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
  /// （对齐 legado BackstageWebView 的 delayTime≈900ms）。
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
