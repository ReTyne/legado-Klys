/// 由 offline_js_bridge.dart 按「一类一文件」拆出的 JsBridgeCrypto。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../offline_js_bridge.dart';


/// 提供 java.createSymmetricCrypto(transformation, key, iv)：纯 Dart AES / DES。
class JsBridgeCrypto {
  JsBridgeCrypto._();

  /// transformation 形如 "AES"、"AES/CBC/PKCS5Padding"、"DES/CBC/PKCS5Padding"。
  /// 含 CBC 走 CBC，否则 ECB；含 DES 走 DES（8 字节分组），否则 AES（16 字节分组）。
  /// key/iv 可为 String（书源原始值，按 UTF-8 取字节）或 List<int>（字节数组，供标准向量测试）。
  static JsSymmetricCrypto createSymmetricCrypto(
      String transformation, Object key, [Object iv = '']) {
    final mode = transformation.toUpperCase();
    // DESede / 3DES / TripleDES 是三次 DES（24 字节密钥），不能当单 DES 处理。
    final isTripleDes = mode.contains('DESEDE') ||
        mode.contains('3DES') ||
        mode.contains('TRIPLEDES');
    final isDes = !isTripleDes && mode.contains('DES');
    final isAes = !isTripleDes && !isDes;
    final cbc = mode.contains('CBC');
    final block = isAes ? 16 : 8;
    final kb = _bytesOf(key);
    final ivBytes = _padTo(_bytesOf(iv), block);
    if (isTripleDes) {
      var k = kb;
      // 两密钥 3DES（16 字节）按 K3 = K1 处理。
      if (k.length == 16) k = [...k, ...k.sublist(0, 8)];
      return JsSymmetricCrypto._(
          false, cbc, 8, ivBytes, null, _TripleDesCore(_padTo(k, 24)));
    }
    final keyBytes = isAes ? _aesKeyBytes(kb) : _padTo(kb, 8);
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

  /// key 补零到最近的 16/24/32 字节，超长截断到 32。
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

/// 三次 DES（EDE）：K1 加密 → K2 解密 → K3 加密，24 字节密钥。
/// 复用单 DES 分组原语，由 [JsSymmetricCrypto] 负责 CBC 链与 PKCS7 填充。
class _TripleDesCore extends _DesCore {
  _TripleDesCore(List<int> key24)
      : _k1 = _DesCore(key24.sublist(0, 8)),
        _k2 = _DesCore(key24.sublist(8, 16)),
        _k3 = _DesCore(key24.sublist(16, 24)),
        super(key24.sublist(0, 8));

  final _DesCore _k1;
  final _DesCore _k2;
  final _DesCore _k3;

  @override
  List<int> encryptBlock(List<int> block8) =>
      _k3.encryptBlock(_k2.decryptBlock(_k1.encryptBlock(block8)));

  @override
  List<int> decryptBlock(List<int> block8) =>
      _k1.decryptBlock(_k2.encryptBlock(_k3.decryptBlock(block8)));
}
