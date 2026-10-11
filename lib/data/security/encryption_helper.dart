import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;

/// 本地安全辅助：摘要哈希与可逆编码
class EncryptionHelper {
  EncryptionHelper._();

  static String md5(String input) => crypto.md5.convert(utf8.encode(input)).toString();
  static String sha256(String input) => crypto.sha256.convert(utf8.encode(input)).toString();

  /// 密码校验：明文与已保存哈希比对
  static bool verifyPassword(String plain, String savedHash) =>
      sha256(plain) == savedHash || md5(plain) == savedHash || plain == savedHash;

  /// 对本地敏感数据做 Base64 可逆编码（非强加密，仅避免明文直存）
  static String encode(String plain) => base64.encode(utf8.encode(plain));
  static String decode(String encoded) => utf8.decode(base64.decode(encoded));

  /// 生成带时间戳的简单令牌
  static String token(String seed) => md5('$seed-${DateTime.now().millisecondsSinceEpoch}');
}
