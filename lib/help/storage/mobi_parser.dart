import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_chapter.dart';

/// 轻量 MOBI/AZW(Kindle KF7) 解析器
///
/// 支持：PDB 记录读取、PalmDOC LZ77(0x02)/无压缩(0x01) 解压、提取正文 HTML 转纯文本、
/// 按中文章节正则切分目录。不依赖外部库。
/// 说明：KF8(KFX/新 azw) 与 HUFF/CDIC 高压缩不在覆盖范围，失败时由调用方回退。
class MobiParser {
  static Future<({Book book, List<BookChapter> chapters})?> parse(String path) async {
    try {
      final data = await File(path).readAsBytes();
      if (data.length < 80) return null;
      // PDB 书名（0..31，以 0 结尾）
      String? pdbName;
      for (var end = 0; end < 32; end++) {
        if (data[end] == 0) { pdbName = _latin1(data.sublist(0, end)); break; }
      }
      // 记录数量在 offset 76（2 字节 BE）
      final recordCount = (_u16(data, 76));
      if (recordCount <= 0) return null;
      // 记录信息表从 78 开始，每条 8 字节：offset(4) + uniqueId(1) + attr(3)
      final recordOffsets = <int>[];
      for (var i = 0; i < recordCount; i++) {
        final pos = 78 + i * 8;
        if (pos + 4 > data.length) break;
        recordOffsets.add(_u32(data, pos));
      }
      if (recordOffsets.isEmpty) return null;
      List<int> record(int idx) {
        final start = recordOffsets[idx];
        final end = idx + 1 < recordOffsets.length ? recordOffsets[idx + 1] : data.length;
        return data.sublist(start, end);
      }

      final rec0 = record(0);
      if (rec0.length < 0x84) return null;
      final compression = _u16(rec0, 0); // 1=none 2=PalmDOC
      // MOBI header 中 firstImageIndex / firstContentRecordCount：在 "MOBI" magic 后
      // PalmDOC header 占 16 字节，MOBI magic 在 16，firstImageIndex 在 MOBI+0x80=16+128=144
      var firstImageIndex = recordCount - 1;
      if (rec0.length > 148 && _latin1(rec0.sublist(16, 20)) == 'MOBI') {
        final fi = _u32(rec0, 144);
        if (fi > 0 && fi <= recordCount) firstImageIndex = fi;
      }
      // 文本记录：索引 1 .. firstImageIndex-1
      final raw = BytesBuilder();
      for (var i = 1; i < firstImageIndex; i++) {
        var rec = record(i);
        // 每条文本记录前 2 字节为本记录包含的连续记录数（用于多记录章节），解压时忽略首2字节?——PalmDOC 文本记录直接是压缩流
        if (compression == 2) {
          rec = _palmDocInflate(rec);
        }
        raw.add(rec);
      }
      var html = _utf8OrLantin(raw.takeBytes());
      // 去标签转纯文本
      var text = _htmlToText(html);
      if (text.trim().isEmpty) return null;

      final name = (pdbName?.trim().isNotEmpty == true ? pdbName!.trim() : path.split('/').last.replaceAll(RegExp(r'\.mobi$|\.azw$', caseSensitive: false), ''));
      final book = Book(name: name, author: '未知作者', local: true, type: 1, fileName: path, canUpdate: false,
          origin: 'local', originName: '本地书籍', noteUrl: 'local://$path', bookUrl: 'local://$path', wordCount: text.length);

      // 按章节正则切分（与 TXT 一致）
      final chapters = _splitChapters(text);
      book.lastChapter = chapters.isNotEmpty ? chapters.last.title : null;
      return (book: book, chapters: chapters);
    } catch (_) {
      return null;
    }
  }

  /// PalmDOC / LZ77 解压（calibre/KindleUnpack 经典算法）
  static List<int> _palmDocInflate(List<int> d) {
    final out = <int>[];
    var i = 0;
    while (i < d.length) {
      final c = d[i] & 0xFF;
      if (c == 0x00) { out.add(c); i += 1; }
      else if (c >= 0x01 && c <= 0x08) {
        final n = c;
        for (var k = 1; k <= n && i + k < d.length; k++) { out.add(d[i + k] & 0xFF); }
        i += 1 + n;
      } else if (c == 0x09) {
        out.add(0x20);
        if (i + 1 < d.length) out.add(d[i + 1] & 0xFF);
        i += 2;
      } else if (c >= 0x0A && c <= 0x1F) {
        i += 1; // 保留/未定义
      } else if (c >= 0x20 && c <= 0x7F) { out.add(c); i += 1; }
      else if (c >= 0x80 && c <= 0xBF) {
        if (i + 1 >= d.length) break;
        final c2 = d[i + 1] & 0xFF;
        final m = ((c & 0x3F) << 8) | c2;
        final len = (m & 0x07) + 3;
        final dist = (m >> 3) + 1;
        for (var k = 0; k < len; k++) {
          final p = out.length - dist;
          out.add(p >= 0 && p < out.length ? out[p] : 0x20);
        }
        i += 2;
      } else { // 0xC0..0xFF
        final dist = (c & 0x1F) + 1;
        final p = out.length - dist;
        out.add(p >= 0 && p < out.length ? out[p] : 0x20);
        i += 1;
      }
    }
    return out;
  }

  static List<BookChapter> _splitChapters(String text) {
    final lines = text.split('\n');
    final re = RegExp(r'^\s*(第[一二三四五六七八九十百千万零〇两\d]+[章节回卷集部篇][^\n]*|【[^】]+】|\[\S+?\])');
    final titles = <int>[];
    for (var i = 0; i < lines.length; i++) {
      if (re.hasMatch(lines[i].trim())) titles.add(i);
    }
    final chapters = <BookChapter>[];
    if (titles.isEmpty) {
      chapters.add(BookChapter(index: 0, title: '正文', url: '', content: text.trim()));
      return chapters;
    }
    for (var c = 0; c < titles.length; c++) {
      final start = titles[c];
      final end = c + 1 < titles.length ? titles[c + 1] : lines.length;
      chapters.add(BookChapter(
        index: c, title: lines[start].trim(), url: '',
        content: lines.sublist(start, end).join('\n').trim(),
      ));
    }
    return chapters;
  }

  static String _htmlToText(String html) {
    var t = html.replaceAll(RegExp(r'</(p|div|h[1-6]|li|blockquote)>', caseSensitive: false), '\n');
    t = t.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    t = t.replaceAll(RegExp(r'<[^>]+>'), '');
    t = t.replaceAll('&nbsp;', ' ').replaceAll('&amp;', '&').replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>').replaceAll('&quot;', '"').replaceAll('&#39;', "'");
    t = t.replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m.group(1)!)));
    return t.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  static int _u16(List<int> d, int o) => ((d[o] & 0xFF) << 8) | (d[o + 1] & 0xFF);
  static int _u32(List<int> d, int o) => ((d[o] & 0xFF) << 24) | ((d[o + 1] & 0xFF) << 16) | ((d[o + 2] & 0xFF) << 8) | (d[o + 3] & 0xFF);
  static String _latin1(List<int> d) => String.fromCharCodes(d.map((b) => b & 0xFF));
  static String _utf8OrLantin(List<int> d) {
    try { return utf8.decode(d, allowMalformed: false); } catch (_) { return _latin1(d); }
  }
}
