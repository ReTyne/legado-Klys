import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/help/storage/export_book_service.dart';

Uint8List _build() => ExportBookService.buildEpub(
      name: '测试书',
      author: '作者',
      titles: const ['第一章', '第二章'],
      contents: const ['正文一\n第二段', '正文二'],
      seed: 1,
    );

void main() {
  group('EPUB 导出结构', () {
    test('mimetype 位于首位且为不压缩存储', () {
      final archive = ZipDecoder().decodeBytes(_build());
      expect(archive.isNotEmpty, isTrue);
      final first = archive[0];
      expect(first.name, 'mimetype');
      // 规范要求 mimetype 必须 STORE
      expect(first.isCompressed, isFalse);
      expect(utf8.decode(first.content as List<int>), 'application/epub+zip');
    });

    test('包含 container / opf / ncx / css / 章节条目', () {
      final archive = ZipDecoder().decodeBytes(_build());
      expect(archive.findFile('META-INF/container.xml'), isNotNull);
      expect(archive.findFile('OEBPS/content.opf'), isNotNull);
      expect(archive.findFile('OEBPS/toc.ncx'), isNotNull);
      expect(archive.findFile('OEBPS/style.css'), isNotNull);
      expect(archive.findFile('OEBPS/chapters/c0.xhtml'), isNotNull);
      expect(archive.findFile('OEBPS/chapters/c1.xhtml'), isNotNull);
    });

    test('正文按段落拆成 <p>，标题做了 XML 转义', () {
      final bytes = ExportBookService.buildEpub(
        name: '书名<&>',
        author: '作者',
        titles: const ['第一章'],
        contents: const ['第一段\n\n第二段'],
        seed: 2,
      );
      final archive = ZipDecoder().decodeBytes(bytes);
      final xhtml = utf8.decode(
          archive.findFile('OEBPS/chapters/c0.xhtml')!.content as List<int>);
      expect(xhtml.contains('<p>第一段</p>'), isTrue);
      expect(xhtml.contains('<p>第二段</p>'), isTrue);

      final opf = utf8.decode(
          archive.findFile('OEBPS/content.opf')!.content as List<int>);
      expect(opf.contains('书名&lt;&amp;&gt;'), isTrue);
      expect(opf.contains('itemref idref="c0"'), isTrue);
    });

    test('正文为空时补占位章节，仍产出合法 zip', () {
      final bytes = ExportBookService.buildEpub(
        name: '空书',
        author: '',
        titles: const [],
        contents: const [],
        seed: 3,
      );
      final archive = ZipDecoder().decodeBytes(bytes);
      expect(archive.isNotEmpty, isTrue);
      expect(archive.findFile('OEBPS/chapters/c0.xhtml'), isNotNull);
      final xhtml = utf8.decode(
          archive.findFile('OEBPS/chapters/c0.xhtml')!.content as List<int>);
      expect(xhtml.contains('暂无'), isTrue);
    });

    test('toc.ncx 与 opf 的章节数一致', () {
      final archive = ZipDecoder().decodeBytes(_build());
      final ncx = utf8.decode(
          archive.findFile('OEBPS/toc.ncx')!.content as List<int>);
      final opf = utf8.decode(
          archive.findFile('OEBPS/content.opf')!.content as List<int>);
      expect('navPoint'.allMatches(ncx).length, 2);
      expect('itemref'.allMatches(opf).length, 2);
    });
  });
}
