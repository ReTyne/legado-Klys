/// 从 crypto_utils.dart 拆分： `help/crypto/` 按算法分文件。
/// 以 part 归属同一库，私有类型互引保持可用。
part of '../../utils/crypto_utils.dart';


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
