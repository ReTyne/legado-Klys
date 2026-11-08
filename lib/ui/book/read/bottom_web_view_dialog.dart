import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:legado_md3/help/device/native_bridge.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';

/// 响应式底部 WebView 弹窗配置（对齐 Sigma `BottomWebViewDialog.Config` 的可落地子集）。
class BottomWebViewConfig {
  /// 弹窗占屏高比例（Sigma peekHeight）
  final double peekHeight;

  /// 平板/宽屏断点；超过则居中并限制宽度
  final double responsiveBreakpoint;

  /// 宽屏时占父宽比例
  final double widthPercentage;

  /// 最大宽度（像素）
  final double maxWidth;

  /// 长按图片是否弹出保存
  final bool longClickSaveImg;

  /// 滚动时是否禁止拖拽调整高度
  final bool scrollNoDraggable;

  /// 背景遮罩暗度
  final double backgroundDimAmount;

  /// 是否启用硬件加速
  final bool hardwareAccelerated;

  /// 是否允许 JS 控制横竖屏（注入 `window.legadoSetOrientation`）
  final bool jsControlOrientation;

  /// 是否覆盖 `window.close()` 并转发到 Dart
  final bool overrideWindowClose;

  /// 是否监听网页 console 日志
  final bool listenConsole;

  /// 退出时是否清空 WebView 缓存/历史（对齐 clearHistory）
  final bool clearHistoryOnClose;

  /// 自定义 UA；为空用内置移动 UA
  final String? userAgent;

  const BottomWebViewConfig({
    this.peekHeight = 0.72,
    this.responsiveBreakpoint = 600,
    this.widthPercentage = 0.7,
    this.maxWidth = 720,
    this.longClickSaveImg = true,
    this.scrollNoDraggable = true,
    this.backgroundDimAmount = 0.32,
    this.hardwareAccelerated = true,
    this.jsControlOrientation = true,
    this.overrideWindowClose = true,
    this.listenConsole = true,
    this.clearHistoryOnClose = true,
    this.userAgent,
  });
}

const String _kMobileUa =
    'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36';

/// 书源登录 / 章节购买 / 验证码等交互场景的底部 WebView。
///
/// 真实能力：
/// - `flutter_inappwebview` 加载页面，JS Handler 与页面双向通信；
/// - 注入脚本覆盖 `window.close()` → 关闭弹窗，接管 `console.log` → Dart 日志；
/// - 注入 `window.legadoSetOrientation('landscape'|'portrait'|'auto')` 让书源 JS 控横竖屏；
/// - `onLongPressHitTestResult` 长按图片 → dio 下载 → 落盘 + 经原生桥分享；
/// - 宽屏按 [BottomWebViewConfig.responsiveBreakpoint] 居中限宽（响应式）；
/// - 退出时回传当前页面 HTML 给调用方（书源据此取登录后的结构/Cookie）。
class BottomWebViewDialog extends StatefulWidget {
  final String url;
  final String? title;
  final BottomWebViewConfig config;

  const BottomWebViewDialog({
    super.key,
    required this.url,
    this.title,
    this.config = const BottomWebViewConfig(),
  });

  /// 统一入口，返回退出时的页面 HTML（书源登录需要）。
  static Future<String?> show(
    BuildContext context, {
    required String url,
    String? title,
    BottomWebViewConfig config = const BottomWebViewConfig(),
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      enableDrag: !config.scrollNoDraggable,
      backgroundColor: Colors.transparent,
      barrierColor: Theme.of(context).colorScheme.scrim
              .withOpacity(config.backgroundDimAmount),
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            height: MediaQuery.of(ctx).size.height *
                config.peekHeight.clamp(0.3, 0.95),
            child: BottomWebViewDialog(
              url: url,
              title: title,
              config: config,
            ),
          ),
        );
      },
    );
  }

  @override
  State<BottomWebViewDialog> createState() => _BottomWebViewDialogState();
}

class _BottomWebViewDialogState extends State<BottomWebViewDialog> {
  InAppWebViewController? _controller;
  int _progress = 0;
  String _currentTitle = '';
  String? _error;
  final List<String> _consoleLogs = [];
  bool _closing = false;

  BottomWebViewConfig get cfg => widget.config;

