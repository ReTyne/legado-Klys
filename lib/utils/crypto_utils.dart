/// 纯 Dart 密码学工具库（对齐 legado-E help/JsEncodeUtils.kt + help/crypto/）。
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

String _bytesToBase64(List<int> bytes) => base64.encode(bytes);

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

/// 按 legado SymmetricCrypto 语义解析 String 数据：优先 hex，否则 base64。
Uint8List _autoDecodeData(String data) {
  if (_looksHex(data)) return _tryHexToBytes(data)!;
  final b64 = _tryBase64ToBytes(data);
  if (b64 != null) return b64;
  return _utf8Bytes(data);
}

// =====================================================================
// MD2（RFC 1319）
// =====================================================================

/// MD2 摘要（crypto 包不含 MD2，自行实现）。
class Md2 {
  Md2._();

  /// MD2 S 盒（π 的十六进制数字）。
  static const List<int> _s = [
    41, 46, 67, 201, 162, 216, 124, 1, 61, 54, 84, 161, 236, 240, 6, 19, //
    98, 167, 5, 243, 192, 199, 115, 140, 152, 147, 43, 217, 188, 76, 130, 202, //
    30, 155, 87, 60, 253, 212, 224, 22, 103, 66, 111, 24, 138, 23, 229, 18, //
    190, 78, 196, 214, 218, 158, 79, 101, 77, 9, 1, 242, 62, 125, 131, 139, //
    72, 213, 57, 120, 209, 165, 27, 96, 255, 193, 216, 200, 45, 236, 222, 96, //
    106, 232, 27, 230, 143, 187, 17, 139, 168, 217, 123, 121, 233, 78, 15, 226, //
    56, 197, 12, 244, 146, 229, 233, 55, 7, 82, 56, 251, 148, 178, 187, 39, //
    174, 21, 211, 165, 4, 47, 235, 146, 254, 154, 44, 33, 86, 173, 47, 89, //
    137, 49, 47, 216, 46, 90, 100, 227, 116, 108, 208, 14, 112, 245, 214, 51, //
    49, 88, 66, 176, 41, 225, 166, 81, 129, 193, 100, 228, 94, 29, 229, 173, //
    54, 78, 16, 217, 163, 3, 114, 100, 57, 195, 20, 176, 12, 133, 190, 233, //
    96, 241, 3, 176, 234, 41, 88, 141, 241, 62, 116, 16, 100, 5, 60, 236, //
    77, 166, 166, 6, 0, 34, 209, 220, 66, 233, 220, 106, 164, 3, 180, 205, //
    147, 91, 23, 6, 111, 57, 111, 10, 5, 96, 170, 179, 233, 157, 112, 235, //
    17, 100, 179, 26, 57, 44, 71, 177, 118, 231, 69, 155, 129, 60, 51, 233, //
    113, 109, 7, 87, 1, 33, 234, 100, 234, 75, 44, 43, 100, 227, 208, 254,
  ];

  static Uint8List digest(List<int> input) {
    final data = Uint8List.fromList(input);
    // 1. 填充：先补 i 个 i 字节（i = 16 - (len mod 16)），再补 16 字节校验和
    final padLen = 16 - (data.length % 16);
    final padded = Uint8List(data.length + padLen + 16);
    padded.setRange(0, data.length, data);
    for (var i = 0; i < padLen; i++) {
      padded[data.length + i] = padLen;
    }
    // 2. 16 字节校验和
    final check = List<int>.filled(16, 0);
    var l = 0;
    for (var i = 0; i < data.length + padLen; i += 16) {
      for (var j = 0; j < 16; j++) {
        l = _s[padded[i + j] ^ l];
        check[j] ^= l;
      }
    }
    padded.setRange(data.length + padLen, padded.length, check);
    // 3. 48 字节状态、18 轮混淆
    final x = List<int>.filled(48, 0);
    for (var i = 0; i < padded.length; i += 16) {
      for (var j = 0; j < 16; j++) {
        x[16 + j] = padded[i + j];
        x[32 + j] = x[16 + j] ^ x[j];
      }
      var t = 0;
      for (var j = 0; j < 18; j++) {
        for (var k = 0; k < 48; k++) {
          t = x[k] ^ _s[t];
          x[k] = t;
        }
        t = (t + j) & 0xff;
      }
    }
    return Uint8List.fromList(x.sublist(0, 16));
  }
}

// =====================================================================
// SHA-224（crypto 包未提供，自行实现；SHA-384/512 直接用 crypto 包内置实现）
// =====================================================================

int _rotr32(int x, int n) => ((x >>> n) | (x << (32 - n))) & 0xffffffff;

/// SHA-224（SHA-256 变体：专用 IV，输出 28 字节）。
class Sha224 extends pc.Hash {
  static const List<int> _iv = [
    0xc1059ed8, 0x367cd507, 0x3070dd17, 0xf70e5939, //
    0xffc00b31, 0x68581511, 0x64f98fa7, 0xbefa4fa4,
  ];
  static const List<int> _k = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, //
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, //
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da, //
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, //
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, //
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, //
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, //
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];

  @override
  int get blockSize => 64;

  @override
  pc.Digest convert(List<int> input) {
    final data = Uint8List.fromList(input);
    final h = List<int>.from(_iv);
    final bitLen = data.length * 8;
    final padded = Uint8List(((data.length + 9 + 63) ~/ 64) * 64);
    padded.setRange(0, data.length, data);
    padded[data.length] = 0x80;
    final lenPos = padded.length - 8;
    for (var i = 0; i < 8; i++) {
      padded[lenPos + i] = (bitLen >> (56 - 8 * i)) & 0xff;
    }
    final w = List<int>.filled(64, 0);
    for (var off = 0; off < padded.length; off += 64) {
      for (var i = 0; i < 16; i++) {
        w[i] = (padded[off + i * 4] << 24) |
            (padded[off + i * 4 + 1] << 16) |
            (padded[off + i * 4 + 2] << 8) |
            padded[off + i * 4 + 3];
      }
      for (var i = 16; i < 64; i++) {
        final s0 = _rotr32(w[i - 15], 7) ^ _rotr32(w[i - 15], 18) ^ (w[i - 15] >>> 3);
        final s1 = _rotr32(w[i - 2], 17) ^ _rotr32(w[i - 2], 19) ^ (w[i - 2] >>> 10);
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
      }
      var a = h[0], b = h[1], c = h[2], d = h[3];
      var e = h[4], f = h[5], g = h[6], hh = h[7];
      for (var i = 0; i < 64; i++) {
        final s1 = _rotr32(e, 6) ^ _rotr32(e, 11) ^ _rotr32(e, 25);
        final ch = (e & f) ^ ((~e & 0xffffffff) & g);
        final t1 = (hh + s1 + ch + _k[i] + w[i]) & 0xffffffff;
        final s0 = _rotr32(a, 2) ^ _rotr32(a, 13) ^ _rotr32(a, 22);
        final maj = (a & b) ^ (a & c) ^ (b & c);
        final t2 = (s0 + maj) & 0xffffffff;
        hh = g; g = f; f = e;
        e = (d + t1) & 0xffffffff;
        d = c; c = b; b = a;
        a = (t1 + t2) & 0xffffffff;
      }
      h[0] = (h[0] + a) & 0xffffffff;
      h[1] = (h[1] + b) & 0xffffffff;
      h[2] = (h[2] + c) & 0xffffffff;
      h[3] = (h[3] + d) & 0xffffffff;
      h[4] = (h[4] + e) & 0xffffffff;
      h[5] = (h[5] + f) & 0xffffffff;
      h[6] = (h[6] + g) & 0xffffffff;
      h[7] = (h[7] + hh) & 0xffffffff;
    }
    final out = Uint8List(28);
    for (var i = 0; i < 7; i++) {
      out[i * 4] = (h[i] >> 24) & 0xff;
      out[i * 4 + 1] = (h[i] >> 16) & 0xff;
      out[i * 4 + 2] = (h[i] >> 8) & 0xff;
      out[i * 4 + 3] = h[i] & 0xff;
    }
    return pc.Digest(out);
  }

  @override
  ByteConversionSink startChunkedConversion(Sink<pc.Digest> sink) =>
      _OneShotHashSink(sink, this);
}


