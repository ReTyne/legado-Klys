import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
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

      var content = utf8.decode(candidates.first.content as List<int>, allowMalformed: true);

      // 提取正文（去除HTML标签）
      return _extractText(content);
    } catch (e) {
      return null;
    }
  }

  /// 统计 EPUB 正文字数：遍历 zip 内 xhtml/html 正文文档，
  /// 累计「去标签文本」长度（跳过 nav/toc/cover 等非正文文档）。
  static Future<int> getWordCount(String filePath) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      var count = 0;
      for (final f in archive.files) {
        if (!f.isFile) continue;
        final name = f.name.toLowerCase();
        if (!name.endsWith('.xhtml') && !name.endsWith('.xht') && !name.endsWith('.html')) continue;
        final base = name.split('/').last;
        // 导航 / 目录 / 封面等非正文文档不计入
        if (base.startsWith('nav') || base.startsWith('toc') || base.contains('cover')) continue;
        final raw = utf8.decode(f.content as List<int>, allowMalformed: true);
        count += _extractText(raw).length;
      }
      return count;
    } catch (e) {
      return 0;
    }
  }

  /// 提取 EPUB 封面图片到缓存目录，返回本地路径；找不到封面时返回 null。
  ///
  /// 查找顺序：OPF `<meta name="cover">` 指向的 manifest item →
  /// manifest 中 href 含 cover 的图片项 → manifest 首个图片项。
  static Future<String?> getCoverImage(String filePath) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      // 1. 定位 OPF
      ArchiveFile? opf;
      for (final f in archive.files) {
        if (f.isFile && f.name.toLowerCase().endsWith('.opf')) {
          opf = f;
          break;
        }
      }
      if (opf == null) return null;
      final opfContent = utf8.decode(opf.content as List<int>, allowMalformed: true);
      final opfDir = opf.name.contains('/')
          ? opf.name.substring(0, opf.name.lastIndexOf('/') + 1)
          : '';

      // 2. OPF meta cover → manifest item id
      String? coverHref;
      final metaCover = RegExp(r'<meta\s+name="cover"\s+content="([^"]+)"',
              caseSensitive: false)
          .firstMatch(opfContent);
      if (metaCover != null) {
        final id = RegExp.escape(metaCover.group(1)!);
        final item = RegExp('<item\\s+[^>]*id="$id"[^>]*href="([^"]+)"',
                caseSensitive: false)
            .firstMatch(opfContent) ??
            RegExp('<item\\s+[^>]*href="([^"]+)"[^>]*id="$id"',
                caseSensitive: false)
                .firstMatch(opfContent);
        if (item != null) coverHref = item.group(1);
      }

      // 3. 兜底：manifest 中 href 含 cover 的图片项；再兜底取首个图片项
      if (coverHref == null) {
        for (final m in RegExp(r'<item\s+[^>]*>', caseSensitive: false)
            .allMatches(opfContent)) {
          final tag = m.group(0)!;
          final href = RegExp(r'href="([^"]+)"').firstMatch(tag)?.group(1);
          final media =
              RegExp(r'media-type="([^"]+)"').firstMatch(tag)?.group(1) ?? '';
          if (href == null || !media.startsWith('image/')) continue;
          if (href.toLowerCase().contains('cover')) {
            coverHref = href;
            break;
          }
          coverHref ??= href;
        }
      }
      if (coverHref == null) return null;

      // 4. 在 zip 内定位封面条目（相对 OPF 目录解析）
      final entryName = _resolveEntry(opfDir, coverHref);
      ArchiveFile? entry;
      for (final f in archive.files) {
        if (f.isFile && (f.name == entryName || f.name.endsWith(coverHref))) {
          entry = f;
          break;
        }
      }
      if (entry == null) return null;

      // 5. 写入缓存目录 covers/ 下
      final tmp = await getTemporaryDirectory();
      final coverDir = Directory('${tmp.path}/covers');
      if (!coverDir.existsSync()) coverDir.createSync(recursive: true);
      final base = entry.name.split('/').last.replaceAll(RegExp(r'[^\w\.\-]'), '_');
      final out = File('${coverDir.path}/${filePath.hashCode.abs()}_$base');
      await out.writeAsBytes(entry.content as List<int>);
      return out.path;
    } catch (e) {
      return null;
    }
  }

  /// HTML → 纯文本（parseChapterContent 与字数统计共用）。
  static String _extractText(String html) {
    final bodyMatch = RegExp(r'<body[^>]*>(.*?)</body>', dotAll: true, caseSensitive: false)
        .firstMatch(html);
    var text = bodyMatch?.group(1) ?? html;

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
  }

  /// 把 OPF 相对 href 解析为 zip 内条目名（处理 ./ ../ 与 URL 编码）。
  static String _resolveEntry(String opfDir, String href) {
    var h = href.split('#').first;
    try {
      h = Uri.decodeComponent(h);
    } catch (_) {
      // 非法编码序列保持原样
    }
    final parts = <String>[];
    for (final seg in '$opfDir$h'.split('/')) {
      if (seg.isEmpty || seg == '.') continue;
      if (seg == '..') {
        if (parts.isNotEmpty) parts.removeLast();
        continue;
      }
      parts.add(seg);
    }
    return parts.join('/');
  }
}
