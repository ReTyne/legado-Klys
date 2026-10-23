import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:share_plus/share_plus.dart';

/// 二维码内容超出容量（版本 1-10 + 纠错等级 M 上限约 271 字节）时抛出
class QrEncodeException implements Exception {
  final int dataLength;
  final int maxCapacity;
  const QrEncodeException(this.dataLength, this.maxCapacity);

  @override
  String toString() => '内容长度 $dataLength 字节，超出二维码容量上限 $maxCapacity 字节';
}

/// 二维码矩阵（不含静默区）。modules[row][col] 为 true 表示深色模块。
class QrCode {
  final int size;
  final List<List<bool>> modules;

  const QrCode(this.size, this.modules);

  /// 导出 PNG 图片字节（8 位灰度，deflate 使用无压缩存储块，零第三方依赖）
  Uint8List toPngBytes({int scale = 10, int quietZone = 4}) =>
      QrEncoder._encodePng(modules, scale: scale, quietZone: quietZone);
}

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

/// QR 矩阵构建：功能图形摆放、数据填充、掩码、格式信息、惩罚分计算
class _MatrixBuilder {
  final int version;
  final int size;
  final List<List<bool>> modules;
  final List<List<bool>> isFunction;

  _MatrixBuilder(this.version)
      : size = version * 4 + 17,
        modules = List.generate(
            version * 4 + 17, (_) => List<bool>.filled(version * 4 + 17, false)),
        isFunction = List.generate(
            version * 4 + 17, (_) => List<bool>.filled(version * 4 + 17, false));

  void setFunction(int row, int col, bool dark) {
    modules[row][col] = dark;
    isFunction[row][col] = true;
  }

  void drawFunctionPatterns() {
    // 探测图形（左上/右上/左下三个角）+ 分隔符
    final corners = <List<int>>[
      [0, 0],
      [0, size - 7],
      [size - 7, 0],
    ];
    for (final corner in corners) {
      final r0 = corner[0];
      final c0 = corner[1];
      for (var dr = -1; dr <= 7; dr++) {
        for (var dc = -1; dc <= 7; dc++) {
          final r = r0 + dr;
          final col = c0 + dc;
          if (r < 0 || r >= size || col < 0 || col >= size) continue;
          final inRing = dr >= 0 && dr <= 6 && dc >= 0 && dc <= 6;
          final dark = inRing &&
              (dr == 0 || dr == 6 || dc == 0 || dc == 6 ||
                  (dr >= 2 && dr <= 4 && dc >= 2 && dc <= 4));
          setFunction(r, col, dark);
        }
      }
    }

    // 定位图形（timing pattern）：第 6 行 / 第 6 列，两端被探测图形截断
    for (var i = 8; i < size - 8; i++) {
      final dark = i % 2 == 0;
      setFunction(6, i, dark);
      setFunction(i, 6, dark);
    }

    // 校正图形（跳过与探测图形重叠的位置）
    final positions = QrEncoder._alignmentPositions[version - 1];
    for (final r in positions) {
      for (final col in positions) {
        if ((r <= 8 && col <= 8) ||
            (r <= 8 && col >= size - 9) ||
            (r >= size - 9 && col <= 8)) {
          continue;
        }
        for (var dr = -2; dr <= 2; dr++) {
          for (var dc = -2; dc <= 2; dc++) {
            final dark = dr.abs() == 2 || dc.abs() == 2 || (dr == 0 && dc == 0);
            setFunction(r + dr, col + dc, dark);
          }
        }
      }
    }

    // 版本信息（版本 7 起，18 位 BCH，两份；版本 1-6 无此区域）
    _drawVersionInfo();

    // 预留格式信息区域（drawFormatBits 在选定掩码后写入具体值）
    for (var i = 0; i <= 8; i++) {
      if (i == 6) continue; // timing 列/行已标记
      setFunction(i, 8, false);
      setFunction(8, i, false);
    }
    for (var i = 0; i < 8; i++) {
      setFunction(8, size - 1 - i, false);
      setFunction(size - 1 - i, 8, false);
    }

    // 暗模块
    setFunction(size - 8, 8, true);
  }

