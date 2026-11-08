/// 由 offline_js_bridge.dart 按「一类一文件」拆出的 OfflineJsBridge。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../offline_js_bridge.dart';


/// 离线 JS 运行时外观：把书源的 jsLib / loginUrl 组装为「注入脚本」供断言。
///
/// 与 `WebViewLegadoJs.loadSource` 的注入顺序一致（bridge 之后执行 jsLib、
/// 再执行 loginUrl）；仅做脚本收集与函数检测，不执行 JS、不触碰 WebView。
class OfflineJsBridge {
  final JsBridgeCache cache = JsBridgeCache();
  final JsBridgeCookie cookie = JsBridgeCookie();
  late final JsBridgeSource source;
  String _script = '';

  /// 注入书源脚本（对齐 WebViewLegadoJs.loadSource 的 jsLib + loginUrl 顺序）。
  void loadSource(JsSource src) {
    source = JsBridgeSource(url: src.jsUrl, variable: src.variable ?? '');
    final buf = StringBuffer();
    final lib = (src.jsLib ?? '').trim();
    if (lib.isNotEmpty) buf.writeln(lib);
    final login = (src.loginUrl ?? '').trim();
    if (login.isNotEmpty) buf.writeln(login);
    _script = buf.toString();
  }

  /// 已组装的注入脚本（jsLib + loginUrl）。
  String get script => _script;

  /// 注入脚本是否定义了关键全局函数（如 getArguments / getServerHost）。
  bool containsFunction(String name) => RegExp(
          r'function\s+' +
              RegExp.escape(name) +
              r'\s*\(|(?:var|let|const)\s+' +
              RegExp.escape(name) +
              r'\s*=')
      .hasMatch(_script);
}
