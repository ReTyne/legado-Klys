/// 由 qr_share_screen.dart 按「一类一文件」拆出的 QrEncoder。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../qr_share_screen.dart';


/// 纯 Dart 实现的最小 QR Code 编码器。
/// 支持：字节模式（UTF-8）、版本 1-10 自动选择、纠错等级 M、8 种掩码按惩罚分择优。
/// 实现参考 ISO/IEC 18004 与 Nayuki QR 参考实现的结构。
class QrEncoder {
  QrEncoder._();

  // ---- 版本参数表（索引 0 对应版本 1，共 10 个版本）----

  /// 每版本总码字数（含数据码字 + EC 码字 + 结构位剩余）
  static const List<int> _totalCodewords = [
    26, 44, 70, 100, 134, 172, 196, 242, 292, 346,
  ];

  /// 纠错等级 M：每版本 [块数, 每块 EC 码字数]
  static const List<List<int>> _ecBlocks = [
    [1, 10], // V1
    [1, 16], // V2
    [1, 26], // V3
    [2, 18], // V4
    [2, 24], // V5
    [4, 16], // V6
    [4, 18], // V7
    [4, 22], // V8
    [5, 22], // V9
    [5, 26], // V10
  ];

  /// 校正图形中心坐标表（版本 1 无校正图形）
  static const List<List<int>> _alignmentPositions = [
    <int>[], // V1
    [6, 18], // V2
    [6, 22], // V3
    [6, 26], // V4
    [6, 30], // V5
    [6, 34], // V6
    [6, 22, 38], // V7
    [6, 24, 42], // V8
    [6, 26, 46], // V9
    [6, 28, 50], // V10
  ];

  /// 掩码惩罚分权重（N1=连续同色, N2=2x2 同色块, N3=类探测图形, N4=深浅比例）
  static const int _penaltyN1 = 3;
  static const int _penaltyN2 = 3;
  static const int _penaltyN3 = 40;
  static const int _penaltyN4 = 10;

  /// 纠错等级 M 的 2 位指示符（用于格式信息）
  static const int _ecLevelBits = 0; // 纠错等级 M（00）

  // ---- GF(256) 运算表（本原多项式 x^8+x^4+x^3+x+1 = 0x11D）----

  static final List<int> _gfExp = List<int>.filled(512, 0);
  static final List<int> _gfLog = List<int>.filled(256, 0);
  static bool _gfReady = false;

  static void _ensureGf() {
    if (_gfReady) return;
    var x = 1;
    for (var i = 0; i < 255; i++) {
      _gfExp[i] = x;
      _gfLog[x] = i;
      x <<= 1;
      if ((x & 0x100) != 0) x ^= 0x11D;
    }
    for (var i = 255; i < 512; i++) {
      _gfExp[i] = _gfExp[i - 255];
    }
    _gfReady = true;
  }

  static int _gfMul(int a, int b) {
    if (a == 0 || b == 0) return 0;
    return _gfExp[_gfLog[a] + _gfLog[b]];
  }

  /// 生成 RS 纠错生成多项式：(x-α^0)(x-α^1)...(x-α^(degree-1))，GF(2^8) 中减法即异或
  static List<int> _rsGeneratorPoly(int degree) {
    var poly = <int>[1];
    for (var i = 0; i < degree; i++) {
      final next = List<int>.filled(poly.length + 1, 0);
      for (var j = 0; j < poly.length; j++) {
        next[j] ^= poly[j]; // poly[j] * x
        next[j + 1] ^= _gfMul(poly[j], _gfExp[i]); // poly[j] * α^i
      }
      poly = next;
    }
    return poly;
  }

  /// 对一段数据码字计算 RS 纠错码字（多项式长除法）
  static List<int> _rsRemainder(List<int> data, int ecCount) {
    final gen = _rsGeneratorPoly(ecCount);
    final res = List<int>.generate(ecCount, (_) => 0);
    for (final b in data) {
      final factor = b ^ res.first;
      res.removeAt(0);
      res.add(0);
      for (var i = 0; i < ecCount; i++) {
        res[i] ^= _gfMul(gen[i + 1], factor);
      }
    }
    return res;
  }

