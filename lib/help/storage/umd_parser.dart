import 'dart:io';
import 'dart:typed_data';
import 'package:enough_convert/enough_convert.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_chapter.dart';

/// UMD 手机电子书解析器（容错实现）
/// UMD 由 TLV 块构成：1 字节 type + 4 字节(大端)长度 + data。
/// 0x02 书名 0x03 作者 0x87 章节标题 0x83 正文(data 首字节为随机填充)。
class UmdParser {
  static Future<({Book book, List<BookChapter> chapters})?> parse(String path) async {
    final bytes = await File(path).readAsBytes();
    if (bytes.isEmpty) return null;

    String? title;
    String? author;
    final chapterTitles = <String>[];
    final contentBuf = StringBuffer();
    final chapterBodies = <String>[];

    int i = 0;
    while (i + 5 < bytes.length) {
      final type = bytes[i] & 0xff;
      final len = ((bytes[i + 1] & 0xff) << 24) | ((bytes[i + 2] & 0xff) << 16) |
          ((bytes[i + 3] & 0xff) << 8) | (bytes[i + 4] & 0xff);
      // 合理长度才认为是 TLV，否则前进 1 字节继续扫描
      if (len <= 0 || len > bytes.length || i + 5 + len > bytes.length) {
        i++;
        continue;
      }
      final data = bytes.sublist(i + 5, i + 5 + len);
      try {
        switch (type) {
          case 0x02:
            title = _decodeText(data);
            break;
          case 0x03:
            author = _decodeText(data);
            break;
          case 0x87: // 章节标题，首字节随机填充
            if (data.length > 1) {
              chapterBodies.add(contentBuf.toString());
              contentBuf.clear();
              chapterTitles.add(_decodeText(data.sublist(1)));
            }
            break;
          case 0x83: // 正文，首字节随机填充
            if (data.length > 1) contentBuf.write(_decodeText(data.sublist(1)));
            break;
        }
      } catch (_) {}
      i += 5 + len;
    }
    chapterBodies.add(contentBuf.toString());

    final allText = chapterBodies.join();
    if (allText.trim().isEmpty && chapterTitles.isEmpty) return null;

    final chapters = <BookChapter>[];
    if (chapterTitles.isEmpty) {
      chapters.add(BookChapter(index: 0, title: '正文', url: '', content: allText));
    } else {
      for (var c = 0; c < chapterTitles.length; c++) {
        final body = c < chapterBodies.length ? chapterBodies[c] : '';
        chapters.add(BookChapter(index: c, title: chapterTitles[c], url: '', content: body));
      }
    }

    final book = Book(
      name: (title != null && title.isNotEmpty) ? title : path.split('/').last.replaceAll('.umd', ''),
      author: (author != null && author.isNotEmpty) ? author : '未知作者',
      local: true, canUpdate: false,
    );
    return (book: book, chapters: chapters);
  }

  /// UMD 文本优先 UTF-16LE，失败回退 GBK
  static String _decodeText(List<int> data) {
    if (data.isEmpty) return '';
    final zeroRatio = data.where((b) => b == 0).length / data.length;
    if (data.length.isEven && zeroRatio > 0.15) {
      try {
        final u16 = Uint16List.view(Uint8List.fromList(data).buffer);
        final sb = StringBuffer();
        for (final c in u16) {
          if (c != 0 && c != 0xfeff) sb.writeCharCode(c);
        }
        final s = sb.toString();
        if (s.isNotEmpty) return s;
      } catch (_) {}
    }
    try {
      return GbkCodec().decode(data);
    } catch (_) {
      return String.fromCharCodes(data.map((b) => b & 0xff));
    }
  }
}
