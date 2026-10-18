import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;

/// 加解密辅助：MD5/SHA1/SHA256/Base64
class CryptoHelper {
  CryptoHelper._();

  static String md5(String s) => crypto.md5.convert(utf8.encode(s)).toString();
  static String md5Bytes(List<int> bytes) => crypto.md5.convert(bytes).toString();

  static String sha1(String s) => crypto.sha1.convert(utf8.encode(s)).toString();
  static String sha256(String s) => crypto.sha256.convert(utf8.encode(s)).toString();

  static String base64Encode(String s) => base64.encode(utf8.encode(s));
  static String base64Decode(String s) => utf8.decode(base64.decode(s));

  /// URL 编码
  static String urlEncode(String s) => Uri.encodeComponent(s);
  static String urlDecode(String s) => Uri.decodeComponent(s);

  /// 生成简单签名：key 按字典序拼接后 MD5
  static String sign(Map<String, String> params, String secret) {
    final keys = params.keys.toList()..sort();
    final buffer = StringBuffer();
    for (final k in keys) {
      buffer.write('$k=${params[k]}&');
    }
    buffer.write('key=$secret');
    return md5(buffer.toString()).toUpperCase();
  }
}
