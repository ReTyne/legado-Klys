import 'dart:typed_data';

import 'package:enough_convert/enough_convert.dart';

/// 编码统计探测器（对齐 legado-E utils/EncodingDetect.kt + lib/icu4j/CharsetDetector）。
///
/// 纯 Dart 实现的简化版 ICU 编码探测：先 BOM / UTF-16 零字节特征 / UTF-8 严格校验，
/// 再对 GBK 与 Big5 做「解码后可读字符占比」打分，取更优者。
/// 相比原来「UTF-8 失败一律按 GBK 回退」，本探测器能正确区分：
///   - 无 BOM 的 UTF-16 LE/BE
///   - Big5 繁体（如台湾源站导出的 TXT）
///   - GBK / GB18030 简体
class EncodingDetector {
  /// 返回编码名：utf-8 / utf-16le / utf-16be / gbk / big5
  static String detect(Uint8List bytes) {
    if (bytes.isEmpty) return 'utf-8';

    // 1) BOM 检测
    if (_startsWith(bytes, const [0xEF, 0xBB, 0xBF])) return 'utf-8';
    if (_startsWith(bytes, const [0xFF, 0xFE])) return 'utf-16le';
    if (_startsWith(bytes, const [0xFE, 0xFF])) return 'utf-16be';

    // 2) 无 BOM 的 UTF-16：ASCII 文本中夹杂大量 NUL 字节
    var nul = 0;
    for (final b in bytes) {
      if (b == 0) nul++;
    }
    if (nul * 5 >= bytes.length) return _utf16Endianness(bytes);

    // 3) UTF-8 严格校验
    if (_isValidUtf8(bytes)) return 'utf-8';

    // 4) GBK 与 Big5 按解码后可读性打分
    final gbkScore = _readableRatio(const GbkCodec().decode(bytes));
    final big5Score = _readableRatio(const Big5Codec().decode(bytes));
    if (big5Score > gbkScore + 0.05) return 'big5';
    return 'gbk';
  }

  static bool _startsWith(Uint8List bytes, List<int> prefix) {
    if (bytes.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[i] != prefix[i]) return false;
    }
    return true;
  }

  /// 判断无 BOM UTF-16 的字节序：偶位多为 0（高字节在前）→ BE，奇位多为 0 → LE
  static String _utf16Endianness(Uint8List bytes) {
    var evenZero = 0, oddZero = 0;
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      if (bytes[i] == 0) evenZero++;
      if (bytes[i + 1] == 0) oddZero++;
    }
    return evenZero >= oddZero ? 'utf-16be' : 'utf-16le';
  }

  /// UTF-8 严格校验（RFC 3629，拒绝过长编码与代理区）
  static bool _isValidUtf8(Uint8List b) {
    var i = 0;
    while (i < b.length) {
      final c = b[i];
      if (c < 0x80) {
        i++;
      } else if ((c & 0xE0) == 0xC0) {
        if (i + 1 >= b.length || (b[i + 1] & 0xC0) != 0x80) return false;
        final cp = ((c & 0x1F) << 6) | (b[i + 1] & 0x3F);
        if (cp < 0x80) return false;
        i += 2;
      } else if ((c & 0xF0) == 0xE0) {
        if (i + 2 >= b.length ||
            (b[i + 1] & 0xC0) != 0x80 ||
            (b[i + 2] & 0xC0) != 0x80) return false;
        final cp = ((c & 0x0F) << 12) | ((b[i + 1] & 0x3F) << 6) | (b[i + 2] & 0x3F);
        if (cp < 0x800 || (cp >= 0xD800 && cp <= 0xDFFF)) return false;
        i += 3;
      } else if ((c & 0xF8) == 0xF0) {
        if (i + 3 >= b.length ||
            (b[i + 1] & 0xC0) != 0x80 ||
            (b[i + 2] & 0xC0) != 0x80 ||
            (b[i + 3] & 0xC0) != 0x80) return false;
        final cp = ((c & 0x07) << 18) |
            ((b[i + 1] & 0x3F) << 12) |
            ((b[i + 2] & 0x3F) << 6) |
            (b[i + 3] & 0x3F);
        if (cp < 0x10000 || cp > 0x10FFFF) return false;
        i += 4;
      } else {
        return false;
      }
    }
    return true;
  }

  /// 可读字符占比：CJK / ASCII 可见字符 / 常见全角标点 / 换行制表计为可读。
  /// 错误解码会产生大量控制符、私有区或生僻符号，从而降低该比值。
  static double _readableRatio(String s) {
    if (s.isEmpty) return 0;
    var readable = 0, total = 0;
    for (final r in s.runes) {
      total++;
      if (r == 0x0A || r == 0x0D || r == 0x09) {
        readable++;
      } else if (r >= 0x20 && r <= 0x7E) {
        readable++;
      } else if (r >= 0x4E00 && r <= 0x9FFF) {
        readable++;
      } else if (r >= 0x3000 && r <= 0x303F) { // CJK 标点
        readable++;
      } else if (r >= 0xFF00 && r <= 0xFFEF) { // 全角
        readable++;
      }
    }
    return total == 0 ? 0 : readable / total;
  }
}