  /// 按 Zig-Zag 顺序填充数据码字（跳过功能模块；剩余位保持 0）
  void drawCodewords(List<int> codewords) {
    var bitIndex = 0;
    final totalBits = codewords.length * 8;
    for (var right = size - 1; right >= 1; right -= 2) {
      if (right == 6) right = 5; // 跳过 timing 列
      for (var vert = 0; vert < size; vert++) {
        for (var j = 0; j < 2; j++) {
          final col = right - j;
          final upward = ((right + 1) & 2) == 0;
          final row = upward ? size - 1 - vert : vert;
          if (!isFunction[row][col] && bitIndex < totalBits) {
            modules[row][col] =
                ((codewords[bitIndex >> 3] >> (7 - (bitIndex & 7))) & 1) == 1;
            bitIndex++;
          }
        }
      }
    }
  }

  /// 应用/撤销掩码（异或两次即还原），仅作用于非功能模块
  void applyMask(int mask) {
    for (var row = 0; row < size; row++) {
      for (var col = 0; col < size; col++) {
        if (isFunction[row][col]) continue;
        if (_maskFn(mask, row, col)) {
          modules[row][col] = !modules[row][col];
        }
      }
    }
  }

  static bool _maskFn(int mask, int row, int col) {
    switch (mask) {
      case 0:
        return (row + col) % 2 == 0;
      case 1:
        return row % 2 == 0;
      case 2:
        return col % 3 == 0;
      case 3:
        return (row + col) % 3 == 0;
      case 4:
        return (row ~/ 2 + col ~/ 3) % 2 == 0;
      case 5:
        return (row * col) % 2 + (row * col) % 3 == 0;
      case 6:
        return ((row * col) % 2 + (row * col) % 3) % 2 == 0;
      case 7:
        return ((row + col) % 2 + (row * col) % 3) % 2 == 0;
      default:
        return false;
    }
  }

  /// 写入格式信息（15 位 BCH，含 EC 等级 M 与掩码图案）
  void drawFormatBits(int mask) {
    final data5 = (QrEncoder._ecLevelBits << 3) | mask;
    var rem = data5;
    for (var i = 0; i < 10; i++) {
      rem = (rem << 1) ^ ((rem >> 9) * 0x537);
    }
    final bits = ((data5 << 10) | rem) ^ 0x5412;
    bool bit(int i) => ((bits >> i) & 1) == 1;

    // 第一份：绕左上探测图形
    for (var i = 0; i <= 5; i++) {
      setFunction(i, 8, bit(i));
    }
    setFunction(7, 8, bit(6));
    setFunction(8, 8, bit(7));
    setFunction(8, 7, bit(8));
    for (var i = 9; i < 15; i++) {
      setFunction(8, 14 - i, bit(i));
    }
    // 第二份：右上与左下
    for (var i = 0; i < 8; i++) {
      setFunction(8, size - 1 - i, bit(i));
    }
    for (var i = 8; i < 15; i++) {
      setFunction(size - 15 + i, 8, bit(i));
    }
    setFunction(size - 8, 8, true); // 暗模块
  }

  /// 版本信息（版本 7-10，18 位 BCH，两份；版本 1-6 无此区域）
  void _drawVersionInfo() {
    if (version < 7) return;
    var rem = version;
    for (var i = 0; i < 12; i++) {
      rem = (rem << 1) ^ ((rem >> 11) * 0x1F25);
    }
    final bits = (version << 12) | rem;
    for (var i = 0; i < 18; i++) {
      final dark = ((bits >> i) & 1) == 1;
      setFunction(i ~/ 3, size - 11 + i % 3, dark);
      setFunction(size - 11 + i % 3, i ~/ 3, dark);
    }
  }