/// 简化 ByteConversionSink：收集全部输入后一次性 convert。
class _OneShotHashSink implements ByteConversionSink {
  _OneShotHashSink(this._out, this._hash);
  final Sink<pc.Digest> _out;
  final pc.Hash _hash;
  final List<int> _buf = <int>[];
  bool _closed = false;

  @override
  void add(List<int> chunk) => _buf.addAll(chunk);

  @override
  void addSlice(List<int> chunk, int start, int end, bool isLast) {
    add(chunk.sublist(start, end));
    if (isLast) close();
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _out.add(_hash.convert(_buf));
    _out.close();
  }
}

// =====================================================================
// 摘要 / HMAC 统一入口
// =====================================================================

/// 摘要算法名归一化："SHA-256" → "SHA256"。
String _normalizeHashName(String type) =>
    type.toUpperCase().replaceAll(RegExp(r'[-_\s]'), '');

pc.Hash _hashByName(String type) {
  switch (_normalizeHashName(type)) {
    case 'MD5':
      return pc.md5;
    case 'SHA1':
      return pc.sha1;
    case 'SHA224':
      return Sha224();
    case 'SHA256':
      return pc.sha256;
    case 'SHA384':
      return pc.sha384;
    case 'SHA512':
      return pc.sha512;
    default:
      throw ArgumentError('不支持的摘要算法: $type');
  }
}

bool _isSupportedHash(String type) {
  final t = _normalizeHashName(type);
  return const {'MD2', 'MD5', 'SHA1', 'SHA224', 'SHA256', 'SHA384', 'SHA512'}
      .contains(t);
}

/// 摘要字节输出（支持 MD2/MD5/SHA1/SHA224/SHA256/SHA384/SHA512）。
Uint8List simpleHashBytes(String type, List<int> data) {
  if (_normalizeHashName(type) == 'MD2') return Md2.digest(data);
  return Uint8List.fromList(_hashByName(type).convert(data).bytes);
}

/// HMAC（RFC 2104）：type 支持 HmacMD5/HmacSHA1/HmacSHA256/HmacSHA512
/// （也兼容去掉 "Hmac" 前缀的写法）。
Uint8List hmacBytes(String type, List<int> key, List<int> data) {
  var name = _normalizeHashName(type);
  if (name.startsWith('HMAC')) name = name.substring(4);
  final hash = _hashByName(name);
  final bs = hash.blockSize;
  var k = Uint8List.fromList(key);
  if (k.length > bs) {
    k = Uint8List.fromList(hash.convert(k).bytes);
  }
  final paddedKey = Uint8List(bs)..setRange(0, k.length, k);
  final inner = Uint8List(bs + data.length);
  final innerDigest = Uint8List(hash.convert(<int>[]).bytes.length);
  final outer = Uint8List(bs + innerDigest.length);
  for (var i = 0; i < bs; i++) {
    inner[i] = paddedKey[i] ^ 0x36;
    outer[i] = paddedKey[i] ^ 0x5c;
  }
  inner.setRange(bs, inner.length, data);
  final innerResult = hash.convert(inner).bytes;
  outer.setRange(bs, outer.length, innerResult);
  return Uint8List.fromList(hash.convert(outer).bytes);
}

// =====================================================================
// AES（FIPS-197，128/192/256）
// =====================================================================

abstract class _BlockCipher {
  int get blockSize;
  void encryptBlock(Uint8List input, int inOff, Uint8List output, int outOff);
  void decryptBlock(Uint8List input, int inOff, Uint8List output, int outOff);
}

class _AesEngine implements _BlockCipher {
  _AesEngine(Uint8List key) {
    if (key.length != 16 && key.length != 24 && key.length != 32) {
      throw ArgumentError('AES 密钥长度必须为 16/24/32 字节');
    }
    _key = Uint8List.fromList(key);
    nk = _key.length ~/ 4;
    nr = nk + 6;
    _expandKey();
  }

  late final Uint8List _key;
  late final int nk;
  late final int nr;
  late final List<int> _w; // 轮密钥展开

  static const List<int> _sbox = [
    0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76, //
    0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0, //
    0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15, //
    0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75, //
    0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0, 0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84, //
    0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf, //
    0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8, //
    0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5, 0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2, //
    0xcd, 0x0c, 0x13, 0xec, 0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73, //
    0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb, //
    0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c, 0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79, //
    0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08, //
    0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a, //
    0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e, 0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e, //
    0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf, //
    0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16,
  ];
  static final List<int> _invSbox = _buildInvSbox();

  static List<int> _buildInvSbox() {
    final inv = List<int>.filled(256, 0);
    for (var i = 0; i < 256; i++) {
      inv[_sbox[i]] = i;
    }
    return inv;
  }

  void _expandKey() {
    final totalWords = 4 * (nr + 1);
    _w = List<int>.filled(totalWords * 4, 0);
    for (var i = 0; i < nk; i++) {
      _w[i * 4] = _key[i * 4];
      _w[i * 4 + 1] = _key[i * 4 + 1];
      _w[i * 4 + 2] = _key[i * 4 + 2];
      _w[i * 4 + 3] = _key[i * 4 + 3];
    }
    var rcon = 1;
    for (var i = nk; i < totalWords; i++) {
      final prev = (i - 1) * 4;
      var t0 = _w[prev], t1 = _w[prev + 1], t2 = _w[prev + 2], t3 = _w[prev + 3];
      if (i % nk == 0) {
        // RotWord + SubWord + Rcon
        final nt0 = _sbox[t1] ^ rcon;
        t1 = _sbox[t2];
        t2 = _sbox[t3];
        t3 = _sbox[t0];
        t0 = nt0;
        rcon = _xtime(rcon);
      } else if (nk > 6 && i % nk == 4) {
        t0 = _sbox[t0];
        t1 = _sbox[t1];
        t2 = _sbox[t2];
        t3 = _sbox[t3];
      }
      final base = (i - nk) * 4;
      _w[i * 4] = _w[base] ^ t0;
      _w[i * 4 + 1] = _w[base + 1] ^ t1;
      _w[i * 4 + 2] = _w[base + 2] ^ t2;
      _w[i * 4 + 3] = _w[base + 3] ^ t3;
    }
  }

  static int _xtime(int b) {
    final r = b << 1;
    return (r & 0x100) != 0 ? (r ^ 0x11b) & 0xff : r & 0xff;
  }

  static int _gmul(int a, int b) {
    var p = 0;
    var x = a, y = b;
    for (var i = 0; i < 8; i++) {
      if ((y & 1) != 0) p ^= x;
      y >>= 1;
      x = _xtime(x);
    }
    return p & 0xff;
  }

  @override
  int get blockSize => 16;

  void _addRoundKey(List<int> s, int round) {
    for (var c = 0; c < 4; c++) {
      for (var r = 0; r < 4; r++) {
        s[c * 4 + r] ^= _w[round * 16 + c * 4 + r];
      }
    }
  }

  @override
  void encryptBlock(Uint8List input, int inOff, Uint8List output, int outOff) {
    final s = List<int>.filled(16, 0);
    for (var i = 0; i < 16; i++) {
      s[i] = input[inOff + i];
    }
    _addRoundKey(s, 0);
    for (var round = 1; round <= nr; round++) {
      for (var i = 0; i < 16; i++) {
        s[i] = _sbox[s[i]];
      }
      // ShiftRows（状态按列优先：s[c*4+r] 为第 c 列第 r 行）
      for (var r = 1; r < 4; r++) {
        final row = <int>[];
        for (var c = 0; c < 4; c++) {
          row.add(s[c * 4 + r]);
        }
        for (var c = 0; c < 4; c++) {
          s[c * 4 + r] = row[(c + r) % 4];
        }
      }
      if (round != nr) {
        for (var c = 0; c < 4; c++) {
          final a0 = s[c * 4], a1 = s[c * 4 + 1], a2 = s[c * 4 + 2], a3 = s[c * 4 + 3];
          s[c * 4] = _gmul(a0, 2) ^ _gmul(a1, 3) ^ a2 ^ a3;
          s[c * 4 + 1] = a0 ^ _gmul(a1, 2) ^ _gmul(a2, 3) ^ a3;
          s[c * 4 + 2] = a0 ^ a1 ^ _gmul(a2, 2) ^ _gmul(a3, 3);
          s[c * 4 + 3] = _gmul(a0, 3) ^ a1 ^ a2 ^ _gmul(a3, 2);
        }
      }
      _addRoundKey(s, round);
    }
    for (var i = 0; i < 16; i++) {
      output[outOff + i] = s[i];
    }
  }

