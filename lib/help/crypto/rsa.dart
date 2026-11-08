/// 从 crypto_utils.dart 拆分：对齐 legado-E `help/crypto/` 按算法分文件。
/// 以 part 归属同一库，私有类型互引保持可用。
part of '../../utils/crypto_utils.dart';


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
  RsaSign(this.algorithm, {String? privateKey, String? publicKey})
      : _privateKeyPem = privateKey,
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
