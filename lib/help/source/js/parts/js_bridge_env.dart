/// 由 offline_js_bridge.dart 按「一类一文件」拆出的 JsBridgeEnv。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../offline_js_bridge.dart';


/// 对齐 java.getWebViewUA：无 WebView 时的默认 UA（与桥 __state.ua 默认值一致）。
class JsBridgeEnv {
  JsBridgeEnv._();

  static const String webViewUA =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/120.0.0.0 Mobile Safari/537.36';
}
