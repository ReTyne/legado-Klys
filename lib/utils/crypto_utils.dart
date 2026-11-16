/// 纯 Dart 密码学工具库。
///
/// 背景：项目未引入 pointycastle（pub cache 中不存在，纪律禁止新增依赖），
/// 因此本文件以纯 Dart 实现书源脚本所需的全部加解密能力：
///
///   * 摘要：MD2 / MD5 / SHA1 / SHA224 / SHA256 / SHA384 / SHA512 / SM3
///     （MD5/SHA1/SHA224/SHA256/SHA384/SHA512 走 crypto 包与自定义 Hash，
///      MD2/SM3 自行实现）
///   * HMAC：HmacMD5 / HmacSHA1 / HmacSHA224 / HmacSHA256 / HmacSHA384 /
///     HmacSHA512（RFC 2104 自实现，以便复用自定义 Hash）
///   * 对称：AES-128/192/256、DES、3DES(DESede)、RC4、SM4(国密)，
///     模式 ECB / CBC / PCBC / CFB / OFB / CTR，PKCS5/PKCS7、
///     ISO10126 与 NoPadding 填充
///   * 非对称：RSA（PEM 解析 PKCS#1/PKCS#8/SPKI，PKCS#1 v1.5 签名/验签/加解密）
///     EC 暂不支持。
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
    if (t.isEmpty ||
        !RegExp(r'^[A-Za-z0-9+/]+={0,2}$').hasMatch(t) ||
        t.length % 4 != 0) {
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
// SM3（GB/T 32905-2016 国密摘要，输出 32 字节）
// =====================================================================

class _Sm3 {
  _Sm3._();

  static const List<int> _iv = [
    0x7380166f,
    0x4914b2b9,
    0x172442d7,
    0xda8a0600,
    0xa96f30bc,
    0x163138aa,
    0xe38dee4d,
    0xb0fb0e4e,
  ];

  static int _rotl(int x, int n) => ((x << n) | (x >>> (32 - n))) & 0xffffffff;

  static int _tj(int j) => j <= 15 ? 0x79cc4519 : 0x7a879d8a;

  static int _ff(int x, int y, int z, int j) =>
      j <= 15 ? (x ^ y ^ z) : ((x & y) | (x & z) | (y & z));

  static int _gg(int x, int y, int z, int j) =>
      j <= 15 ? (x ^ y ^ z) : ((x & y) | ((~x & 0xffffffff) & z));

  static int _p0(int x) => (x ^ _rotl(x, 9) ^ _rotl(x, 17)) & 0xffffffff;
  static int _p1(int x) => (x ^ _rotl(x, 15) ^ _rotl(x, 23)) & 0xffffffff;

  static Uint8List digest(List<int> input) {
    final data = Uint8List.fromList(input);
    final bitLen = data.length * 8;
    // 填充：0x80 + 若干 0x00 + 8 字节大端 bit 长度，总长为 64 的倍数
    final paddedLen = ((data.length + 9 + 63) ~/ 64) * 64;
    final msg = Uint8List(paddedLen);
    msg.setRange(0, data.length, data);
    msg[data.length] = 0x80;
    for (var i = 0; i < 8; i++) {
      msg[paddedLen - 1 - i] = (bitLen >> (8 * i)) & 0xff;
    }
    final v = List<int>.from(_iv);
    final w = List<int>.filled(68, 0);
    final w1 = List<int>.filled(64, 0);
    for (var off = 0; off < msg.length; off += 64) {
      for (var i = 0; i < 16; i++) {
        w[i] = ((msg[off + i * 4] & 0xff) << 24) |
            ((msg[off + i * 4 + 1] & 0xff) << 16) |
            ((msg[off + i * 4 + 2] & 0xff) << 8) |
            (msg[off + i * 4 + 3] & 0xff);
      }
      for (var j = 16; j < 68; j++) {
        w[j] = (_p1(w[j - 16] ^ w[j - 9] ^ _rotl(w[j - 3], 15)) ^
                _rotl(w[j - 13], 7) ^
                w[j - 6]) &
            0xffffffff;
      }
      for (var j = 0; j < 64; j++) {
        w1[j] = (w[j] ^ w[j + 4]) & 0xffffffff;
      }
      var a = v[0], b = v[1], c = v[2], d = v[3];
      var e = v[4], f = v[5], g = v[6], h = v[7];
      for (var j = 0; j < 64; j++) {
        final ss1 =
            _rotl((_rotl(a, 12) + e + _rotl(_tj(j), j % 32)) & 0xffffffff, 7);
        final ss2 = (ss1 ^ _rotl(a, 12)) & 0xffffffff;
        final tt1 = (_ff(a, b, c, j) + d + ss2 + w1[j]) & 0xffffffff;
        final tt2 = (_gg(e, f, g, j) + h + ss1 + w[j]) & 0xffffffff;
        d = c;
        c = _rotl(b, 9);
        b = a;
        a = tt1;
        h = g;
        g = _rotl(f, 19);
        f = e;
        e = _p0(tt2);
      }
      v[0] = (v[0] ^ a) & 0xffffffff;
      v[1] = (v[1] ^ b) & 0xffffffff;
      v[2] = (v[2] ^ c) & 0xffffffff;
      v[3] = (v[3] ^ d) & 0xffffffff;
      v[4] = (v[4] ^ e) & 0xffffffff;
      v[5] = (v[5] ^ f) & 0xffffffff;
      v[6] = (v[6] ^ g) & 0xffffffff;
      v[7] = (v[7] ^ h) & 0xffffffff;
    }
    final out = Uint8List(32);
    for (var i = 0; i < 8; i++) {
      out[i * 4] = (v[i] >> 24) & 0xff;
      out[i * 4 + 1] = (v[i] >> 16) & 0xff;
      out[i * 4 + 2] = (v[i] >> 8) & 0xff;
      out[i * 4 + 3] = v[i] & 0xff;
    }
    return out;
  }
}

// =====================================================================
// 摘要 / HMAC 归一化与核心（供顶层函数与静态门面共用）
// =====================================================================

const Set<String> _digestAlgorithms = <String>{
  'MD2',
  'MD5',
  'SHA1',
  'SHA224',
  'SHA256',
  'SHA384',
  'SHA512',
  'SM3',
};

const Set<String> _hmacAlgorithms = <String>{
  'MD5',
  'SHA1',
  'SHA224',
  'SHA256',
  'SHA384',
  'SHA512',
};

/// 大小写、连字符、下划线、空白归一化；去掉可选的 Hmac 前缀。
String _normalizeAlgorithm(String algorithm) {
  var name = algorithm.toUpperCase().replaceAll(RegExp(r'[-_\s]'), '');
  if (name.startsWith('HMAC')) name = name.substring(4);
  return name;
}

String _normalizeDigestAlgorithm(String algorithm) {
  final name = _normalizeAlgorithm(algorithm);
  if (!_digestAlgorithms.contains(name)) {
    throw ArgumentError('不支持的摘要算法: $algorithm'
        '（支持 MD2/MD5/SHA1/SHA224/SHA256/SHA384/SHA512/SM3）');
  }
  return name;
}

String _normalizeHmacAlgorithm(String algorithm) {
  final name = _normalizeAlgorithm(algorithm);
  if (!_hmacAlgorithms.contains(name)) {
    throw ArgumentError('不支持的 HMAC 算法: $algorithm'
        '（支持 HmacMD5/HmacSHA1/HmacSHA224/HmacSHA256/HmacSHA384/HmacSHA512）');
  }
  return name;
}

Uint8List _digestCore(String algorithm, List<int> data) {
  final name = _normalizeDigestAlgorithm(algorithm);
  if (name == 'SM3') return _Sm3.digest(data);
  // 复用 sha224.dart 中既有的 simpleHashBytes（MD2/MD5/SHA1/SHA224/SHA256/SHA384/SHA512）
  return simpleHashBytes(name, data);
}

Uint8List _hmacCore(String algorithm, List<int> key, List<int> data) {
  // 复用 sha224.dart 中既有的 RFC 2104 实现
  return hmacBytes(_normalizeHmacAlgorithm(algorithm), key, data);
}

// =====================================================================
// 顶层导出函数（供协议层 / 引擎直接调用）
// =====================================================================

/// 摘要（hex）。[algorithm] 大小写不敏感，可带 Hmac 前缀容错。
String digestHex(String data, String algorithm) =>
    _bytesToHex(_digestCore(algorithm, _utf8Bytes(data)));

/// 摘要（base64）。
String digestBase64(String data, String algorithm) =>
    base64.encode(_digestCore(algorithm, _utf8Bytes(data)));

/// 摘要（字节）。
List<int> digestBytes(List<int> data, String algorithm) =>
    _digestCore(algorithm, data);

/// HMAC（hex）：[data] 明文、[key] 密钥、[algorithm] 如 HmacSHA256。
String hmacHex(String data, String key, String algorithm) =>
    _bytesToHex(_hmacCore(algorithm, _utf8Bytes(key), _utf8Bytes(data)));

/// HMAC（base64）。
String hmacBase64(String data, String key, String algorithm) =>
    base64.encode(_hmacCore(algorithm, _utf8Bytes(key), _utf8Bytes(data)));

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

  /// RSA 验签。签名串统一按 hex 优先解码，兼容 signBase64 / signHex 两种输出。
  static bool verify(
      String algorithm, String publicKey, String data, String signature) {
    return rsaVerifyBytes(
        algorithm, publicKey, _utf8Bytes(data), _autoDecodeData(signature));
  }

  // ---- 供书源网络/协议层使用的门面（新增）----

  /// 摘要（hex）：[data] 明文、[algorithm] 算法名。
  static String digestHex(String data, String algorithm) =>
      _bytesToHex(_digestCore(algorithm, _utf8Bytes(data)));

  /// 摘要（base64）。
  static String digestBase64(String data, String algorithm) =>
      base64.encode(_digestCore(algorithm, _utf8Bytes(data)));

  /// 摘要（字节）。
  static List<int> digestBytes(List<int> data, String algorithm) =>
      _digestCore(algorithm, data);

  /// 非对称加密（hex）：[transformation] 如 "RSA/ECB/PKCS1Padding"，
  /// [key] 为公钥（[usePublicKey] 为 true）或私钥（false）PEM，
  /// [data] 为明文。
  static String asymEncryptHex(String transformation, String key, String data,
      {bool usePublicKey = true}) {
    final crypto = AsymmetricCrypto(transformation,
        publicKey: usePublicKey ? key : null,
        privateKey: usePublicKey ? null : key);
    return crypto.encryptHex(data, usePublicKey: usePublicKey);
  }

  /// RSA 签名（hex）：[algorithm] 如 "SHA256withRSA"，[key] 为私钥 PEM。
  static String signHex(String algorithm, String key, String data) =>
      _bytesToHex(rsaSignBytes(algorithm, key, _utf8Bytes(data)));
}
