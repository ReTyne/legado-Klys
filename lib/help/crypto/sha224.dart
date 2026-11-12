/// 从 crypto_utils.dart 拆分： `help/crypto/` 按算法分文件。
/// 以 part 归属同一库，私有类型互引保持可用。
part of '../../utils/crypto_utils.dart';


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
