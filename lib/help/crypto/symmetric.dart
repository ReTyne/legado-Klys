/// 从 crypto_utils.dart 拆分： `help/crypto/` 按算法分文件。
/// 以 part 归属同一库，私有类型互引保持可用。
part of '../../utils/crypto_utils.dart';


// =====================================================================
// 对称加密门面（对齐 hutool SymmetricCrypto 被书源调用的方法集）
// =====================================================================

/// 对称加密器：java.createSymmetricCrypto(transformation, key, iv)。
class SymmetricCrypto {
  SymmetricCrypto(String transformation, dynamic key, {dynamic iv}) {
    _t = _Transformation(transformation);
    _key = _normalizeKey(_t.algorithm, _toBytes(key));
    if (iv != null) setIv(iv);
  }

  late final _Transformation _t;
  late final Uint8List _key;
  Uint8List? _iv;

  static Uint8List _toBytes(dynamic v) {
    if (v is List<int>) return Uint8List.fromList(v);
    if (v is String) return Uint8List.fromList(utf8.encode(v));
    throw ArgumentError('key/iv 仅支持 String 或字节数组');
  }

  static int _blockSizeOf(String alg) => alg == 'DES' || alg == 'DESEDE' ? 8 : 16;

  void setIv(dynamic iv) {
    if (_t.algorithm == 'RC4') return; // 流密码无 IV
    final b = _toBytes(iv);
    final bs = _blockSizeOf(_t.algorithm);
    final out = Uint8List(bs);
    final n = b.length > bs ? bs : b.length;
    out.setRange(0, n, b);
    _iv = out;
  }

  Uint8List _crypt(List<int> data, bool encrypt) {
    final input = Uint8List.fromList(data);
    if (_t.algorithm == 'RC4') {
      final out = Uint8List(input.length);
      _Rc4Engine(_key).process(input, 0, input.length, out, 0);
      return out;
    }
    final cipher = _createCipher(_t, _key);
    final buf = _t.padded && encrypt ? _padPkcs7(input, cipher.blockSize) : input;
    return _applyMode(cipher, _parseMode(_t.mode), _iv, buf, encrypt);
  }

  /// 加密 → 字节数组。
  Uint8List encrypt(dynamic data) => _crypt(_toBytes(data), true);

  /// 加密 → Base64。
  String encryptBase64(dynamic data) => base64.encode(encrypt(data));

  /// 加密 → Hex。
  String encryptHex(dynamic data) => _bytesToHex(encrypt(data));

  Uint8List decryptBytes(List<int> data) {
    final out = _crypt(data, false);
    if (_t.padded) return _unpadPkcs7(out, _blockSizeOf(_t.algorithm));
    return out;
  }

  /// 解密：String 入参自动识别 hex/base64，返回字节数组。
  Uint8List decrypt(dynamic data) {
    if (data is String) return decryptBytes(_autoDecodeData(data));
    return decryptBytes(data as List<int>);
  }

  /// 解密 → UTF-8 字符串。
  String decryptStr(dynamic data) => utf8.decode(decrypt(data), allowMalformed: true);

  /// 解密 Base64 数据 → UTF-8 字符串。
  String decryptBase64(String data) {
    final b = _tryBase64ToBytes(data) ?? _utf8Bytes(data);
    return utf8.decode(decryptBytes(b), allowMalformed: true);
  }

  /// 解密 Hex 数据 → UTF-8 字符串。
  String decryptHex(String data) {
    final b = _tryHexToBytes(data) ?? _utf8Bytes(data);
    return utf8.decode(decryptBytes(b), allowMalformed: true);
  }
}
