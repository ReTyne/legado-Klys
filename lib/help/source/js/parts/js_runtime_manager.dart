/// 由 legado_js_runtime.dart 按「一类一文件」拆出的 JsRuntimeManager。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../legado_js_runtime.dart';


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
    // 初始化失败（WebView 超时/异常）时回退迷你求值器，保证书源链路不挂死
    try {
      await rt.loadSource(source).timeout(const Duration(seconds: 20));
    } catch (e) {
      debugPrint('JS 运行时初始化失败，回退迷你求值器: $e');
      try {
        await rt.dispose();
      } catch (_) {}
      rt = MiniLegadoJs();
      await rt.loadSource(source);
    }
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