  @override
  void decryptBlock(Uint8List input, int inOff, Uint8List output, int outOff) {
    final s = List<int>.filled(16, 0);
    for (var i = 0; i < 16; i++) {
      s[i] = input[inOff + i];
    }
    _addRoundKey(s, nr);
    for (var round = nr - 1; round >= 0; round--) {
      // InvShiftRows
      for (var r = 1; r < 4; r++) {
        final row = <int>[];
        for (var c = 0; c < 4; c++) {
          row.add(s[c * 4 + r]);
        }
        for (var c = 0; c < 4; c++) {
          s[c * 4 + r] = row[(c - r + 4) % 4];
        }
      }
      for (var i = 0; i < 16; i++) {
        s[i] = _invSbox[s[i]];
      }
      _addRoundKey(s, round);
      if (round != 0) {
        for (var c = 0; c < 4; c++) {
          final a0 = s[c * 4], a1 = s[c * 4 + 1], a2 = s[c * 4 + 2], a3 = s[c * 4 + 3];
          s[c * 4] = _gmul(a0, 14) ^ _gmul(a1, 11) ^ _gmul(a2, 13) ^ _gmul(a3, 9);
          s[c * 4 + 1] = _gmul(a0, 9) ^ _gmul(a1, 14) ^ _gmul(a2, 11) ^ _gmul(a3, 13);
          s[c * 4 + 2] = _gmul(a0, 13) ^ _gmul(a1, 9) ^ _gmul(a2, 14) ^ _gmul(a3, 11);
          s[c * 4 + 3] = _gmul(a0, 11) ^ _gmul(a1, 13) ^ _gmul(a2, 9) ^ _gmul(a3, 14);
        }
      }
    }
    for (var i = 0; i < 16; i++) {
      output[outOff + i] = s[i];
    }
  }
}

// =====================================================================
// DES / 3DES（DESede）
// =====================================================================

class _DesEngine implements _BlockCipher {
  _DesEngine(Uint8List key) {
    if (key.length != 8) throw ArgumentError('DES 密钥长度必须为 8 字节');
    _subKeys = _generateSubKeys(key);
  }

  late final List<Uint8List> _subKeys;

  static const List<int> _ip = [
    58, 50, 42, 34, 26, 18, 10, 2, 60, 52, 44, 36, 28, 20, 12, 4, //
    62, 54, 46, 38, 30, 22, 14, 6, 64, 56, 48, 40, 32, 24, 16, 8, //
    57, 49, 41, 33, 25, 17, 9, 1, 59, 51, 43, 35, 27, 19, 11, 3, //
    61, 53, 45, 37, 29, 21, 13, 5, 63, 55, 47, 39, 31, 23, 15, 7,
  ];
  static const List<int> _fp = [
    40, 8, 48, 16, 56, 24, 64, 32, 39, 7, 47, 15, 55, 23, 63, 31, //
    38, 6, 46, 14, 54, 22, 62, 30, 37, 5, 45, 13, 53, 21, 61, 29, //
    36, 4, 44, 12, 52, 20, 60, 28, 35, 3, 43, 11, 51, 19, 59, 27, //
    34, 2, 42, 10, 50, 18, 58, 26, 33, 1, 41, 9, 49, 17, 57, 25,
  ];
  static const List<int> _e = [
    32, 1, 2, 3, 4, 5, 4, 5, 6, 7, 8, 9, 8, 9, 10, 11, 12, 13, //
    12, 13, 14, 15, 16, 17, 16, 17, 18, 19, 20, 21, 20, 21, 22, 23, 24, 25, //
    24, 25, 26, 27, 28, 29, 28, 29, 30, 31, 32, 1,
  ];
  static const List<int> _p = [
    16, 7, 20, 21, 29, 12, 28, 17, 1, 15, 23, 26, 5, 18, 31, 10, //
    2, 8, 24, 14, 32, 27, 3, 9, 19, 13, 30, 6, 22, 11, 4, 25,
  ];
  static const List<int> _pc1 = [
    57, 49, 41, 33, 25, 17, 9, 1, 58, 50, 42, 34, 26, 18, //
    10, 2, 59, 51, 43, 35, 27, 19, 11, 3, 60, 52, 44, 36, //
    63, 55, 47, 39, 31, 23, 15, 7, 62, 54, 46, 38, 30, 22, //
    14, 6, 61, 53, 45, 37, 29, 21, 13, 5, 28, 20, 12, 4,
  ];
  static const List<int> _pc2 = [
    14, 17, 11, 24, 1, 5, 3, 28, 15, 6, 21, 10, //
    23, 19, 12, 4, 26, 8, 16, 7, 27, 20, 13, 2, //
    41, 52, 31, 37, 47, 55, 30, 40, 51, 45, 33, 48, //
    44, 49, 39, 56, 34, 53, 46, 42, 50, 36, 29, 32,
  ];
  static const List<int> _shifts = [
    1, 1, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2, 2, 2, 1,
  ];
  static const List<List<int>> _sboxes = [
    // S1
    [14, 4, 13, 1, 2, 15, 11, 8, 3, 10, 6, 12, 5, 9, 0, 7, //
     0, 15, 7, 4, 14, 2, 13, 1, 10, 6, 12, 11, 9, 5, 3, 8, //
     4, 1, 14, 8, 13, 6, 2, 11, 15, 12, 9, 7, 3, 10, 5, 0, //
     15, 12, 8, 2, 4, 9, 1, 7, 5, 11, 3, 14, 10, 0, 6, 13],
    // S2
    [15, 1, 8, 14, 6, 11, 3, 4, 9, 7, 2, 13, 12, 0, 5, 10, //
     3, 13, 4, 7, 15, 2, 8, 14, 12, 0, 1, 10, 6, 9, 11, 5, //
     0, 14, 7, 11, 10, 4, 13, 1, 5, 8, 12, 6, 9, 3, 2, 15, //
     13, 8, 10, 1, 3, 15, 4, 2, 11, 6, 7, 12, 0, 5, 14, 9],
    // S3
    [10, 0, 9, 14, 6, 3, 15, 5, 1, 13, 12, 7, 11, 4, 2, 8, //
     13, 7, 0, 9, 3, 4, 6, 10, 2, 8, 5, 14, 12, 11, 15, 1, //
     13, 6, 4, 9, 8, 15, 3, 0, 11, 1, 2, 12, 5, 10, 14, 7, //
     1, 10, 13, 0, 6, 9, 8, 7, 4, 15, 14, 3, 11, 5, 2, 12],
    // S4
    [7, 13, 14, 3, 0, 6, 9, 10, 1, 2, 8, 5, 11, 12, 4, 15, //
     13, 8, 11, 5, 6, 15, 0, 3, 4, 7, 2, 12, 1, 10, 14, 9, //
     10, 6, 9, 0, 12, 11, 7, 13, 15, 1, 3, 14, 5, 2, 8, 4, //
     3, 15, 0, 6, 10, 1, 13, 8, 9, 4, 5, 11, 12, 7, 2, 14],
    // S5
    [2, 12, 4, 1, 7, 10, 11, 6, 8, 5, 3, 15, 13, 0, 14, 9, //
     14, 11, 2, 12, 4, 7, 13, 1, 5, 0, 15, 10, 3, 9, 8, 6, //
     4, 2, 1, 11, 10, 13, 7, 8, 15, 9, 12, 5, 6, 3, 0, 14, //
     11, 8, 12, 7, 1, 14, 2, 13, 6, 15, 0, 9, 10, 4, 5, 3],
    // S6
    [12, 1, 10, 15, 9, 2, 6, 8, 0, 13, 3, 4, 14, 7, 5, 11, //
     10, 15, 4, 2, 7, 12, 9, 5, 6, 1, 13, 14, 0, 11, 3, 8, //
     9, 14, 15, 5, 2, 8, 12, 3, 7, 0, 4, 10, 1, 13, 11, 6, //
     4, 3, 2, 12, 9, 5, 15, 10, 11, 14, 1, 7, 6, 0, 8, 13],
    // S7
    [4, 11, 2, 14, 15, 0, 8, 13, 3, 12, 9, 7, 5, 10, 6, 1, //
     13, 0, 11, 7, 4, 9, 1, 10, 14, 3, 5, 12, 2, 15, 8, 6, //
     1, 4, 11, 13, 12, 3, 7, 14, 10, 15, 6, 8, 0, 5, 9, 2, //
     6, 11, 13, 8, 1, 4, 10, 7, 9, 5, 0, 15, 14, 2, 3, 12],
    // S8
    [13, 2, 8, 4, 6, 15, 11, 1, 10, 9, 3, 14, 5, 0, 12, 7, //
     1, 15, 13, 8, 10, 3, 7, 4, 12, 5, 6, 11, 0, 14, 9, 2, //
     7, 11, 4, 1, 9, 12, 14, 2, 0, 6, 10, 13, 15, 3, 5, 8, //
     2, 1, 14, 7, 4, 10, 8, 13, 15, 12, 9, 0, 3, 5, 6, 11],
  ];

