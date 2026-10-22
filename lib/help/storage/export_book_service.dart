import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
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

  /// 导出为符合 EPUB 2.0.1 规范的 .epub 文件，返回文件路径。
  ///
  /// 目录结构（zip 打包，mimetype 必须位于首位且不压缩）：
  ///   mimetype
  ///   META-INF/container.xml
  ///   OEBPS/content.opf
  ///   OEBPS/toc.ncx
  ///   OEBPS/style.css
  ///   OEBPS/chapters/c0.xhtml ...
  static Future<String> exportToEpub(Book book, List<BookChapter> chapters) async {
    final usable = chapters.where((c) => !c.isVolume).toList();
    final bytes = buildEpub(
      name: book.name,
      author: book.author,
      titles: usable.map((c) => c.title).toList(growable: false),
      contents: usable.map((c) => c.content ?? '').toList(growable: false),
    );
    final dir = await getApplicationDocumentsDirectory();
    final exportDir = Directory('${dir.path}/export');
    if (!exportDir.existsSync()) exportDir.createSync(recursive: true);
    final file = File('${exportDir.path}/${_safeName(book, 'epub')}');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  /// 生成 EPUB 2.0.1 zip 字节。
  ///
  /// 拆成纯函数是为了能在不依赖 `path_provider` 的单元测试里校验
  /// 目录结构与 mimetype 的首位不压缩存储。
  static Uint8List buildEpub({
    required String name,
    required String author,
    required List<String> titles,
    required List<String> contents,
    int seed = 0,
  }) {
    final archive = Archive();
    void add(String path, String content, {bool store = false}) {
      final bytes = utf8.encode(content);
      final file = ArchiveFile(path, bytes.length, bytes);
      // 规范：mimetype 必须 STORE（不压缩）且排第一
      file.compress = !store;
      archive.addFile(file);
    }

    // 1. mimetype（不压缩，第一个条目）
    add('mimetype', 'application/epub+zip', store: true);

    // 2. container.xml
    add(
      'META-INF/container.xml',
      '<?xml version="1.0" encoding="UTF-8"?>\n'
          '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">\n'
          '  <rootfiles>\n'
          '    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>\n'
          '  </rootfiles>\n'
          '</container>\n',
    );

    // 3. 正文条目 + manifest / spine / navMap
    final items = StringBuffer();
    final spine = StringBuffer();
    final navMap = StringBuffer();
    var order = 0;

    void writeChapter(String id, String title, String content) {
      final escTitle = _xml(title);
      final body = StringBuffer();
      for (final para in content.split(RegExp(r'\n+'))) {
        final t = para.trim();
        if (t.isNotEmpty) body.writeln('<p>${_xml(t)}</p>');
      }
      if (body.isEmpty) body.writeln('<p>（本章暂无内容）</p>');
      add(
        'OEBPS/chapters/$id.xhtml',
        '<?xml version="1.0" encoding="UTF-8"?>\n'
            '<!DOCTYPE html>\n'
            '<html xmlns="http://www.w3.org/1999/xhtml">\n'
            '<head><title>$escTitle</title>'
            '<link href="../style.css" rel="stylesheet" type="text/css"/></head>\n'
            '<body><h2>$escTitle</h2>\n$body</body>\n</html>\n',
      );
      items.writeln('    <item id="$id" href="chapters/$id.xhtml" '
          'media-type="application/xhtml+xml"/>');
      spine.writeln('    <itemref idref="$id"/>');
      navMap.writeln('    <navPoint id="navPoint-$order" playOrder="${order + 1}">'
          '<navLabel><text>$escTitle</text></navLabel>'
          '<content src="chapters/$id.xhtml"/></navPoint>');
      order++;
    }

    if (titles.isEmpty) {
      writeChapter('c0', '正文', '（本书暂无已缓存正文，请先下载章节后再导出。）');
    } else {
      for (var i = 0; i < titles.length; i++) {
        writeChapter('c$i', titles[i], i < contents.length ? contents[i] : '');
      }
    }

    // 4. 样式表
    add('OEBPS/style.css', '''
body { margin: 1em; line-height: 1.6; font-family: serif; }
h2 { font-size: 1.2em; text-align: center; margin: 1em 0; }
p { text-indent: 2em; margin: 0 0 0.4em; }
''');

    final uid = 'urn:uuid:${name.hashCode.abs()}-${seed == 0 ? DateTime.now().millisecondsSinceEpoch : seed}';
    final nowUtc = DateTime.now().toUtc().toIso8601String().split('.').first;

    // 5. content.opf
    add(
      'OEBPS/content.opf',
      '<?xml version="1.0" encoding="UTF-8"?>\n'
          '<package xmlns="http://www.idpf.org/2007/opf" unique-identifier="bookid" version="2.0">\n'
          '  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">\n'
          '    <dc:title>${_xml(name)}</dc:title>\n'
          '    <dc:creator opf:role="aut">${_xml(author)}</dc:creator>\n'
          '    <dc:language>zh-CN</dc:language>\n'
          '    <dc:identifier id="bookid">$uid</dc:identifier>\n'
          '    <dc:date>$nowUtc</dc:date>\n'
          '  </metadata>\n'
          '  <manifest>\n'
          '    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>\n'
          '    <item id="css" href="style.css" media-type="text/css"/>\n'
          '$items'
          '  </manifest>\n'
          '  <spine toc="ncx">\n'
          '$spine'
          '  </spine>\n'
          '</package>\n',
    );

    // 6. toc.ncx（目录）
    add(
      'OEBPS/toc.ncx',
      '<?xml version="1.0" encoding="UTF-8"?>\n'
          '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">\n'
          '  <head>\n'
          '    <meta name="dtb:uid" content="$uid"/>\n'
          '    <meta name="dtb:depth" content="1"/>\n'
          '    <meta name="dtb:totalPageCount" content="0"/>\n'
          '    <meta name="dtb:maxPageNumber" content="0"/>\n'
          '  </head>\n'
          '  <docTitle><text>${_xml(name)}</text></docTitle>\n'
          '  <navMap>\n'
          '$navMap'
          '  </navMap>\n'
          '</ncx>\n',
    );

    final encoded = ZipEncoder().encode(archive);
    if (encoded == null) throw StateError('EPUB 打包失败：ZipEncoder 返回空');
    return encoded as Uint8List;
  }

  static String _safeName(Book book, String ext) {
    final safe = '${book.name}_${book.author}'
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .trim();
    return '$safe.$ext';
  }

  static String _xml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static Future<File> _writeFile(Book book, String ext, String content) async {
    final dir = await getApplicationDocumentsDirectory();
    final exportDir = Directory('${dir.path}/export');
    if (!exportDir.existsSync()) exportDir.createSync(recursive: true);
    final file = File('${exportDir.path}/${_safeName(book, ext)}');
    await file.writeAsString(content);
    return file;
  }
}