  /// 注入到页面的桥接脚本：window.close / console / 控屏。
  String get _bridgeScript => '''
(function(){
  var ch = function(){
    return window.flutter_inappwebview && window.flutter_inappwebview.callHandler
      ? window.flutter_inappwebview.callHandler.bind(window.flutter_inappwebview) : null;
  };
  ${cfg.overrideWindowClose ? '''
  if (!window.__legadoCloseHooked) {
    window.__legadoCloseHooked = true;
    window.close = function(){ var f=ch(); if(f) f('legadoClose'); };
  }''' : ''}
  ${cfg.listenConsole ? '''
  if (!window.__legadoLogHooked) {
    window.__legadoLogHooked = true;
    var _log = console.log;
    console.log = function(){
      try { var f=ch(); if(f) f('legadoLog', Array.prototype.join.call(arguments,' ')); } catch(e){}
      _log.apply(console, arguments);
    };
  }''' : ''}
  ${cfg.jsControlOrientation ? '''
  window.legadoSetOrientation = function(mode){
    var f=ch(); if(f) f('legadoOrientation', String(mode||'auto'));
  };''' : ''}
})();
''';

  void _registerHandlers(InAppWebViewController c) {
    c.addJavaScriptHandler(
      handlerName: 'legadoClose',
      callback: (args) {
        _close(null);
        return null;
      },
    );
    if (cfg.listenConsole) {
      c.addJavaScriptHandler(
        handlerName: 'legadoLog',
        callback: (args) {
          final line = args.isNotEmpty ? '${args.first}' : '';
          if (line.isNotEmpty && _consoleLogs.length < 200) {
            _consoleLogs.add(line);
          }
          return null;
        },
      );
    }
    if (cfg.jsControlOrientation) {
      c.addJavaScriptHandler(
        handlerName: 'legadoOrientation',
        callback: (args) {
          final mode = args.isNotEmpty ? '${args.first}' : 'auto';
          _applyOrientation(mode);
          return null;
        },
      );
    }
  }

