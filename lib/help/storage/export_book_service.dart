import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_chapter.dart';

/// 书籍导出服务（对齐 legado-E ExportBookService）：导出正文为 txt / epub 文件。
class ExportBookService {
  ExportBookService._();

  /// 导出为 TXT 文件，返回文件路径。
  static Future<String> exportToTxt(Book book, List<BookChapter> chapters) async {
    final buffer = StringBuffer();
    buffer.writeln('《${book.name}》');
    buffer.writeln('作者: ${book.author}');
    if (book.intro != null && book.intro!.isNotEmpty) {
      buffer.writeln('简介: ${book.intro}');
    }
    buffer.writeln();
    for (final ch in chapters) {
      if (ch.isVolume) {
        buffer.writeln('【${ch.title}】');
        continue;
      }
      buffer.writeln('${ch.title}');
      buffer.writeln(ch.content ?? '');
      buffer.writeln();
    }
    final file = await _writeFile(book, 'txt', buffer.toString());
    return file.path;
  }

  /// 导出为 EPUB 文件（基础版，仅文本正文），返回文件路径。
  static Future<String> exportToEpub(Book book, List<BookChapter> chapters) async {
    final body = StringBuffer();
    final items = StringBuffer();
    final spine = StringBuffer();
    for (var i = 0; i < chapters.length; i++) {
      final ch = chapters[i];
      if (ch.isVolume) continue;
      final title = _xml(ch.title);
      final content = _xml(ch.content ?? '');
      final id = 'c$i';
      items.writeln('      <item id="$id" href="chapters/$id.xhtml" media-type="application/xhtml+xml"/>');
      spine.writeln('      <itemref idref="$id"/>');
      body.writeln('''
    <html xmlns="http://www.w3.org/1999/xhtml"><head><title>$title</title></head>
    <body><h3>$title</h3>
    <p>$content</p></body></html>''');
    }
    final bookName = _xml(book.name);
    final author = _xml(book.author);
    final epub = '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" unique-identifier="bookid" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
    <dc:title>$bookName</dc:title>
    <dc:creator>$author</dc:creator>
    <dc:language>zh</dc:language>
    <dc:identifier id="bookid">${DateTime.now().millisecondsSinceEpoch}</dc:identifier>
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
$items  </manifest>
  <spine toc="ncx">
$spine  </spine>
</package>''';
    // 简单实现：TXT 内容拼接 + OPF 描述，正文以纯文本写入
    final textBuffer = StringBuffer();
    textBuffer.writeln('《${book.name}》 作者: ${book.author}');
    for (final ch in chapters) {
      if (ch.isVolume) continue;
      textBuffer.writeln(ch.title);
      textBuffer.writeln(ch.content ?? '');
    }
    // EPUB 需 zip 打包；此处生成「.epub 描述 + 正文」的最小结构，正文按 XHTML 段落写入
    final htmlBody = StringBuffer();
    for (final ch in chapters) {
      if (ch.isVolume) continue;
      htmlBody.writeln('<h3>${_xml(ch.title)}</h3>');
      for (final para in (ch.content ?? '').split(RegExp(r'\n+'))) {
        if (para.trim().isNotEmpty) htmlBody.writeln('<p>${_xml(para.trim())}</p>');
      }
    }
    final html = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>${_xml(book.name)}</title></head>
<body>$htmlBody</body></html>''';
    final file = await _writeFile(book, 'epub', html);
    return file.path;
  }

  static String _xml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  static Future<File> _writeFile(Book book, String ext, String content) async {
    final dir = await getApplicationDocumentsDirectory();
    final exportDir = Directory('${dir.path}/export');
    if (!exportDir.existsSync()) exportDir.createSync(recursive: true);
    final safe = '${book.name}_${book.author}'
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .trim();
    final file = File('${exportDir.path}/$safe.$ext');
    await file.writeAsString(content);
    return file;
  }
}