  static List<Uint8List> _generateSubKeys(Uint8List key) {
    // 密钥位序列（MSB 优先）
    final bits = List<int>.filled(64, 0);
    for (var i = 0; i < 64; i++) {
      bits[i] = (key[i ~/ 8] >> (7 - (i % 8))) & 1;
    }
    var c = List<int>.filled(28, 0);
    var d = List<int>.filled(28, 0);
    for (var i = 0; i < 28; i++) {
      c[i] = bits[_pc1[i] - 1];
      d[i] = bits[_pc1[i + 28] - 1];
    }
    final keys = <Uint8List>[];
    for (var round = 0; round < 16; round++) {
      final s = _shifts[round];
      c = [...c.sublist(s), ...c.sublist(0, s)];
      d = [...d.sublist(s), ...d.sublist(0, s)];
      final cd = [...c, ...d];
      final sub = Uint8List(48);
      for (var i = 0; i < 48; i++) {
        sub[i] = cd[_pc2[i] - 1];
      }
      keys.add(sub);
    }
    return keys;
  }

  static void _feistel(List<int> r, List<int> subKey, List<int> out) {
    // 扩展 32 → 48 并与子密钥异或
    final x = List<int>.filled(48, 0);
    for (var i = 0; i < 48; i++) {
      x[i] = r[_e[i] - 1] ^ subKey[i];
    }
    // S 盒替换 48 → 32
    final sOut = List<int>.filled(32, 0);
    for (var i = 0; i < 8; i++) {
      final row = (x[i * 6] << 1) | x[i * 6 + 5];
      final col = (x[i * 6 + 1] << 3) | (x[i * 6 + 2] << 2) | (x[i * 6 + 3] << 1) | x[i * 6 + 4];
      final v = _sboxes[i][row * 16 + col];
      sOut[i * 4] = (v >> 3) & 1;
      sOut[i * 4 + 1] = (v >> 2) & 1;
      sOut[i * 4 + 2] = (v >> 1) & 1;
      sOut[i * 4 + 3] = v & 1;
    }
    // P 置换
    for (var i = 0; i < 32; i++) {
      out[i] = sOut[_p[i] - 1];
    }
  }

  @override
  int get blockSize => 8;

  void _crypt(Uint8List input, int inOff, Uint8List output, int outOff, bool encrypt) {
    final block = Uint8List(8);
    for (var i = 0; i < 8; i++) {
      block[i] = input[inOff + i];
    }
    final bits = List<int>.filled(64, 0);
    for (var i = 0; i < 64; i++) {
      bits[i] = (block[i ~/ 8] >> (7 - (i % 8))) & 1;
    }
    final ipBits = List<int>.filled(64, 0);
    for (var i = 0; i < 64; i++) {
      ipBits[i] = bits[_ip[i] - 1];
    }
    var l = List<int>.filled(32, 0);
    var r = List<int>.filled(32, 0);
    for (var i = 0; i < 32; i++) {
      l[i] = ipBits[i];
      r[i] = ipBits[32 + i];
    }
    for (var round = 0; round < 16; round++) {
      final subKey = encrypt ? _subKeys[round] : _subKeys[15 - round];
      final f = List<int>.filled(32, 0);
      _feistel(r, subKey, f);
      final newR = List<int>.filled(32, 0);
      for (var i = 0; i < 32; i++) {
        newR[i] = l[i] ^ f[i];
      }
      l = r;
      r = newR;
    }
    // 末轮不交换：R16 || L16 经 FP 输出
    final preOutput = [...r, ...l];
    final fpBits = List<int>.filled(64, 0);
    for (var i = 0; i < 64; i++) {
      fpBits[i] = preOutput[_fp[i] - 1];
    }
    for (var i = 0; i < 8; i++) {
      var b = 0;
      for (var j = 0; j < 8; j++) {
        b = (b << 1) | fpBits[i * 8 + j];
      }
      output[outOff + i] = b;
    }
  }

  @override
  void encryptBlock(Uint8List input, int inOff, Uint8List output, int outOff) =>
      _crypt(input, inOff, output, outOff, true);

  @override
  void decryptBlock(Uint8List input, int inOff, Uint8List output, int outOff) =>
      _crypt(input, inOff, output, outOff, false);
}

/// 3DES（DESede EDE 模式）：24 字节密钥（16 字节时 K3=K1）。
class _Des3Engine implements _BlockCipher {
  _Des3Engine(Uint8List key) {
    var k = Uint8List.fromList(key);
    if (k.length == 16) {
      final full = Uint8List(24);
      full.setRange(0, 16, k);
      full.setRange(16, 24, k.sublist(0, 8));
      k = full;
    }
    if (k.length != 24) throw ArgumentError('3DES 密钥长度必须为 16/24 字节');
    _k1 = _DesEngine(k.sublist(0, 8));
    _k2 = _DesEngine(k.sublist(8, 16));
    _k3 = _DesEngine(k.sublist(16, 24));
  }

  late final _DesEngine _k1;
  late final _DesEngine _k2;
  late final _DesEngine _k3;

  @override
  int get blockSize => 8;

  @override
  void encryptBlock(Uint8List input, int inOff, Uint8List output, int outOff) {
    final t = Uint8List(8);
    _k1.encryptBlock(input, inOff, t, 0);
    final t2 = Uint8List(8);
    _k2.decryptBlock(t, 0, t2, 0);
    _k3.encryptBlock(t2, 0, output, outOff);
  }

  @override
  void decryptBlock(Uint8List input, int inOff, Uint8List output, int outOff) {
    final t = Uint8List(8);
    _k3.decryptBlock(input, inOff, t, 0);
    final t2 = Uint8List(8);
    _k2.encryptBlock(t, 0, t2, 0);
    _k1.decryptBlock(t2, 0, output, outOff);
  }
}

// =====================================================================
// SM4（GB/T 32907-2016 国密分组密码）
// =====================================================================

class _Sm4Engine implements _BlockCipher {
  _Sm4Engine(Uint8List key) {
    if (key.length != 16) throw ArgumentError('SM4 密钥长度必须为 16 字节');
    _rk = _keyExpansion(key);
  }

  late final List<int> _rk; // 32 个轮密钥（32 位字）