  /// 版本 v 的数据码字总数
  static int _dataCodewordCount(int version) {
    final blocks = _ecBlocks[version - 1];
    return _totalCodewords[version - 1] - blocks[0] * blocks[1];
  }

  /// 字节模式最大容量（用于报错提示）
  static int maxByteCapacity() => _dataCodewordCount(10);

  /// 编码文本为二维码。字节模式，版本在 1-10 间自动选择，容量不足抛 [QrEncodeException]。
  static QrCode encode(String text) {
    _ensureGf();
    final data = utf8.encode(text);

    // 1. 选择能容纳内容的最小版本
    var version = -1;
    for (var v = 1; v <= 10; v++) {
      final countBits = v <= 9 ? 8 : 16; // 字符计数指示符位数
      final need = 4 + countBits + data.length * 8;
      if (need <= _dataCodewordCount(v) * 8) {
        version = v;
        break;
      }
    }
    if (version < 0) {
      throw QrEncodeException(data.length, maxByteCapacity());
    }
    final countBits = version <= 9 ? 8 : 16;
    final dataCapacityBits = _dataCodewordCount(version) * 8;

    // 2. 组装位流：模式(0100) + 字符数 + 数据 + 终止符 + 字节对齐 + 填充字节
    final bits = <int>[];
    void put(int value, int length) {
      for (var i = length - 1; i >= 0; i--) {
        bits.add((value >> i) & 1);
      }
    }

    put(4, 4); // 模式指示符 0100 = 字节模式
    put(data.length, countBits);
    for (final b in data) {
      put(b, 8);
    }
    put(0, math.min(4, dataCapacityBits - bits.length)); // 终止符（最多 4 位 0）
    while (bits.length % 8 != 0) {
      bits.add(0);
    }
    const padBytes = [0xEC, 0x11];
    var padIdx = 0;
    while (bits.length < dataCapacityBits) {
      put(padBytes[padIdx % 2], 8);
      padIdx++;
    }

    // 3. 位流转码字
    final codewords = <int>[];
    for (var i = 0; i < bits.length; i += 8) {
      var b = 0;
      for (var j = 0; j < 8; j++) {
        b = (b << 1) | bits[i + j];
      }
      codewords.add(b);
    }

    // 4. 分块 + RS 纠错 + 交织（数据码字按块交织，随后 EC 码字按块交织）
    final blockInfo = _ecBlocks[version - 1];
    final numBlocks = blockInfo[0];
    final ecPerBlock = blockInfo[1];
    final shortLen = _dataCodewordCount(version) ~/ numBlocks;
    final numLong = _dataCodewordCount(version) % numBlocks;
    final dataBlocks = <List<int>>[];
    final ecBlocks = <List<int>>[];
    var offset = 0;
    for (var i = 0; i < numBlocks; i++) {
      final len = shortLen + (i < numLong ? 1 : 0);
      final blk = codewords.sublist(offset, offset + len);
      offset += len;
      dataBlocks.add(blk);
      ecBlocks.add(_rsRemainder(blk, ecPerBlock));
    }
    final interleaved = <int>[];
    for (var i = 0; i <= shortLen; i++) {
      for (final blk in dataBlocks) {
        if (i < blk.length) interleaved.add(blk[i]);
      }
    }
    for (var i = 0; i < ecPerBlock; i++) {
      for (final blk in ecBlocks) {
        interleaved.add(blk[i]);
      }
    }

    // 5. 构建矩阵
    final builder = _MatrixBuilder(version);
    builder.drawFunctionPatterns();
    builder.drawCodewords(interleaved);

    // 6. 逐掩码尝试，按惩罚分择优
    var bestScore = 1 << 30;
    List<List<bool>>? bestModules;
    for (var mask = 0; mask < 8; mask++) {
      builder.applyMask(mask);
      builder.drawFormatBits(mask);
      final score = builder.penaltyScore();
      if (score < bestScore) {
        bestScore = score;
        bestModules = builder.copyModules();
      }
      builder.applyMask(mask); // 异或两次还原，供下一掩码使用
    }
    // 最佳掩码已应用并写入格式位（bestModules 即当前矩阵快照）
    return QrCode(builder.size, bestModules ?? builder.copyModules());
  }

