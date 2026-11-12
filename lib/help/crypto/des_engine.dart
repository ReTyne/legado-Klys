/// 从 crypto_utils.dart 拆分： `help/crypto/` 按算法分文件。
/// 以 part 归属同一库，私有类型互引保持可用。
part of '../../utils/crypto_utils.dart';


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