  static const List<int> _sbox = [
    0xd6, 0x90, 0xe9, 0xfe, 0xcc, 0xe1, 0x3d, 0xb7, 0x16, 0xb6, 0x14, 0xc2, 0x28, 0xfb, 0x2c, 0x05, //
    0x2b, 0x67, 0x9a, 0x76, 0x2a, 0xbe, 0x04, 0xc3, 0xaa, 0x44, 0x13, 0x26, 0x49, 0x86, 0x06, 0x99, //
    0x9c, 0x42, 0x50, 0xf4, 0x91, 0xef, 0x98, 0x7a, 0x33, 0x54, 0x0b, 0x43, 0xed, 0xcf, 0xac, 0x62, //
    0xe4, 0xb3, 0x1c, 0xa9, 0xc9, 0x08, 0xe8, 0x95, 0x80, 0xdf, 0x94, 0xfa, 0x75, 0x8f, 0x3f, 0xa6, //
    0x47, 0x07, 0xa7, 0xfc, 0xf3, 0x73, 0x17, 0xba, 0x83, 0x59, 0x3c, 0x19, 0xe6, 0x85, 0x4f, 0xa8, //
    0x68, 0x6b, 0x81, 0xb2, 0x71, 0x64, 0xda, 0x8b, 0xf8, 0xeb, 0x0f, 0x4b, 0x70, 0x56, 0x9d, 0x35, //
    0x1e, 0x24, 0x0e, 0x5e, 0x63, 0x58, 0xd1, 0xa2, 0x25, 0x22, 0x7c, 0x3b, 0x01, 0x21, 0x78, 0x87, //
    0xd4, 0x00, 0x46, 0x57, 0x9f, 0xd3, 0x27, 0x52, 0x4c, 0x36, 0x02, 0xe7, 0xa0, 0xc4, 0xc8, 0x9e, //
    0xea, 0xbf, 0x8a, 0xd2, 0x40, 0xc7, 0x38, 0xb5, 0xa3, 0xf7, 0xf2, 0xce, 0xf9, 0x61, 0x15, 0xa1, //
    0xe0, 0xae, 0x5d, 0xa4, 0x9b, 0x34, 0x1a, 0x55, 0xad, 0x93, 0x32, 0x30, 0xf5, 0x8c, 0xb1, 0xe3, //
    0x1d, 0xf6, 0xe2, 0x2e, 0x82, 0x66, 0xca, 0x60, 0xc0, 0x29, 0x23, 0xab, 0x0d, 0x53, 0x4e, 0x6f, //
    0xd5, 0xdb, 0x37, 0x45, 0xde, 0xfd, 0x8e, 0x2f, 0x03, 0xff, 0x6a, 0x72, 0x6d, 0x6c, 0x5b, 0x51, //
    0x8d, 0x1b, 0xaf, 0x92, 0xbb, 0xdd, 0xbc, 0x7f, 0x11, 0xd9, 0x5c, 0x41, 0x1f, 0x10, 0x5a, 0xd8, //
    0x0a, 0xc1, 0x31, 0x88, 0xa5, 0xcd, 0x7b, 0xbd, 0x2d, 0x74, 0xd0, 0x12, 0xb8, 0xe5, 0xb4, 0xb0, //
    0x89, 0x69, 0x97, 0x4a, 0x0c, 0x96, 0x77, 0x7e, 0x65, 0xb9, 0xf1, 0x09, 0xc5, 0x6e, 0xc6, 0x84, //
    0x18, 0xf0, 0x7d, 0xec, 0x3a, 0xdc, 0x4d, 0x20, 0x79, 0xee, 0x5f, 0x3e, 0xd7, 0xcb, 0x39, 0x48,
  ];
  static const List<int> _fk = [
    0xa3b1bac6, 0x56aa3350, 0x677d9197, 0xb27022dc,
  ];
  static final List<int> _ck = List<int>.generate(128, (i) {
    // CK[i] 四个字节依次为 7*(4i+j) mod 256
    var v = 0;
    for (var j = 0; j < 4; j++) {
      v = (v << 8) | ((7 * (4 * i + j)) & 0xff);
    }
    return v;
  });

  static int _rotl32(int x, int n) => ((x << n) | (x >>> (32 - n))) & 0xffffffff;

  static int _tau(int a) =>
      (_sbox[(a >>> 24) & 0xff] << 24) |
      (_sbox[(a >>> 16) & 0xff] << 16) |
      (_sbox[(a >>> 8) & 0xff] << 8) |
      _sbox[a & 0xff];

  List<int> _keyExpansion(Uint8List key) {
    var k0 = ((key[0] << 24) | (key[1] << 16) | (key[2] << 8) | key[3]) ^ _fk[0];
    var k1 = ((key[4] << 24) | (key[5] << 16) | (key[6] << 8) | key[7]) ^ _fk[1];
    var k2 = ((key[8] << 24) | (key[9] << 16) | (key[10] << 8) | key[11]) ^ _fk[2];
    var k3 = ((key[12] << 24) | (key[13] << 16) | (key[14] << 8) | key[15]) ^ _fk[3];
    final rk = <int>[];
    final ks = <int>[k0, k1, k2, k3];
    for (var i = 0; i < 32; i++) {
      final x = ks[i + 1] ^ ks[i + 2] ^ ks[i + 3] ^ _ck[i];
      final t = _tau(x);
      // L'(B) = B ⊕ (B<<<13) ⊕ (B<<<23)
      final rkI = ks[i] ^ t ^ _rotl32(t, 13) ^ _rotl32(t, 23);
      ks.add(rkI);
      rk.add(rkI);
    }
    return rk;
  }

  @override
  int get blockSize => 16;

  void _crypt(Uint8List input, int inOff, Uint8List output, int outOff, bool encrypt) {
    var x0 = (input[inOff] << 24) | (input[inOff + 1] << 16) | (input[inOff + 2] << 8) | input[inOff + 3];
    var x1 = (input[inOff + 4] << 24) | (input[inOff + 5] << 16) | (input[inOff + 6] << 8) | input[inOff + 7];
    var x2 = (input[inOff + 8] << 24) | (input[inOff + 9] << 16) | (input[inOff + 10] << 8) | input[inOff + 11];
    var x3 = (input[inOff + 12] << 24) | (input[inOff + 13] << 16) | (input[inOff + 14] << 8) | input[inOff + 15];
    for (var i = 0; i < 32; i++) {
      final rkI = encrypt ? _rk[i] : _rk[31 - i];
      final x = x1 ^ x2 ^ x3 ^ rkI;
      final t = _tau(x);
      // L(B) = B ⊕ (B<<<2) ⊕ (B<<<10) ⊕ (B<<<18) ⊕ (B<<<24)
      final fx = x0 ^ t ^ _rotl32(t, 2) ^ _rotl32(t, 10) ^ _rotl32(t, 18) ^ _rotl32(t, 24);
      x0 = x1; x1 = x2; x2 = x3; x3 = fx;
    }
    final words = [x3, x2, x1, x0]; // 反序输出
    for (var i = 0; i < 4; i++) {
      output[outOff + i * 4] = (words[i] >> 24) & 0xff;
      output[outOff + i * 4 + 1] = (words[i] >> 16) & 0xff;
      output[outOff + i * 4 + 2] = (words[i] >> 8) & 0xff;
      output[outOff + i * 4 + 3] = words[i] & 0xff;
    }
  }

  @override
  void encryptBlock(Uint8List input, int inOff, Uint8List output, int outOff) =>
      _crypt(input, inOff, output, outOff, true);

  @override
  void decryptBlock(Uint8List input, int inOff, Uint8List output, int outOff) =>
      _crypt(input, inOff, output, outOff, false);
}

// =====================================================================
// RC4（流密码）
// =====================================================================

class _Rc4Engine {
  _Rc4Engine(Uint8List key) {
    if (key.isEmpty || key.length > 256) {
      throw ArgumentError('RC4 密钥长度须在 1..256 字节');
    }
    _s = List<int>.generate(256, (i) => i);
    var j = 0;
    for (var i = 0; i < 256; i++) {
      j = (j + _s[i] + key[i % key.length]) & 0xff;
      final t = _s[i];
      _s[i] = _s[j];
      _s[j] = t;
    }
  }

  late final List<int> _s;
  int _i = 0;
  int _j = 0;