  Future<void> _applyOrientation(String mode) async {
    try {
      if (mode == 'landscape') {
        await SystemChrome.setPreferredOrientations(
            [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      } else if (mode == 'portrait') {
        await SystemChrome.setPreferredOrientations(
            [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
      } else {
        await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      }
    } catch (_) {}
  }

  Future<void> _close(String? html) async {
    if (_closing) return;
    _closing = true;
    // 恢复屏幕方向（网页可能改过）
    try {
      await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    } catch (_) {}
    if (cfg.clearHistoryOnClose) {
      try {
        await InAppWebViewController.clearAllCache();
      } catch (_) {}
    }
    if (mounted) Navigator.pop(context, html);
  }

  Future<String?> _grabHtml() async {
    try {
      final html = await _controller?.evaluateJavascript(
          source: 'document.documentElement.outerHTML');
      return html is String ? html : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveImage(String url) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final resp = await Dio().get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 20),
        ),
      );
      final bytes = Uint8List.fromList(resp.data ?? <int>[]);
      if (bytes.isEmpty) {
        messenger.showSnackBar(const SnackBar(content: Text('图片为空，保存失败')));
        return;
      }
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory(p.join(dir.path, 'webview_images'));
      if (!await folder.exists()) await folder.create(recursive: true);
      final ext = _guessExt(url);
      final file = File(p.join(
          folder.path, 'img_${DateTime.now().millisecondsSinceEpoch}.$ext'));
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('图片已保存：${file.path}'),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: '分享',
            onPressed: () => NativeBridge.instance.shareFile(
              file.path,
              mime: 'image/*',
              title: '网页图片',
            ),
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('保存图片失败：$e')));
    }
  }

  String _guessExt(String url) {
    final lower = url.toLowerCase().split('?').first;
    if (lower.endsWith('.png')) return 'png';
    if (lower.endsWith('.webp')) return 'webp';
    if (lower.endsWith('.gif')) return 'gif';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'jpg';
    return 'jpg';
  }

  Future<void> _onLongPress(
      InAppWebViewController c, InAppWebViewHitTestResult hit) async {
    if (!cfg.longClickSaveImg) return;
    final type = hit.type;
    final isImage = type == InAppWebViewHitTestResultType.IMAGE_TYPE ||
        type == InAppWebViewHitTestResultType.SRC_IMAGE_ANCHOR_TYPE;
    final src = hit.extra;
    if (!isImage || src == null || src.isEmpty || !src.startsWith('http')) return;
    final confirm = await showAppConfirmDialog(
      context,
      title: '保存图片',
      content: '把网页图片保存到本地？\n$src',
      confirmText: '保存',
    );
    if (confirm) await _saveImage(src);
  }

  Future<void> _showConsole() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('网页日志'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(
              _consoleLogs.isEmpty ? '（暂无 console 输出）' : _consoleLogs.join('\n'),
              style: const TextStyle(fontSize: 11, height: 1.5),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (ctx, constraints) {
      final wide = constraints.maxWidth > cfg.responsiveBreakpoint;
      final width = wide
          ? (constraints.maxWidth * cfg.widthPercentage).clamp(0.0, cfg.maxWidth)
          : constraints.maxWidth;
      final body = Column(
        children: [
          // 拖拽把手
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withOpacity(0.4),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          // 标题栏
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    (widget.title != null && widget.title!.isNotEmpty)
                        ? widget.title!
                        : (_currentTitle.isNotEmpty
                            ? _currentTitle
                            : '交互网页'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: '返回上一页',
                  icon: const Icon(Icons.arrow_back_outlined, size: 20),
                  onPressed: () async {
                    if (await _controller?.canGoBack() ?? false) {
                      _controller?.goBack();
                    }
                  },
                ),
                IconButton(
                  tooltip: '刷新页面',
                  icon: const Icon(Icons.refresh_outlined, size: 20),
                  onPressed: () => _controller?.reload(),
                ),
                if (cfg.listenConsole)
                  IconButton(
                    tooltip: '查看网页日志',
                    icon: const Icon(Icons.article_outlined, size: 20),
                    onPressed: _showConsole,
                  ),
                IconButton(
                  tooltip: '完成并回传页面',
                  icon: const Icon(Icons.check_outlined, size: 20),
                  onPressed: () async => _close(await _grabHtml()),
                ),
                IconButton(
                  tooltip: '关闭',
                  icon: const Icon(Icons.close_outlined, size: 20),
                  onPressed: () => _close(null),
                ),
              ],
            ),
          ),
          if (_progress < 100)
            LinearProgressIndicator(value: _progress / 100, minHeight: 2),
          Expanded(
            child: _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.error_outline, size: 40, color: cs.error),
                          const SizedBox(height: 8),
                          Text('页面加载失败：$_error',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: cs.onSurfaceVariant)),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: () {
                              setState(() => _error = null);
                              _controller?.reload();
                            },
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    ),
                  )
                : InAppWebView(
                    initialUrlRequest:
                        URLRequest(url: WebUri(widget.url)),
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: true,
                      domStorageEnabled: true,
                      useShouldOverrideUrlLoading: true,
                      mixedContentMode:
                          MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                      userAgent: cfg.userAgent ?? _kMobileUa,
                      supportZoom: true,
                      builtInZoomControls: true,
                      cacheEnabled: !cfg.clearHistoryOnClose,
                      hardwareAcceleration: cfg.hardwareAccelerated,
                      verticalScrollBarEnabled: true,
                      horizontalScrollBarEnabled: false,
                    ),
                    onWebViewCreated: (c) {
                      _controller = c;
                      _registerHandlers(c);
                    },
                    onProgressChanged: (c, v) {
                      if (mounted) setState(() => _progress = v);
                    },
                    onTitleChanged: (c, title) {
                      if (title != null && title.isNotEmpty && mounted) {
                        setState(() => _currentTitle = title);
                      }
                    },
                    onLoadStop: (c, url) async {
                      try {
                        await c.evaluateJavascript(source: _bridgeScript);
                      } catch (_) {}
                    },
                    onConsoleMessage: (c, msg) {
                      if (cfg.listenConsole &&
                          msg.message.isNotEmpty &&
                          _consoleLogs.length < 200) {
                        _consoleLogs.add(msg.message);
                      }
                    },
                    onCloseWindow: (c) => _close(null),
                    onLongPressHitTestResult: _onLongPress,
                    onReceivedError: (c, req, err) {
                      if (mounted) {
                        setState(() => _error = err.description);
                      }
                    },
                  ),
          ),
        ],
      );
      return Center(
        child: SizedBox(
          width: width,
          child: ClipRRect(
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
            child: body,
          ),
        ),
      );
    });
  }
}
