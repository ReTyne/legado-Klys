/// 从 crypto_utils.dart 拆分： `help/crypto/` 按算法分文件。
/// 以 part 归属同一库，私有类型互引保持可用。
part of '../../utils/crypto_utils.dart';

// =====================================================================
// AES（FIPS-197，128/192/256）
// =====================================================================

abstract class _BlockCipher {
  int get blockSize;
  void encryptBlock(Uint8List input, int inOff, Uint8List output, int outOff);
  void decryptBlock(Uint8List input, int inOff, Uint8List output, int outOff);
}

// =====================================================================
// 分组密码模式（ECB/CBC/PCBC/CFB/OFB/CTR）
// =====================================================================

enum _Mode { ecb, cbc, pcbc, cfb, ofb, ctr }

/// 应用分组模式。ECB/CBC/PCBC 要求数据按块对齐；CFB/OFB/CTR 按流处理。
Uint8List _applyMode(_BlockCipher cipher, _Mode mode, Uint8List? iv,
    Uint8List data, bool encrypt) {
  final bs = cipher.blockSize;
  final out = Uint8List(data.length);
  final streamModes =
      mode == _Mode.cfb || mode == _Mode.ofb || mode == _Mode.ctr;
  // ECB/CBC/PCBC（含 NoPadding）必须按块对齐，否则给出明确错误。
  if (!streamModes && data.length % bs != 0) {
    throw ArgumentError('数据长度必须是块大小 $bs 的倍数（模式 ${mode.name.toUpperCase()}）');
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
        // CFB 反馈寄存器必须装入「密文」：加密取输出，解密取输入。
        // 若解密误用明文输出反馈，后续块的密钥流会错乱导致解密失败。
        final feedback = encrypt ? out : data;
        final next = Uint8List(bs);
        next.setRange(0, len, feedback.sublist(off, off + len));
        if (len < bs) {
          next.setRange(len, bs, prev.sublist(len, bs));
        }
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
        // OFB 反馈的是密钥流，与输入/输出无关，加解密路径对称
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
// PKCS#5/PKCS#7 填充
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
// ISO10126 填充：末字节记录填充长度，其余填充字节为真实随机值
// =====================================================================

Uint8List _padIso10126(Uint8List data, int blockSize) {
  final pad = blockSize - (data.length % blockSize);
  final out = Uint8List(data.length + pad);
  out.setRange(0, data.length, data);
  final random = Random.secure();
  for (var i = data.length; i < out.length - 1; i++) {
    out[i] = random.nextInt(256);
  }
  out[out.length - 1] = pad;
  return out;
}

Uint8List _unpadIso10126(Uint8List data, int blockSize) {
  if (data.isEmpty) return data;
  final p = data[data.length - 1];
  if (p < 1 || p > blockSize || p > data.length) return data;
  // 中间为随机字节，不校验其内容，仅按末字节长度裁剪
  return Uint8List.fromList(data.sublist(0, data.length - p));
}

/// 按填充方式去填充。
Uint8List _unpad(Uint8List data, String padding, int blockSize) {
  if (padding == 'ISO10126') return _unpadIso10126(data, blockSize);
  return _unpadPkcs7(data, blockSize);
}

/// 按填充方式填充（PKCS7 或 ISO10126）。
Uint8List _pad(Uint8List data, String padding, int blockSize) {
  if (padding == 'ISO10126') return _padIso10126(data, blockSize);
  return _padPkcs7(data, blockSize);
}

// =====================================================================
// 分组密钥归一化
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
    // 算法名归一化：3DES/TRIPLEDES → DESEDE，SMS4 → SM4，ARCFOUR → RC4
    if (alg == '3DES' || alg == 'TRIPLEDES' || alg == 'DESEDE') alg = 'DESEDE';
    if (alg == 'SMS4') alg = 'SM4';
    if (alg == 'ARCFOUR') alg = 'RC4';
    if (!const {'AES', 'DES', 'DESEDE', 'RC4', 'SM4'}.contains(alg)) {
      throw ArgumentError('不支持的对称算法: ${parts[0]}');
    }
    algorithm = alg;
    mode = parts.length > 1 ? parts[1].trim() : 'ECB';
    // GCM 需要 GHASH 认证标签，纯 Dart 实现未提供；当前依赖集不含
    // pointycastle/encrypt，明确拒绝而不是静默降级为无认证模式。
    if (mode == 'GCM') {
      throw ArgumentError('分组模式 GCM 暂不支持：需要 GHASH 与认证标签，需引入密码学依赖后启用');
    }
    if (!const {'ECB', 'CBC', 'PCBC', 'CFB', 'OFB', 'CTR'}.contains(mode)) {
      throw ArgumentError('不支持的分组模式: ${parts[1]}');
    }
    final padRaw = parts.length > 2 ? parts[2].trim() : 'PKCS5PADDING';
    switch (padRaw) {
      case 'PKCS5PADDING':
      case 'PKCS7PADDING':
        padding = 'PKCS7';
        break;
      case 'ISO10126PADDING':
        padding = 'ISO10126';
        break;
      case 'NOPADDING':
        padding = 'NONE';
        break;
      default:
        throw ArgumentError('不支持的填充方式: ${parts[2]}');
    }
    // 流模式（CFB/OFB/CTR/RC4）与 NoPadding 均不应用块填充
    final streamMode =
        mode == 'CFB' || mode == 'OFB' || mode == 'CTR' || alg == 'RC4';
    padded = !streamMode && padding != 'NONE';
  }

  late final String algorithm;
  late final String mode;
  late final String padding;
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