  void process(Uint8List data, int off, int len, Uint8List out, int outOff) {
    for (var k = 0; k < len; k++) {
      _i = (_i + 1) & 0xff;
      _j = (_j + _s[_i]) & 0xff;
      final t = _s[_i];
      _s[_i] = _s[_j];
      _s[_j] = t;
      final ks = _s[(_s[_i] + _s[_j]) & 0xff];
      out[outOff + k] = data[off + k] ^ ks;
    }
  }
}

// =====================================================================
// 分组密码模式（ECB/CBC/PCBC/CFB/OFB/CTR）
// =====================================================================

enum _Mode { ecb, cbc, pcbc, cfb, ofb, ctr }

/// 应用分组模式。ECB/CBC/PCBC 要求数据按块对齐；CFB/OFB/CTR 按流处理。
Uint8List _applyMode(
    _BlockCipher cipher, _Mode mode, Uint8List? iv, Uint8List data, bool encrypt) {
  final bs = cipher.blockSize;
  final out = Uint8List(data.length);
  final streamModes = mode == _Mode.cfb || mode == _Mode.ofb || mode == _Mode.ctr;
  if (!streamModes && data.length % bs != 0) {
    throw ArgumentError('数据长度必须是块大小 $bs 的倍数');
  }
  if (mode != _Mode.ecb && (iv == null || iv.length != bs)) {
    throw ArgumentError('模式 ${mode.name.toUpperCase()} 需要 $bs 字节 IV');
  }

  switch (mode) {
    case _Mode.ecb:
      for (var off = 0; off < data.length; off += bs) {
        if (encrypt) {
          cipher.encryptBlock(data, off, out, off);
        } else {
          cipher.decryptBlock(data, off, out, off);
        }
      }
      return out;

    case _Mode.cbc:
      final prevC = Uint8List.fromList(iv!);
      for (var off = 0; off < data.length; off += bs) {
        if (encrypt) {
          for (var i = 0; i < bs; i++) {
            out[off + i] = data[off + i] ^ prevC[i];
          }
          cipher.encryptBlock(out, off, out, off);
          prevC.setRange(0, bs, out.sublist(off, off + bs));
        } else {
          final dec = Uint8List(bs);
          cipher.decryptBlock(data, off, dec, 0);
          for (var i = 0; i < bs; i++) {
            out[off + i] = dec[i] ^ prevC[i];
          }
          prevC.setRange(0, bs, data.sublist(off, off + bs));
        }
      }
      return out;

    case _Mode.pcbc:
      final prevC = Uint8List.fromList(iv!);
      // PCBC：明文与上一密文、上一明文异或；首个块上一明文为 0
      final prevP = Uint8List(bs);
      for (var off = 0; off < data.length; off += bs) {
        if (encrypt) {
          for (var i = 0; i < bs; i++) {
            out[off + i] = data[off + i] ^ prevC[i] ^ prevP[i];
          }
          cipher.encryptBlock(out, off, out, off);
          prevC.setRange(0, bs, out.sublist(off, off + bs));
          prevP.setRange(0, bs, data.sublist(off, off + bs));
        } else {
          final dec = Uint8List(bs);
          cipher.decryptBlock(data, off, dec, 0);
          for (var i = 0; i < bs; i++) {
            out[off + i] = dec[i] ^ prevC[i] ^ prevP[i];
          }
          prevC.setRange(0, bs, data.sublist(off, off + bs));
          prevP.setRange(0, bs, out.sublist(off, off + bs));
        }
      }
      return out;

    case _Mode.cfb:
      final prev = Uint8List.fromList(iv!);
      for (var off = 0; off < data.length; off += bs) {
        final len = (off + bs <= data.length) ? bs : data.length - off;
        final ks = Uint8List(bs);
        cipher.encryptBlock(prev, 0, ks, 0);
        for (var i = 0; i < len; i++) {
          out[off + i] = data[off + i] ^ ks[i];
        }
        final next = Uint8List(bs);
        next.setRange(0, len, out.sublist(off, off + len));
        next.setRange(len, bs, prev.sublist(len, bs));
        prev.setRange(0, bs, next);
      }
      return out;

    case _Mode.ofb:
      final prev = Uint8List.fromList(iv!);
      for (var off = 0; off < data.length; off += bs) {
        final len = (off + bs <= data.length) ? bs : data.length - off;
        final ks = Uint8List(bs);
        cipher.encryptBlock(prev, 0, ks, 0);
        for (var i = 0; i < len; i++) {
          out[off + i] = data[off + i] ^ ks[i];
        }
        prev.setRange(0, bs, ks);
      }
      return out;

    case _Mode.ctr:
      final counter = Uint8List.fromList(iv!);
      for (var off = 0; off < data.length; off += bs) {
        final len = (off + bs <= data.length) ? bs : data.length - off;
        final ks = Uint8List(bs);
        cipher.encryptBlock(counter, 0, ks, 0);
        for (var i = 0; i < len; i++) {
          out[off + i] = data[off + i] ^ ks[i];
        }
        // 计数器按大端自增
        for (var i = bs - 1; i >= 0; i--) {
          counter[i] = (counter[i] + 1) & 0xff;
          if (counter[i] != 0) break;
        }
      }
      return out;
  }
}

// =====================================================================
// PKCS#5/PKCS7 填充
// =====================================================================

Uint8List _padPkcs7(Uint8List data, int blockSize) {
  final pad = blockSize - (data.length % blockSize);
  final out = Uint8List(data.length + pad);
  out.setRange(0, data.length, data);
  for (var i = data.length; i < out.length; i++) {
    out[i] = pad;
  }
  return out;
}

Uint8List _unpadPkcs7(Uint8List data, int blockSize) {
  if (data.isEmpty) return data;
  final p = data[data.length - 1];
  if (p < 1 || p > blockSize || p > data.length) return data;
  for (var i = data.length - p; i < data.length; i++) {
    if (data[i] != p) return data;
  }
  return Uint8List.fromList(data.sublist(0, data.length - p));
}

// =====================================================================
// 分组密钥归一化（对齐 legado 既有 JS 桥策略）
// =====================================================================

Uint8List _normalizeKey(String algorithm, List<int> key) {
  int take(int n) => key.length > n ? n : key.length;
  switch (algorithm) {
    case 'AES':
      const sizes = [16, 24, 32];
      for (final s in sizes) {
        if (key.length <= s) {
          final out = Uint8List(s);
          out.setRange(0, key.length, key);
          return out;
        }
      }
      return Uint8List.fromList(key.sublist(0, 32));
    case 'DES':
      final out = Uint8List(8);
      out.setRange(0, take(8), key);
      return out;
    case 'DESEDE':
      final out = Uint8List(24);
      out.setRange(0, take(24), key);
      return out;
    case 'SM4':
      final out = Uint8List(16);
      out.setRange(0, take(16), key);
      return out;
    default:
      return Uint8List.fromList(key);
  }
}

// =====================================================================
// transformation 解析
// =====================================================================

class _Transformation {
  _Transformation(String transformation) {
    final parts = transformation.toUpperCase().split('/');
    var alg = parts[0].trim();
    if (alg == '3DES' || alg == 'TRIPLEDES' || alg == 'DESEDE') alg = 'DESEDE';
    if (alg == 'SMS4') alg = 'SM4';
    if (alg == 'ARCFOUR') alg = 'RC4';
    if (!const {'AES', 'DES', 'DESEDE', 'RC4', 'SM4'}.contains(alg)) {
      throw ArgumentError('不支持的对称算法: ${parts[0]}');
    }
    algorithm = alg;
    mode = parts.length > 1 ? parts[1].trim() : 'ECB';
    if (!const {'ECB', 'CBC', 'PCBC', 'CFB', 'OFB', 'CTR'}.contains(mode)) {
      throw ArgumentError('不支持的分组模式: ${parts[1]}');
    }
    final padding = parts.length > 2 ? parts[2].trim() : 'PKCS5PADDING';
    if (!const {'PKCS5PADDING', 'PKCS7PADDING', 'NOPADDING', 'ISO10126PADDING'}
        .contains(padding)) {
      throw ArgumentError('不支持的填充方式: ${parts[2]}');
    }
    // 流模式（CFB/OFB/CTR/RC4）不应用块填充
    padded = mode != 'CFB' && mode != 'OFB' && mode != 'CTR' && alg != 'RC4' &&
        padding != 'NOPADDING';
  }