  /// 惩罚分（N1 连续同色 + N2 2x2 同色 + N3 类探测图形 + N4 深浅比例）
  int penaltyScore() {
    var result = 0;
    // 行方向
    for (var row = 0; row < size; row++) {
      result += _penaltyLine(
          List<bool>.generate(size, (c) => modules[row][c]));
    }
    // 列方向
    for (var col = 0; col < size; col++) {
      result += _penaltyLine(
          List<bool>.generate(size, (r) => modules[r][col]));
    }
    // 2x2 同色块
    for (var row = 0; row < size - 1; row++) {
      for (var col = 0; col < size - 1; col++) {
        final c = modules[row][col];
        if (c == modules[row][col + 1] &&
            c == modules[row + 1][col] &&
            c == modules[row + 1][col + 1]) {
          result += QrEncoder._penaltyN2;
        }
      }
    }
    // 深浅比例
    var dark = 0;
    for (final row in modules) {
      for (final m in row) {
        if (m) dark++;
      }
    }
    final total = size * size;
    final k =
        ((dark * 20 - total * 10).abs() + total - 1) ~/ total - 1;
    result += k * QrEncoder._penaltyN4;
    return result;
  }

  int _penaltyLine(List<bool> line) {
    var result = 0;
    var runColor = false;
    var runLen = 0;
    final history = <int>[0, 0, 0, 0, 0, 0, 0];
    for (var i = 0; i < line.length; i++) {
      if (line[i] == runColor) {
        runLen++;
        if (runLen == 5) {
          result += QrEncoder._penaltyN1;
        } else if (runLen > 5) {
          result += 1;
        }
      } else {
        _addHistory(runLen, history, line.length);
        if (!runColor) {
          result += _countPatterns(history) * QrEncoder._penaltyN3;
        }
        runColor = line[i];
        runLen = 1;
      }
    }
    result += _terminateAndCount(runColor, runLen, history, line.length) *
        QrEncoder._penaltyN3;
    return result;
  }

  void _addHistory(int runLen, List<int> history, int size) {
    var len = runLen;
    if (history[0] == 0) {
      len += size; // 首个游程补上浅色边框
    }
    for (var i = history.length - 1; i > 0; i--) {
      history[i] = history[i - 1];
    }
    history[0] = len;
  }

  int _countPatterns(List<int> history) {
    final n = history[1];
    final core = n > 0 &&
        history[2] == n &&
        history[3] == n * 3 &&
        history[4] == n &&
        history[5] == n;
    return (core && history[6] >= n * 4 && history[0] >= n * 4 ? 1 : 0) +
        (core && history[0] >= n * 4 && history[6] >= n * 4 ? 1 : 0);
  }

  int _terminateAndCount(
      bool runColor, int runLen, List<int> history, int size) {
    var len = runLen;
    if (runColor) {
      _addHistory(len, history, size);
      len = 0;
    }
    len += size; // 末游程补上浅色边框
    _addHistory(len, history, size);
    return _countPatterns(history);
  }

  List<List<bool>> copyModules() =>
      List<List<bool>>.generate(size, (r) => List<bool>.from(modules[r]));
}

/// 书源二维码分享页：把书源 JSON 编码为二维码展示，可导出 PNG 分享或复制 JSON
class QrShareScreen extends StatefulWidget {
  final BookSource source;
  const QrShareScreen({super.key, required this.source});

  @override
  State<QrShareScreen> createState() => _QrShareScreenState();
}

