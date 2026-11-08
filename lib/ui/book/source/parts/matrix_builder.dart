/// 由 qr_share_screen.dart 按「一类一文件」拆出的 _MatrixBuilder。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../qr_share_screen.dart';


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