  late final String algorithm;
  late final String mode;
  late final bool padded;
}

_BlockCipher _createCipher(_Transformation t, Uint8List key) {
  switch (t.algorithm) {
    case 'AES':
      return _AesEngine(key);
    case 'DES':
      return _DesEngine(key);
    case 'DESEDE':
      return _Des3Engine(key);
    case 'SM4':
      return _Sm4Engine(key);
    default:
      throw ArgumentError('未知算法');
  }
}

_Mode _parseMode(String mode) {
  switch (mode) {
    case 'ECB':
      return _Mode.ecb;
    case 'CBC':
      return _Mode.cbc;
    case 'PCBC':
      return _Mode.pcbc;
    case 'CFB':
      return _Mode.cfb;
    case 'OFB':
      return _Mode.ofb;
    case 'CTR':
      return _Mode.ctr;
    default:
      throw ArgumentError('未知模式: $mode');
  }
}

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

// =====================================================================
// RSA（PEM 解析 + PKCS#1 v1.5 签名/验签/加解密）
// =====================================================================

class _RsaPrivateKey {
  _RsaPrivateKey(this.n, this.e, this.d);
  final BigInt n;
  final BigInt e;
  final BigInt d;
  int get byteLength => (n.bitLength + 7) ~/ 8;
}

class _RsaPublicKey {
  _RsaPublicKey(this.n, this.e);
  final BigInt n;
  final BigInt e;
  int get byteLength => (n.bitLength + 7) ~/ 8;
}

/// 极简 DER 解析器（TLV）。
class _Der {
  _Der(this.tag, this.value);
  final int tag;
  final List<int> value;

  List<_Der> children() {
    final out = <_Der>[];
    var i = 0;
    while (i < value.length) {
      final t = value[i++];
      if (i >= value.length) break;
      var len = value[i++];
      if (len & 0x80 != 0) {
        final n = len & 0x7f;
        if (n == 0 || i + n > value.length) break;
        len = 0;
        for (var j = 0; j < n; j++) {
          len = (len << 8) | value[i++];
        }
      }
      if (i + len > value.length) break;
      out.add(_Der(t, value.sublist(i, i + len)));
      i += len;
    }
    return out;
  }

  BigInt asBigInt() {
    var v = BigInt.zero;
    for (final b in value) {
      v = (v << 8) | BigInt.from(b);
    }
    return v;
  }
}

_Der _derParse(Uint8List der) {
  final t = der[0];
  var i = 1;
  var len = der[i++];
  if (len & 0x80 != 0) {
    final n = len & 0x7f;
    len = 0;
    for (var j = 0; j < n; j++) {
      len = (len << 8) | der[i++];
    }
  }
  if (i + len > der.length) {
    throw const FormatException('DER 长度非法');
  }
  return _Der(t, der.sublist(i, i + len));
}

Uint8List _pemToDer(String pem, String label) {
  final re = RegExp('-----BEGIN $label-----(.*?)-----END $label-----',
      caseSensitive: false, dotAll: true);
  final m = re.firstMatch(pem);
  if (m == null) throw FormatException('PEM 中未找到 $label');
  final body = m.group(1)!.replaceAll(RegExp(r'\s+'), '');
  return Uint8List.fromList(base64.decode(body));
}

/// 解析 RSA 私钥 PEM（支持 PKCS#1 "RSA PRIVATE KEY" 与 PKCS#8 "PRIVATE KEY"）。
_RsaPrivateKey _parsePrivateKey(String pem) {
  final p = pem.trim();
  _Der seq;
  if (p.contains('BEGIN PRIVATE KEY')) {
    final der = _derParse(_pemToDer(p, 'PRIVATE KEY'));
    final children = der.children();
    // PKCS#8: SEQUENCE { INTEGER version, SEQUENCE alg, OCTET STRING pkcs1 }
    if (children.length >= 3 && children[2].tag == 0x04) {
      seq = _derParse(Uint8List.fromList(children[2].value));
    } else {
      seq = der;
    }
  } else if (p.contains('BEGIN RSA PRIVATE KEY')) {
    seq = _derParse(_pemToDer(p, 'RSA PRIVATE KEY'));
  } else {
    // 容错：整体按 base64/DER 解析
    try {
      seq = _derParse(_pemToDer(p, 'PRIVATE KEY'));
    } catch (_) {
      try {
        seq = _derParse(_pemToDer(p, 'RSA PRIVATE KEY'));
      } catch (_) {
        final raw = _tryBase64ToBytes(p.replaceAll(RegExp(r'\s+'), '')) ?? _utf8Bytes(p);
        seq = _derParse(raw);
      }
    }
  }
  final fields = seq.children();
  if (fields.length < 4) throw const FormatException('RSA 私钥格式错误');
  // version, n, e, d
  return _RsaPrivateKey(fields[1].asBigInt(), fields[2].asBigInt(), fields[3].asBigInt());
}

/// 解析 RSA 公钥 PEM（支持 SPKI "PUBLIC KEY" 与 PKCS#1 "RSA PUBLIC KEY"）。
_RsaPublicKey _parsePublicKey(String pem) {
  final p = pem.trim();
  _Der seq;
  if (p.contains('BEGIN RSA PUBLIC KEY')) {
    seq = _derParse(_pemToDer(p, 'RSA PUBLIC KEY'));
  } else {
    final der = _derParse(_pemToDer(p, 'PUBLIC KEY'));
    final children = der.children();
    // SPKI: SEQUENCE { SEQUENCE alg, BIT STRING }
    if (children.length >= 2 && children[1].tag == 0x03) {
      final bitStr = children[1].value;
      // BIT STRING 首字节为未使用位数，跳过
      seq = _derParse(Uint8List.fromList(bitStr.sublist(1)));
    } else {
      seq = der;
    }
  }
  final fields = seq.children();
  if (fields.length < 2) throw const FormatException('RSA 公钥格式错误');
  return _RsaPublicKey(fields[0].asBigInt(), fields[1].asBigInt());
}

/// DigestInfo 前缀（PKCS#1 v1.5）。
const Map<String, List<int>> _digestInfoPrefix = {
  'MD5': [0x30, 0x20, 0x30, 0x0c, 0x06, 0x08, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x02, 0x05, 0x05, 0x00, 0x04, 0x10],
  'SHA1': [0x30, 0x21, 0x30, 0x09, 0x06, 0x05, 0x2b, 0x0e, 0x03, 0x02, 0x1a, 0x05, 0x00, 0x04, 0x14],
  'SHA224': [0x30, 0x2d, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x04, 0x05, 0x00, 0x04, 0x1c],
  'SHA256': [0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20],
  'SHA384': [0x30, 0x41, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x02, 0x05, 0x00, 0x04, 0x30],
  'SHA512': [0x30, 0x51, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x03, 0x05, 0x00, 0x04, 0x40],
};

/// "SHA256withRSA" → "SHA256"。
String _hashFromSignAlgorithm(String algorithm) {
  final up = algorithm.toUpperCase().replaceAll(RegExp(r'[-_\s]'), '');
  final idx = up.indexOf('WITHRSA');
  final name = idx > 0 ? up.substring(0, idx) : up.replaceAll('RSA', '');
  if (!_isSupportedHash(name)) throw ArgumentError('不支持的签名算法: $algorithm');
  return name;
}

BigInt _os2ip(List<int> bytes) {
  var v = BigInt.zero;
  for (final b in bytes) {
    v = (v << 8) | BigInt.from(b & 0xff);
  }
  return v;
}

Uint8List _i2osp(BigInt v, int len) {
  final out = Uint8List(len);
  var x = v;
  for (var i = len - 1; i >= 0; i--) {
    out[i] = (x & BigInt.from(0xff)).toInt();
    x >>= 8;
  }
  return out;
}

