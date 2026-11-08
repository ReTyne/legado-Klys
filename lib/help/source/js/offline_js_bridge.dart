import 'dart:convert';

import 'js_source.dart';

part 'parts/js_bridge_env.dart';
part 'parts/js_bridge_time.dart';
part 'parts/js_bridge_cache.dart';
part 'parts/js_bridge_cookie.dart';
part 'parts/js_bridge_source.dart';
part 'parts/js_symmetric_crypto.dart';
part 'parts/js_bridge_crypto.dart';
part 'parts/offline_js_bridge.dart';
part 'parts/aes_core.dart';
part 'parts/des_core.dart';


/// 纯 Dart 实现的 legado JS 桥 API 子集（离线可测，不依赖 WebView / 网络 / 平台通道）。
///
/// 用途：把「两个真实聚合源（7632 / 7814）重度依赖、且可纯 Dart 实现」的桥 API
/// 做成真实实现，供 `test/real_source_compat_test.dart` 在无 WebView 的单测里断言。
/// 与 `legado_bridge_js.dart`（注入 WebView 的 JS 桥）语义对齐：
///   * java.base64Encode / base64Decode / base64DecodeToByteArray
///   * java.getWebViewUA、java.timeFormat
///   * cache.put/get/putMemory/getFromMemory
///   * cookie.getCookie/setCookie/removeCookie/getKey
///   * source.getVariable/setVariable/getLoginInfo/putLoginInfo/getLoginInfoMap/getKey/getLoginHeader
///   * java.createSymmetricCrypto（AES / DES，ECB / CBC，PKCS5 / PKCS7）
///
/// 平台边界（不在此假实现）：java.ajax / startBrowserAwait / searchBook /
/// refreshExplore、Packages.*、java.deviceID（iOS 专属）依赖 Android 原生、
/// Rhino Java 互操作或可见 WebView，仍由 WebView 桥 + 原生通道承担。

/// 对齐 java.base64Encode / base64Decode / base64DecodeToByteArray 的真实编解码。
class JsBridgeCodec {
  JsBridgeCodec._();

  /// base64 编码（对齐 __b64Unicode：先取 UTF-8 字节）。
  static String base64Encode(String text) => base64.encode(utf8.encode(text));

  /// base64 解码为 UTF-8 字符串（解码失败返回空串，对齐桥的 try/catch 兜底）。
  static String base64Decode(String text) {
    try {
      return utf8.decode(base64.decode(_clean(text)));
    } catch (_) {
      return '';
    }
  }

  /// 对齐 java.base64DecodeToByteArray：返回字节数组，供 createSymmetricCrypto 解密。
  static List<int> base64DecodeToByteArray(String text) {
    try {
      return base64.decode(_clean(text));
    } catch (_) {
      return <int>[];
    }
  }

  /// 字节数组 -> base64（对齐 encryptBase64）。
  static String bytesToBase64(List<int> bytes) => base64.encode(bytes);

  /// 字节数组 -> 小写 hex（对齐 encryptHex）。
  static String bytesToHex(List<int> bytes) =>
      bytes.map((b) => (b & 0xff).toRadixString(16).padLeft(2, '0')).join();

  /// hex 字符串 -> 字节数组（对齐 __hexToBytes）。
  static List<int> hexToBytes(String hex) {
    final h = hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    final out = <int>[];
    for (var i = 0; i + 1 < h.length; i += 2) {
      out.add(int.parse(h.substring(i, i + 2), radix: 16));
    }
    return out;
  }

  static String _clean(String s) => s.replaceAll(RegExp(r'\s'), '');
}