  // ==================== PNG 编码 ====================

  /// 将模块矩阵编码为 PNG（灰度 8 位，deflate 用无压缩存储块 + Adler32/CRC32 自实现）
  static Uint8List _encodePng(List<List<bool>> modules,
      {required int scale, required int quietZone}) {
    final n = modules.length;
    final dim = n + quietZone * 2;
    final width = dim * scale;
    final height = dim * scale;
    // 每行前置 1 字节过滤器类型（0 = None）
    final raw = Uint8List(width * height + height);
    var p = 0;
    for (var y = 0; y < height; y++) {
      raw[p++] = 0;
      final my = (y ~/ scale) - quietZone;
      for (var x = 0; x < width; x++) {
        final mx = (x ~/ scale) - quietZone;
        final dark =
            my >= 0 && my < n && mx >= 0 && mx < n && modules[my][mx];
        raw[p++] = dark ? 0x00 : 0xFF;
      }
    }

    final out = <int>[];
    void putBytes(List<int> b) => out.addAll(b);
    void putBe32(int v) {
      out.add((v >> 24) & 0xFF);
      out.add((v >> 16) & 0xFF);
      out.add((v >> 8) & 0xFF);
      out.add(v & 0xFF);
    }

    // PNG 签名
    putBytes(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

    void writeChunk(String type, List<int> data) {
      putBe32(data.length);
      final typeBytes = ascii.encode(type);
      putBytes(typeBytes);
      putBytes(data);
      putBe32(_crc32(typeBytes, data));
    }

    // IHDR
    writeChunk('IHDR', <int>[
      ..._be32Bytes(width),
      ..._be32Bytes(height),
      8, // 位深
      0, // 颜色类型：灰度
      0, // 压缩方法
      0, // 过滤方法
      0, // 非隔行扫描
    ]);

    // IDAT：zlib 流 = 2 字节头 + deflate 存储块 + Adler32
    final zlibStream = <int>[
      0x78, 0x01, // CMF/FLG：deflate、32K 窗口、无压缩
    ];
    var pos = 0;
    while (pos < raw.length) {
      final end = math.min(pos + 65535, raw.length);
      final chunk = raw.sublist(pos, end);
      final finalBlock = end == raw.length;
      zlibStream.add(finalBlock ? 1 : 0); // BFINAL + BTYPE(00 存储块)
      zlibStream.add(chunk.length & 0xFF);
      zlibStream.add((chunk.length >> 8) & 0xFF);
      zlibStream.add(~chunk.length & 0xFF);
      zlibStream.add((~chunk.length >> 8) & 0xFF);
      zlibStream.addAll(chunk);
      pos = end;
    }
    final adler = _adler32(raw);
    zlibStream.add((adler >> 24) & 0xFF);
    zlibStream.add((adler >> 16) & 0xFF);
    zlibStream.add((adler >> 8) & 0xFF);
    zlibStream.add(adler & 0xFF);
    writeChunk('IDAT', zlibStream);

    // IEND
    writeChunk('IEND', const <int>[]);

    return Uint8List.fromList(out);
  }

  static List<int> _be32Bytes(int v) => [
        (v >> 24) & 0xFF,
        (v >> 16) & 0xFF,
        (v >> 8) & 0xFF,
        v & 0xFF,
      ];

  static int _adler32(Uint8List data) {
    var a = 1;
    var b = 0;
    const mod = 65521;
    for (final x in data) {
      a = (a + x) % mod;
      b = (b + a) % mod;
    }
    return (b << 16) | a;
  }

  static final List<int> _crcTable = _buildCrcTable();

  static List<int> _buildCrcTable() {
    final t = List<int>.filled(256, 0);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
      }
      t[n] = c;
    }
    return t;
  }

  static int _crc32(List<int> a, List<int> b) {
    var c = 0xFFFFFFFF;
    for (final x in a) {
      c = _crcTable[(c ^ x) & 0xFF] ^ (c >> 8);
    }
    for (final x in b) {
      c = _crcTable[(c ^ x) & 0xFF] ^ (c >> 8);
    }
    return c ^ 0xFFFFFFFF;
  }
}