/// EMSA-PKCS1-v1_5 编码（签名用，blockType 1）。
Uint8List _emsaPkcs1V15(List<int> digest, String hashName, int emLen) {
  final prefix = _digestInfoPrefix[hashName];
  if (prefix == null) throw ArgumentError('不支持的签名摘要: $hashName');
  final t = <int>[...prefix, ...digest];
  if (emLen < t.length + 11) throw ArgumentError('RSA 密钥太短');
  final psLen = emLen - t.length - 3;
  final em = Uint8List(emLen);
  em[0] = 0x00;
  em[1] = 0x01;
  for (var i = 0; i < psLen; i++) {
    em[2 + i] = 0xff;
  }
  em[2 + psLen] = 0x00;
  em.setRange(3 + psLen, emLen, t);
  return em;
}

/// EME-PKCS1-v1_5 编码（加密用，blockType 2）。
Uint8List _emePkcs1V15(List<int> message, int k, Random random) {
  if (message.length > k - 11) throw ArgumentError('RSA 明文过长');
  final psLen = k - message.length - 3;
  final ps = Uint8List(psLen);
  for (var i = 0; i < psLen; i++) {
    ps[i] = random.nextInt(255) + 1; // 非零随机字节
  }
  final em = Uint8List(k);
  em[0] = 0x00;
  em[1] = 0x02;
  em.setRange(2, 2 + psLen, ps);
  em[2 + psLen] = 0x00;
  em.setRange(3 + psLen, k, message);
  return em;
}

/// RSA 签名（PKCS#1 v1.5）。
Uint8List rsaSignBytes(String algorithm, String privateKeyPem, List<int> data) {
  final hashName = _hashFromSignAlgorithm(algorithm);
  final key = _parsePrivateKey(privateKeyPem);
  final digest = simpleHashBytes(hashName, data);
  final em = _emsaPkcs1V15(digest, hashName, key.byteLength);
  final s = _os2ip(em).modPow(key.d, key.n);
  return _i2osp(s, key.byteLength);
}

/// RSA 验签。
bool rsaVerifyBytes(String algorithm, String publicKeyPem, List<int> data, List<int> signature) {
  try {
    final hashName = _hashFromSignAlgorithm(algorithm);
    final key = _parsePublicKey(publicKeyPem);
    final digest = simpleHashBytes(hashName, data);
    final expected = <int>[..._digestInfoPrefix[hashName]!, ...digest];
    if (signature.length != key.byteLength) return false;
    final s = _os2ip(signature);
    if (s >= key.n) return false;
    final em = _i2osp(s.modPow(key.e, key.n), key.byteLength);
    // EM = 00 01 FF.. 00 || T
    if (em.length < 11) return false;
    if (em[0] != 0x00 || em[1] != 0x01) return false;
    var i = 2;
    while (i < em.length && em[i] == 0xff) {
      i++;
    }
    if (i >= em.length || em[i] != 0x00) return false;
    i++;
    final t = em.sublist(i);
    if (t.length != expected.length) return false;
    var diff = 0;
    for (var j = 0; j < t.length; j++) {
      diff |= t[j] ^ expected[j];
    }
    return diff == 0;
  } catch (_) {
    return false;
  }
}

/// RSA 加密（公钥，PKCS#1 v1.5 blockType 2）。
Uint8List rsaEncryptBytes(String publicKeyPem, List<int> data) {
  final key = _parsePublicKey(publicKeyPem);
  final em = _emePkcs1V15(data, key.byteLength, Random.secure());
  final c = _os2ip(em).modPow(key.e, key.n);
  return _i2osp(c, key.byteLength);
}

/// RSA 解密（私钥）。
Uint8List rsaDecryptBytes(String privateKeyPem, List<int> data) {
  final key = _parsePrivateKey(privateKeyPem);
  if (data.length != key.byteLength) {
    throw ArgumentError('密文长度与密钥不匹配');
  }
  final c = _os2ip(data);
  if (c >= key.n) throw ArgumentError('密文超出模数范围');
  final em = _i2osp(c.modPow(key.d, key.n), key.byteLength);
  if (em.length < 11 || em[0] != 0x00 || em[1] != 0x02) {
    throw const FormatException('RSA 解密失败：密文格式错误');
  }
  var i = 2;
  while (i < em.length && em[i] != 0x00) {
    i++;
  }
  if (i >= em.length) throw const FormatException('RSA 解密失败：未找到分隔符');
  return Uint8List.fromList(em.sublist(i + 1));
}

/// RSA 非对称加密门面（对齐 hutool AsymmetricCrypto 常用方法）。
class AsymmetricCrypto {
  AsymmetricCrypto(String transformation, {String? publicKey, String? privateKey}) {
    final alg = transformation.split('/').first.trim().toUpperCase();
    if (alg != 'RSA') {
      throw ArgumentError('暂仅支持 RSA 非对称加密（EC 待后续支持）');
    }
    _publicKeyPem = publicKey;
    _privateKeyPem = privateKey;
  }

  String? _publicKeyPem;
  String? _privateKeyPem;

  void setPublicKey(String key) => _publicKeyPem = key;
  void setPrivateKey(String key) => _privateKeyPem = key;

  static List<int> _toBytes(dynamic v) {
    if (v is List<int>) return v;
    if (v is String) return Uint8List.fromList(utf8.encode(v));
    throw ArgumentError('仅支持 String 或字节数组');
  }

  Uint8List encrypt(dynamic data) {
    if (_publicKeyPem == null) throw StateError('未设置公钥');
    return rsaEncryptBytes(_publicKeyPem!, _toBytes(data));
  }

  String encryptBase64(dynamic data) => base64.encode(encrypt(data));
  String encryptHex(dynamic data) => _bytesToHex(encrypt(data));

  Uint8List decrypt(dynamic data) {
    if (_privateKeyPem == null) throw StateError('未设置私钥');
    final bytes = data is String ? _autoDecodeData(data) : _toBytes(data);
    return rsaDecryptBytes(_privateKeyPem!, bytes);
  }

  String decryptStr(dynamic data) => utf8.decode(decrypt(data), allowMalformed: true);

  String decryptBase64(String data) {
    if (_privateKeyPem == null) throw StateError('未设置私钥');
    final b = _tryBase64ToBytes(data) ?? _utf8Bytes(data);
    return utf8.decode(rsaDecryptBytes(_privateKeyPem!, b), allowMalformed: true);
  }

  String decryptHex(String data) {
    if (_privateKeyPem == null) throw StateError('未设置私钥');
    final b = _tryHexToBytes(data) ?? _utf8Bytes(data);
    return utf8.decode(rsaDecryptBytes(_privateKeyPem!, b), allowMalformed: true);
  }
}

/// RSA 签名门面（对齐 hutool Sign 常用方法）。
class RsaSign {
  RsaSign(String algorithm, {String? privateKey, String? publicKey})
      : algorithm = algorithm,
        _privateKeyPem = privateKey,
        _publicKeyPem = publicKey;

  final String algorithm;
  String? _privateKeyPem;
  String? _publicKeyPem;

  void setPrivateKey(String key) => _privateKeyPem = key;
  void setPublicKey(String key) => _publicKeyPem = key;

  static List<int> _toBytes(dynamic v) {
    if (v is List<int>) return v;
    if (v is String) return Uint8List.fromList(utf8.encode(v));
    throw ArgumentError('仅支持 String 或字节数组');
  }

  Uint8List sign(dynamic data) {
    if (_privateKeyPem == null) throw StateError('未设置私钥');
    return rsaSignBytes(algorithm, _privateKeyPem!, _toBytes(data));
  }

  String signHex(dynamic data) => _bytesToHex(sign(data));
  String signBase64(dynamic data) => base64.encode(sign(data));

  bool verify(dynamic data, dynamic signature) {
    if (_publicKeyPem == null) throw StateError('未设置公钥');
    final sig = signature is String
        ? (_tryBase64ToBytes(signature) ?? _tryHexToBytes(signature) ?? _utf8Bytes(signature))
        : (signature as List<int>);
    return rsaVerifyBytes(algorithm, _publicKeyPem!, _toBytes(data), sig);
  }
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
