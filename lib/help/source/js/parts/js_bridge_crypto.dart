/// 由 offline_js_bridge.dart 按「一类一文件」拆出的 JsBridgeCrypto。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../offline_js_bridge.dart';


/// 对齐 java.createSymmetricCrypto(transformation, key, iv)：纯 Dart AES / DES。
class JsBridgeCrypto {
  JsBridgeCrypto._();

  /// transformation 形如 "AES"、"AES/CBC/PKCS5Padding"、"DES/CBC/PKCS5Padding"。
  /// 含 CBC 走 CBC，否则 ECB；含 DES 走 DES（8 字节分组），否则 AES（16 字节分组）。
  /// key/iv 可为 String（书源原始值，按 UTF-8 取字节）或 List<int>（字节数组，供标准向量测试）。
  static JsSymmetricCrypto createSymmetricCrypto(
      String transformation, Object key, [Object iv = '']) {
    final mode = transformation.toUpperCase();
    final isAes = !mode.contains('DES');
    final cbc = mode.contains('CBC');
    final block = isAes ? 16 : 8;
    final kb = _bytesOf(key);
    final keyBytes = isAes ? _aesKeyBytes(kb) : _padTo(kb, 8);
    final ivBytes = _padTo(_bytesOf(iv), block);
    return JsSymmetricCrypto._(
      isAes,
      cbc,
      block,
      ivBytes,
      isAes ? _AesCore(keyBytes) : null,
      isAes ? null : _DesCore(keyBytes),
    );
  }

  static List<int> _bytesOf(Object v) =>
      v is List<int> ? List<int>.from(v) : utf8.encode(v.toString());

  /// 对齐桥 __aesKeyBytes：key 补零到最近的 16/24/32 字节，超长截断到 32。
  static List<int> _aesKeyBytes(List<int> kb) {
    for (final size in const [16, 24, 32]) {
      if (kb.length <= size) return _padTo(kb, size);
    }
    return kb.sublist(0, 32);
  }

  static List<int> _padTo(List<int> bytes, int size) {
    final out = List<int>.filled(size, 0);
    final n = bytes.length < size ? bytes.length : size;
    for (var i = 0; i < n; i++) {
      out[i] = bytes[i];
    }
    return out;
  }
}
