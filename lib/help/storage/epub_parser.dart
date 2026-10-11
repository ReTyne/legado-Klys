import 'dart:io';
import 'package:archive/archive.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_chapter.dart';

/// EPUB书籍解析器
class EpubParser {
  /// 解析EPUB文件
  static Future<Book?> parse(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      // 查找OPF文件
      String? opfPath;
      for (final file in archive.files) {
        if (file.name.endsWith('.opf')) {
          opfPath = file.name;
          break;
        }
      }

      if (opfPath == null) return null;

      final opfFile = archive.files.firstWhere((f) => f.name == opfPath);
      final opfContent = String.fromCharCodes(opfFile.content as List<int>);

      // 解析书名和作者
      final titleMatch = RegExp(r'<dc:title>([^<]+)</dc:title>').firstMatch(opfContent);
      final creatorMatch = RegExp(r'<dc:creator[^>]*>([^<]+)</dc:creator>').firstMatch(opfContent);
      final descMatch = RegExp(r'<dc:description>([^<]+)</dc:description>').firstMatch(opfContent);

      final book = Book(
        name: titleMatch?.group(1) ?? '未知书籍',
        author: creatorMatch?.group(1) ?? '未知作者',
        intro: descMatch?.group(1),
        local: true,
        type: 1,
        fileName: filePath,
        canUpdate: false,
      );

      return book;
    } catch (e) {
      return null;
    }
  }

  /// 解析EPUB目录（同时支持 EPUB2 toc.ncx 与 EPUB3 nav.xhtml）
  static Future<List<BookChapter>> parseToc(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return [];

      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final chapters = <BookChapter>[];
      var index = 0;

      // 1) EPUB2: toc.ncx
      final ncx = archive.files.where((f) => f.name.endsWith('toc.ncx')).toList();
      if (ncx.isNotEmpty) {
        final tocContent = String.fromCharCodes(ncx.first.content as List<int>);
        final navPoints = RegExp(r'<navPoint[^>]*>.*?<text>([^<]+)</text>.*?<content src="([^"]+)"', dotAll: true).allMatches(tocContent);
        for (final match in navPoints) {
          chapters.add(BookChapter(
            title: match.group(1) ?? '第${index + 1}章',
            url: (match.group(2) ?? '').split('#').first,
            index: index++,
            isVolume: false,
          ));
        }
      }

      // 2) EPUB3: nav.xhtml / nav.html（toc.ncx 缺失或为空时兜底）
      if (chapters.isEmpty) {
        final nav = archive.files.where((f) => f.name.endsWith('nav.xhtml') || f.name.endsWith('nav.html') || f.name.endsWith('nav.xht')).toList();
        if (nav.isNotEmpty) {
          final navContent = String.fromCharCodes(nav.first.content as List<int>);
          // 取 epub:type="toc" 区域内的链接（若无则取全部 nav 链接）
          final tocRegion = RegExp(r'<nav[^>]*epub:type="toc"[^>]*>(.*?)</nav>', dotAll: true).firstMatch(navContent)?.group(1) ?? navContent;
          final links = RegExp(r'<a[^>]+href="([^"]+)"[^>]*>(.*?)</a>', dotAll: true).allMatches(tocRegion);
          for (final match in links) {
            final title = (match.group(2) ?? '').replaceAll(RegExp(r'<[^>]+>'), '').trim();
            final href = (match.group(1) ?? '').split('#').first;
            if (title.isEmpty || href.isEmpty) continue;
            chapters.add(BookChapter(title: title, url: href, index: index++, isVolume: false));
          }
        }
      }

      return chapters;
    } catch (e) {
      return [];
    }
  }

  /// 解析EPUB章节内容
  static Future<String?> parseChapterContent(String filePath, String chapterUrl) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;
      // 去掉锚点，取相对文件名用于匹配
      final target = chapterUrl.split('#').first.split('/').last;

      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      // 查找章节文件（精确 basename 优先，其次包含匹配）
      var candidates = archive.files.where((f) => f.name.split('/').last == target).toList();
      if (candidates.isEmpty) candidates = archive.files.where((f) => f.name.endsWith(target) || f.name.contains(chapterUrl.split('#').first)).toList();
      if (candidates.isEmpty) return null;

      var content = String.fromCharCodes(candidates.first.content as List<int>);

      // 提取正文（去除HTML标签）
      final bodyMatch = RegExp(r'<body[^>]*>(.*?)</body>', dotAll: true).firstMatch(content);
      var text = bodyMatch?.group(1) ?? content;

      // 块级标签转换行
      text = text.replaceAll(RegExp(r'</(p|div|h[1-6]|li|blockquote)>', caseSensitive: false), '\n');
      text = text.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
      // 去除其余HTML标签
      text = text.replaceAll(RegExp(r'<[^>]+>'), '');
      // 常见 HTML 实体
      text = text
          .replaceAll('&nbsp;', ' ').replaceAll('&amp;', '&').replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>').replaceAll('&quot;', '"').replaceAll('&#39;', "'")
          .replaceAll('&hellip;', '…').replaceAll('&mdash;', '—').replaceAll('&ndash;', '–');
      text = text.replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m.group(1)!)));
      text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();

      return text;
    } catch (e) {
      return null;
    }
  }
}
