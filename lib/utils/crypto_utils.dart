/// 纯 Dart 密码学工具库。
///
/// 背景：项目未引入 pointycastle（pub cache 中不存在，纪律禁止新增依赖），
/// 因此本文件以纯 Dart 实现书源脚本所需的全部加解密能力：
///
///   * 摘要：MD2 / MD5 / SHA1 / SHA224 / SHA256 / SHA384 / SHA512
///     （MD5/SHA1/SHA256/SHA512 走 crypto 包，MD2/SHA224/SHA384 自行实现）
///   * HMAC：HmacMD5 / HmacSHA1 / HmacSHA256 / HmacSHA512（RFC 2104 自实现，
///     以便复用自定义 Hash）
///   * 对称：AES-128/192/256、DES、3DES(DESede)、RC4、SM4(国密)，
///     模式 ECB / CBC / PCBC / CFB / OFB / CTR，PKCS5/PKCS7 填充
///   * 非对称：RSA（PEM 解析 PKCS#1/PKCS#8/SPKI，PKCS#1 v1.5 签名/验签/加解密）
///     EC 暂缺（见任务报告）。
///
/// 所有输入/输出均使用 Uint8List；字符串按 UTF-8 编解码。
/// 本文件不依赖 Flutter，可在任意 Dart 环境（含单元测试）运行。
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as pc;
part '../help/crypto/md2.dart';
part '../help/crypto/sha224.dart';
part '../help/crypto/block_cipher.dart';
part '../help/crypto/aes_engine.dart';
part '../help/crypto/des_engine.dart';
part '../help/crypto/sm4_engine.dart';
part '../help/crypto/rc4_engine.dart';
part '../help/crypto/symmetric.dart';
part '../help/crypto/rsa.dart';


// =====================================================================
// 通用字节 / 编解码工具
// =====================================================================

Uint8List _utf8Bytes(String s) => Uint8List.fromList(utf8.encode(s));

String _bytesToHex(List<int> bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

/// 十六进制字符串 → 字节；非法返回 null。
Uint8List? _tryHexToBytes(String hex) {
  final h = hex.replaceAll(RegExp(r'\s+'), '');
  if (h.isEmpty || h.length % 2 != 0) return null;
  if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(h)) return null;
  final out = Uint8List(h.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(h.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

bool _looksHex(String s) => _tryHexToBytes(s) != null;


Uint8List? _tryBase64ToBytes(String s) {
  try {
    final t = s.trim();
    if (t.isEmpty || !RegExp(r'^[A-Za-z0-9+/]+={0,2}$').hasMatch(t) || t.length % 4 != 0) {
      return null;
    }
    return Uint8List.fromList(base64.decode(t));
  } catch (_) {
    return null;
  }
}

/// 优先 hex，否则 base64。
Uint8List _autoDecodeData(String data) {
  if (_looksHex(data)) return _tryHexToBytes(data)!;
  final b64 = _tryBase64ToBytes(data);
  if (b64 != null) return b64;
  return _utf8Bytes(data);
}



// =====================================================================
// 静态门面（供 Dart 端 legado://crypto 协议处理与直接调用）
// =====================================================================

/// 密码学统一入口（JS 桥经 legado://crypto 同步 XHR 调用）。
class CryptoUtils {
  CryptoUtils._();

  /// 摘要（hex）：type 支持 MD2/MD5/SHA1/SHA224/SHA256/SHA384/SHA512。
  static String simpleHash(String type, String data) =>
      _bytesToHex(simpleHashBytes(type, _utf8Bytes(data)));

  /// 摘要（base64）。
  static String simpleHashBase64(String type, String data) =>
      base64.encode(simpleHashBytes(type, _utf8Bytes(data)));

  /// HMAC（hex）：type 如 HmacSHA256 / HmacMD5。
  static String hmacHex(String type, String key, String data) =>
      _bytesToHex(hmacBytes(type, _utf8Bytes(key), _utf8Bytes(data)));

  /// HMAC（base64）。
  static String hmacBase64(String type, String key, String data) =>
      base64.encode(hmacBytes(type, _utf8Bytes(key), _utf8Bytes(data)));

  /// 对称加密（字节）。
  static Uint8List symmetricEncrypt(String transformation, dynamic key,
      {dynamic iv, required List<int> data}) {
    return SymmetricCrypto(transformation, key, iv: iv).encrypt(data);
  }

  /// 对称解密（字节，自动识别 hex/base64 输入）。
  static Uint8List symmetricDecrypt(String transformation, dynamic key,
      {dynamic iv, required dynamic data}) {
    return SymmetricCrypto(transformation, key, iv: iv).decrypt(data);
  }

  /// RSA 签名（base64）。
  static String signBase64(String algorithm, String privateKey, String data) =>
      base64.encode(rsaSignBytes(algorithm, privateKey, _utf8Bytes(data)));

  /// RSA 验签。
  static bool verify(String algorithm, String publicKey, String data, String signature) {
    final sig =
        _tryBase64ToBytes(signature) ?? _tryHexToBytes(signature) ?? _utf8Bytes(signature);
    return rsaVerifyBytes(algorithm, publicKey, _utf8Bytes(data), sig);
  }
}
