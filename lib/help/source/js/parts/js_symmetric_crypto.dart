/// 由 offline_js_bridge.dart 按「一类一文件」拆出的 JsSymmetricCrypto。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../offline_js_bridge.dart';


/// createSymmetricCrypto 返回的加解密句柄（对齐 legado JsExtensions）。
class JsSymmetricCrypto {
  JsSymmetricCrypto._(this._isAes, this._cbc, this._block, this._iv,
      this._aes, this._des);

  final bool _isAes;
  final bool _cbc;
  final int _block;
  final List<int> _iv;
  final _AesCore? _aes;
  final _DesCore? _des;

  List<int> _encBlock(List<int> b) =>
      _isAes ? _aes!.encryptBlock(b) : _des!.encryptBlock(b);
  List<int> _decBlock(List<int> b) =>
      _isAes ? _aes!.decryptBlock(b) : _des!.decryptBlock(b);

  /// 单分组 ECB 原语（无填充/无 CBC 链），用于对齐 AES / DES 标准测试向量。
  List<int> encryptBlock(List<int> block) => _encBlock(block);

  /// 单分组 ECB 解密原语（与 [encryptBlock] 互逆）。
  List<int> decryptBlock(List<int> block) => _decBlock(block);

  /// 加密字节（PKCS5/PKCS7 填充 + 可选 CBC），返回字节数组（对齐 encrypt）。
  List<int> encrypt(List<int> data) {
    final padded = _pad(data, _block);
    final out = <int>[];
    var prev = List<int>.from(_iv);
    for (var off = 0; off < padded.length; off += _block) {
      final block = padded.sublist(off, off + _block);
      final x = _cbc
          ? List<int>.generate(_block, (i) => block[i] ^ prev[i])
          : block;
      final c = _encBlock(x);
      out.addAll(c);
      prev = c;
    }
    return out;
  }

  /// 加密字符串为 base64（对齐 encryptBase64）。
  String encryptBase64(String text) =>
      JsBridgeCodec.bytesToBase64(encrypt(utf8.encode(text)));

  /// 加密字符串为 hex（对齐 encryptHex）。
  String encryptHex(String text) =>
      JsBridgeCodec.bytesToHex(encrypt(utf8.encode(text)));

  /// 解密字节数组（可选 CBC + 去填充），返回明文字节（对齐 decrypt）。
  List<int> decrypt(List<int> cipher) {
    final out = <int>[];
    var prev = List<int>.from(_iv);
    for (var off = 0; off + _block <= cipher.length; off += _block) {
      final c = cipher.sublist(off, off + _block);
      final p = _decBlock(c);
      out.addAll(_cbc
          ? List<int>.generate(_block, (i) => p[i] ^ prev[i])
          : p);
      prev = c;
    }
    return _unpad(out, _block);
  }

  /// 解密字符串（hex 或 base64；亦兼容 7814 传入的字节数组）为 UTF-8 明文。
  String decryptStr(Object input) {
    List<int> bytes;
    if (input is List<int>) {
      bytes = input;
    } else {
      final s = input.toString();
      bytes = RegExp(r'^[0-9a-fA-F]+$').hasMatch(s) && s.length.isEven
          ? JsBridgeCodec.hexToBytes(s)
          : JsBridgeCodec.base64DecodeToByteArray(s);
    }
    try {
      return utf8.decode(decrypt(bytes));
    } catch (_) {
      return '';
    }
  }

  static List<int> _pad(List<int> data, int block) {
    final pad = block - (data.length % block);
    return [...data, ...List<int>.filled(pad, pad)];
  }

  static List<int> _unpad(List<int> data, int block) {
    if (data.isEmpty) return data;
    final p = data.last;
    if (p > 0 && p <= block && data.length >= p) {
      for (var i = data.length - p; i < data.length; i++) {
        if (data[i] != p) return data;
      }
      return data.sublist(0, data.length - p);
    }
    return data;
  }
}