class _QrShareScreenState extends State<QrShareScreen> {
  late final String _json;
  QrCode? _qr;
  bool _compact = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _json = const JsonEncoder.withIndent('  ').convert(widget.source.toJson());
    try {
      _qr = QrEncoder.encode(_json);
    } on QrEncodeException {
      // 完整 JSON 超长时退化用精简字段（省略空值），导入端可正常还原
      try {
        final compact = jsonEncode(_compactSourceJson(widget.source));
        _qr = QrEncoder.encode(compact);
        _compact = true;
      } on QrEncodeException catch (e) {
        _error = e.toString();
      }
    }
  }

  /// 仅保留非空/非默认字段的精简书源 JSON
  Map<String, dynamic> _compactSourceJson(BookSource source) {
    final compact = <String, dynamic>{};
    source.toJson().forEach((key, value) {
      if (value == null) return;
      if (value is String && value.isEmpty) return;
      if (value is Map && value.isEmpty) return;
      compact[key] = value;
    });
    return compact;
  }

  Future<void> _shareImage() async {
    final qr = _qr;
    if (qr == null) return;
    try {
      final bytes = qr.toPngBytes(scale: 10, quietZone: 4);
      final file = File(
          '${Directory.systemTemp.path}/source_qr_${widget.source.bookSourceUrl.hashCode.abs()}.png');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)],
          text: '书源二维码：${widget.source.bookSourceName}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导出图片失败: $e')));
      }
    }
  }

  Future<void> _copyJson() async {
    await Clipboard.setData(ClipboardData(text: _json));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('书源 JSON 已复制到剪贴板')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final qr = _qr;
    return Scaffold(
      appBar: AppBar(
        title: const Text('二维码分享'),
        actions: [
          IconButton(
              icon: const Icon(Icons.copy_all), tooltip: '复制 JSON', onPressed: _copyJson),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: qr == null
                    ? _buildErrorState(theme)
                    : Card(
                        color: Colors.white,
                        elevation: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: SizedBox(
                            width: 300,
                            height: 300,
                            child: CustomPaint(
                              painter: _QrPainter(qr, Colors.black),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              color: theme.colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.source.bookSourceName,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('JSON 大小：${_json.length} 字节',
                        style: theme.textTheme.bodySmall),
                    Text('二维码版本：${(qr != null ? (qr.size - 17) ~/ 4 : '-')}（纠错等级 M）',
                        style: theme.textTheme.bodySmall),
                    if (_compact)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text('书源字段较多，二维码内为精简 JSON（省略空字段），可正常导入',
                            style: TextStyle(fontSize: 11, color: Colors.orange)),
                      ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(_error!,
                            style: const TextStyle(fontSize: 11, color: Colors.red)),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.image),
                    label: const Text('分享二维码图片'),
                    onPressed: qr == null ? null : _shareImage,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.content_copy),
                    label: const Text('复制 JSON'),
                    onPressed: _copyJson,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(ThemeData theme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.qr_code_2, size: 72, color: Colors.grey[400]),
        const SizedBox(height: 12),
        const Text('无法生成二维码', style: TextStyle(fontSize: 16)),
        const SizedBox(height: 8),
        const Text('书源 JSON 超出二维码（版本 10 / 纠错 M）容量上限，\n请改用「复制 JSON」或分享 JSON 文本。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}

/// 二维码绘制（含 2 模块静默区，深色模块按主题色绘制）
class _QrPainter extends CustomPainter {
  final QrCode qr;
  final Color color;
  const _QrPainter(this.qr, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = Colors.white;
    canvas.drawRect(Offset.zero & size, bg);
    final n = qr.size;
    const qz = 2;
    final cell = size.width / (n + qz * 2);
    final dark = Paint()
      ..color = color
      ..isAntiAlias = false;
    for (var row = 0; row < n; row++) {
      for (var col = 0; col < n; col++) {
        if (!qr.modules[row][col]) continue;
        final dx = (col + qz) * cell;
        final dy = (row + qz) * cell;
        // 轻微外扩避免亚像素缝隙
        canvas.drawRect(
            Rect.fromLTWH(dx - 0.05, dy - 0.05, cell + 0.1, cell + 0.1), dark);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrPainter old) =>
      old.qr != qr || old.color != color;
}
