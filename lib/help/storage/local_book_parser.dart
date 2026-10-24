import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_chapter.dart';
import 'package:legado_md3/help/source/txt_parser.dart';
import 'epub_parser.dart';

/// 本地书籍解析器 - 支持TXT/EPUB/MOBI/PDF/UMD
class LocalBookParser {
  /// 解析书籍信息
  static Future<Book?> parse(String filePath) async {
    final ext = filePath.split('.').last.toLowerCase();
    switch (ext) {
      case 'txt':
        return _parseTxt(filePath);
      case 'epub':
        return _parseEpub(filePath);
      case 'mobi':
        return _parseMobi(filePath);
      case 'pdf':
        return _parsePdf(filePath);
      case 'umd':
        return _parseUmd(filePath);
      default:
        return null;
    }
  }

  /// 解析目录
  static Future<List<BookChapter>> parseToc(String filePath) async {
    final ext = filePath.split('.').last.toLowerCase();
    switch (ext) {
      case 'txt':
        return _parseTxtToc(filePath);
      case 'epub':
        return _parseEpubToc(filePath);
      case 'mobi':
        return _parseMobiToc(filePath);
      case 'pdf':
        return _parsePdfToc(filePath);
      case 'umd':
        return _parseUmdToc(filePath);
      default:
        return [];
    }
  }

  // ========== TXT ==========
  static Future<Book?> _parseTxt(String filePath) async {
    try {
      final file = File(filePath);
      final name = file.uri.pathSegments.last.replaceAll('.txt', '');
      // 统计正文字数（与 import_book_service 的 txt 分支口径一致：全文长度）
      int? wordCount;
      try {
        final content = await TxtParserService.readFileAutoDetect(file);
        wordCount = content.length;
      } catch (_) {
        wordCount = null;
      }
      return Book(
        name: name,
        author: '未知作者',
        local: true,
        type: 1,
        fileName: filePath,
        canUpdate: false,
        wordCount: wordCount,
      );
    } catch (e) {
      return null;
    }
  }

  static Future<List<BookChapter>> _parseTxtToc(String filePath) async {
    try {
      final file = File(filePath);
      final content = await TxtParserService.readFileAutoDetect(file);
      final lines = content.split('\n');
      final chapters = <BookChapter>[];
      final chapterRegex = RegExp(r'^\s*(第[一二三四五六七八九十百千万零〇两\d]+[章节回卷集部篇][^\n]*)|^\s*(\d+[\.、][^\n]+)|^\s*([【\[][^\n]+[】\]])');
      var index = 0;
      for (final line in lines) {
        final match = chapterRegex.firstMatch(line);
        if (match != null) {
          chapters.add(BookChapter(
            title: match.group(0)!.trim(),
            url: 'txt://$index',
            index: index++,
            isVolume: false,
          ));
        }
      }
      if (chapters.isEmpty) {
        chapters.add(BookChapter(title: '正文', url: 'txt://0', index: 0, isVolume: false));
      }
      return chapters;
    } catch (e) {
      return [BookChapter(title: '正文', url: 'txt://0', index: 0, isVolume: false)];
    }
  }

  // ========== EPUB ==========
  static Future<Book?> _parseEpub(String filePath) async {
    try {
      // 元数据优先取 OPF（书名/作者/简介），失败回退按文件名建 Book
      final book = await EpubParser.parse(filePath) ??
          Book(
            name: File(filePath).uri.pathSegments.last.replaceAll('.epub', ''),
            author: '未知作者',
            local: true,
            type: 1,
            fileName: filePath,
            canUpdate: false,
          );
      // 字数统计：累计各正文章节文本长度
      final wordCount = await EpubParser.getWordCount(filePath);
      if (wordCount > 0) book.wordCount = wordCount;
      // 封面：仅当 book.coverUrl 为空时写入（避免覆盖已有封面）
      if (book.coverUrl == null || book.coverUrl!.isEmpty) {
        final cover = await EpubParser.getCoverImage(filePath);
        if (cover != null) book.coverUrl = cover;
      }
      return book;
    } catch (e) {
      return null;
    }
  }

  static Future<List<BookChapter>> _parseEpubToc(String filePath) async {
    final toc = await EpubParser.parseToc(filePath);
    return toc.isEmpty
        ? [BookChapter(title: '正文', url: 'epub://0', index: 0, isVolume: false)]
        : toc;
  }

  // ========== MOBI ==========
  // TODO: mobi 仅支持 PalmDOC 正文提取，元数据/封面/字数统计待补
  static Future<Book?> _parseMobi(String filePath) async {
    try {
      final file = File(filePath);
      final name = file.uri.pathSegments.last.replaceAll('.mobi', '');
      return Book(name: name, author: '未知作者', local: true, type: 1, fileName: filePath, canUpdate: false);
    } catch (e) {
      return null;
    }
  }

  static Future<List<BookChapter>> _parseMobiToc(String filePath) async {
    return [BookChapter(title: '正文', url: 'mobi://0', index: 0, isVolume: false)];
  }

  // ========== PDF ==========
  // TODO: pdf 仅支持基础文本流提取，元数据/封面/字数统计待补
  static Future<Book?> _parsePdf(String filePath) async {
    try {
      final file = File(filePath);
      final name = file.uri.pathSegments.last.replaceAll('.pdf', '');
      return Book(name: name, author: '未知作者', local: true, type: 1, fileName: filePath, canUpdate: false);
    } catch (e) {
      return null;
    }
  }

  static Future<List<BookChapter>> _parsePdfToc(String filePath) async {
    return [BookChapter(title: '正文', url: 'pdf://0', index: 0, isVolume: false)];
  }

  // ========== UMD ==========
  // TODO: umd 为漫画格式，需走漫画阅读器，书籍元数据/字数统计待补
  static Future<Book?> _parseUmd(String filePath) async {
    try {
      final file = File(filePath);
      final name = file.uri.pathSegments.last.replaceAll('.umd', '');
      return Book(name: name, author: '未知作者', local: true, type: 1, fileName: filePath, canUpdate: false);
    } catch (e) {
      return null;
    }
  }

  static Future<List<BookChapter>> _parseUmdToc(String filePath) async {
    return [BookChapter(title: '正文', url: 'umd://0', index: 0, isVolume: false)];
  }

  /// 读取本地书籍指定章节内容（通用入口）
  static Future<String?> readChapter(String filePath, int chapterIndex, List<BookChapter> chapters) async {
    final ext = filePath.split('.').last.toLowerCase();
    switch (ext) {
      case 'txt':
        return readTxtChapter(filePath, chapterIndex, chapters);
      case 'epub':
        return _readEpubChapter(filePath, chapterIndex, chapters);
      case 'mobi':
        return _readMobiChapter(filePath);
      case 'pdf':
        return _readPdfChapter(filePath);
      case 'umd':
        return _readSimpleChapter(filePath, 'UMD 为漫画格式，请使用漫画阅读器（当前版本暂未接入 UMD 图片解析）');
      default:
        return null;
    }
  }

  static Future<String?> _readSimpleChapter(String filePath, String message) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        return '$message\n\n文件：${file.uri.pathSegments.last}';
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _readEpubChapter(String filePath, int chapterIndex, List<BookChapter> chapters) async {
    // 优先用传入目录里的章节 url 解析
    if (chapterIndex >= 0 && chapterIndex < chapters.length) {
      final url = chapters[chapterIndex].url;
      if (url.isNotEmpty && !url.startsWith('epub://')) {
        final content = await EpubParser.parseChapterContent(filePath, url);
        if (content != null && content.isNotEmpty) return content;
      }
    }
    // 兜底：重新解析目录后按下标取章节
    final toc = await EpubParser.parseToc(filePath);
    if (chapterIndex >= 0 && chapterIndex < toc.length) {
      return EpubParser.parseChapterContent(filePath, toc[chapterIndex].url);
    }
    return null;
  }

  /// 读取TXT章节内容。
  /// 优先按 startPos/endPos（规范化文本 `LineSplitter.convert(content).join('\n')`
  /// 的字符区间）直取——长章节拆分后的子章节标题为 `原标题(n)`，标题匹配会失效；
  /// 无位置信息时回退按标题匹配（兼容旧库数据）。
  static Future<String?> readTxtChapter(String filePath, int chapterIndex, List<BookChapter> chapters) async {
    try {
      final file = File(filePath);
      final content = await TxtParserService.readFileAutoDetect(file);
      if (chapterIndex >= chapters.length) return null;
      final chapter = chapters[chapterIndex];
      // 位置优先：拆分前后的章节均带区间，直接切片（读取侧做同一规范化，保证偏移可复现）
      if (chapter.startPos != null && chapter.endPos != null) {
        final normalized = const LineSplitter().convert(content).join('\n');
        var s = chapter.startPos!.clamp(0, normalized.length);
        var e = chapter.endPos!.clamp(0, normalized.length);
        if (s > e) {
          final t = s;
          s = e;
          e = t;
        }
        return normalized.substring(s, e).trim();
      }
      final lines = content.split('\n');
      final title = chapter.title;
      var startIdx = -1;
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trim() == title.trim()) {
          startIdx = i + 1;
          break;
        }
      }
      if (startIdx == -1) return null;
      var endIdx = lines.length;
      if (chapterIndex + 1 < chapters.length) {
        final nextTitle = chapters[chapterIndex + 1].title;
        for (var i = startIdx; i < lines.length; i++) {
          if (lines[i].trim() == nextTitle.trim()) {
            endIdx = i;
            break;
          }
        }
      }
      return lines.sublist(startIdx, endIdx).join('\n').trim();
    } catch (e) {
      return null;
    }
  }

  // ========== MOBI（PalmDOC 解压 + HTML 提取） ==========
  /// 读取 MOBI 章节正文（基础实现：提取整本正文，目录暂按单章处理）。
  static Future<String?> _readMobiChapter(String filePath) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      final text = _extractMobiText(bytes);
      if (text == null || text.trim().isEmpty) {
        return 'MOBI 解析失败：文件结构无法识别。';
      }
      return text;
    } catch (e) {
      return null;
    }
  }

  /// 解析 MOBI/PalmDB 结构并解压 PalmDOC 文本。
  static String? _extractMobiText(List<int> bytes) {
    if (bytes.length < 78) return null;
    // PalmDB header：offset 76 处的 2 字节为 record 数量
    final numRecords = _be16(bytes, 76);
    if (numRecords <= 0) return null;
    // record info list：offset 78 起，每条 8 字节（offset 4B + attr 1B + uniqueID 3B）
    final offsets = <int>[];
    for (var i = 0; i < numRecords; i++) {
      final p = 78 + i * 8;
      if (p + 8 > bytes.length) break;
      offsets.add(_be32(bytes, p));
    }
    if (offsets.isEmpty) return null;

    // record 0 = PalmDOC header（16 字节）：compression / textLength / recordCount
    var compression = 1;
    var textLength = 0;
    var recordCount = 0;
    final hdr = offsets[0];
    if (hdr + 16 <= bytes.length) {
      compression = _be16(bytes, hdr);
      textLength = _be32(bytes, hdr + 4);
      recordCount = _be16(bytes, hdr + 8);
    }

    // 文本 record：从 record 1 开始，共 recordCount 条
    var total = recordCount > 0 && recordCount + 1 <= offsets.length
        ? recordCount + 1
        : offsets.length;
    final buf = <int>[];
    for (var i = 1; i < total && i < offsets.length; i++) {
      final start = offsets[i];
      final end = i + 1 < offsets.length ? offsets[i + 1] : bytes.length;
      if (start >= end || start >= bytes.length) continue;
      buf.addAll(bytes.sublist(start, end));
    }

    List<int> text;
    if (compression == 2) {
      text = _palmDocDecompress(buf);
    } else if (compression == 17480) {
      // HUFF/CDIC 压缩（Kindle 专用），暂不支持
      return null;
    } else {
      text = buf;
    }
    if (textLength > 0 && text.length > textLength) text = text.sublist(0, textLength);

    String html;
    try {
      html = utf8.decode(text);
    } catch (_) {
      html = latin1.decode(text);
    }
    return _htmlToText(html);
  }

  /// PalmDOC LZ77 解压。
  static List<int> _palmDocDecompress(List<int> src) {
    final out = <int>[];
    var i = 0;
    while (i < src.length) {
      final c = src[i++];
      if (c == 0) {
        if (i < src.length) out.add(src[i++]);
      } else if (c <= 8) {
        for (var j = 0; j < c && i < src.length; j++) out.add(src[i++]);
      } else if (c <= 0x7f) {
        out.add(c);
      } else if (c <= 0xbf) {
        if (i >= src.length) break;
        final len = ((c >> 5) & 3) + 3;
        final dist = ((c & 0x1f) << 8) + src[i++];
        _copyBack(out, dist, len);
      } else {
        if (i + 1 >= src.length) break;
        final b1 = src[i++];
        final b2 = src[i++];
        final len = ((c >> 3) & 7) + 3;
        final dist = ((c & 7) << 16) + (b1 << 8) + b2;
        _copyBack(out, dist, len);
      }
    }
    return out;
  }

  static void _copyBack(List<int> out, int dist, int len) {
    for (var j = 0; j < len; j++) {
      final idx = out.length - dist;
      out.add(idx >= 0 && idx < out.length ? out[idx] : 0);
    }
  }

  // ========== PDF（基础文本流提取） ==========
  static Future<String?> _readPdfChapter(String filePath) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      final text = _extractPdfText(bytes);
      if (text == null || text.trim().isEmpty) {
        return 'PDF 解析失败：可能是扫描版/图片型 PDF，无法提取文本。';
      }
      return text;
    } catch (e) {
      return null;
    }
  }

  /// 基础 PDF 文本提取：定位所有 stream，FlateDecode 解压后抽取 Tj/TJ 文本操作符。
  static String? _extractPdfText(List<int> bytes) {
    final sb = StringBuffer();
    // 逐字节扫描 "stream ... endstream"
    final marker = ascii.encode('stream');
    final endMarker = ascii.encode('endstream');
    var i = 0;
    while (i < bytes.length - 6) {
      // 找 "stream"
      var found = true;
      for (var k = 0; k < marker.length; k++) {
        if (bytes[i + k] != marker[k]) { found = false; break; }
      }
      if (!found) { i++; continue; }
      // 跳过 stream 后的换行
      var start = i + marker.length;
      if (start < bytes.length && (bytes[start] == 0x0d || bytes[start] == 0x0a)) {
        start++;
        if (start < bytes.length && (bytes[start] == 0x0a || bytes[start] == 0x0d) &&
            bytes[start] != bytes[start - 1]) start++;
      }
      // 找 endstream
      var end = -1;
      for (var j = start; j < bytes.length - 9; j++) {
        var m = true;
        for (var k = 0; k < endMarker.length; k++) {
          if (bytes[j + k] != endMarker[k]) { m = false; break; }
        }
        if (m) { end = j; break; }
      }
      if (end < 0) break;
      var data = bytes.sublist(start, end);
      // 尝试 FlateDecode 解压
      try {
        data = ZLibDecoder().decodeBytes(data);
      } catch (_) {
        // 非压缩流，保持原样
      }
      sb.write(_extractPdfTextOps(latin1.decode(data)));
      i = end + endMarker.length;
    }
    final t = sb.toString().trim();
    return t.isEmpty ? null : t;
  }

  /// 从 PDF 内容流抽取 (text) Tj 与 [..] TJ 操作符中的文本。
  static String _extractPdfTextOps(String stream) {
    final sb = StringBuffer();
    // Tj： (text) Tj
    for (final m in RegExp(r'\(((?:[^()\\]|\\.)*)\)\s*Tj').allMatches(stream)) {
      sb.write(_pdfUnescape(m.group(1) ?? ''));
    }
    // TJ： [ (a) -120 (b) ] TJ —— 逐段提取字符串
    for (final m in RegExp(r'\[((?:[^\[\]\\]|\\.)*)\]\s*TJ', dotAll: true).allMatches(stream)) {
      final inner = m.group(1) ?? '';
      for (final s in RegExp(r'\(((?:[^()\\]|\\.)*)\)').allMatches(inner)) {
        sb.write(_pdfUnescape(s.group(1) ?? ''));
      }
    }
    final t = sb.toString();
    return t.isEmpty ? '' : '$t\n';
  }

  static String _pdfUnescape(String s) {
    return s
        .replaceAllMapped(RegExp(r'\\([nrtbf()\\])'), (m) {
          const map = {'n': '\n', 'r': '\r', 't': '\t', 'b': '\b', 'f': '\f', '(': '(', ')': ')', '\\': '\\'};
          return map[m.group(1)] ?? m.group(0)!;
        })
        .replaceAllMapped(RegExp(r'\\([0-7]{1,3})'), (m) {
          return String.fromCharCode(int.parse(m.group(1)!, radix: 8));
        });
  }

  /// HTML → 纯文本（复用 EPUB 的块级换行与实体处理思路）。
  static String _htmlToText(String html) {
    var text = html;
    final body = RegExp(r'<body[^>]*>(.*)</body>', dotAll: true, caseSensitive: false).firstMatch(text);
    text = body?.group(1) ?? text;
    text = text.replaceAll(RegExp(r'</(p|div|h[1-6]|li|blockquote|tr)>', caseSensitive: false), '\n');
    text = text.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    text = text.replaceAll(RegExp(r'<[^>]+>'), '');
    text = text
        .replaceAll('&nbsp;', ' ').replaceAll('&amp;', '&').replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>').replaceAll('&quot;', '"').replaceAll('&#39;', "'")
        .replaceAll('&hellip;', '…').replaceAll('&mdash;', '—').replaceAll('&ndash;', '–');
    text = text.replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m.group(1)!)));
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    return text;
  }

  // ========== 大端字节工具 ==========
  static int _be16(List<int> b, int off) => (b[off] << 8) | b[off + 1];
  static int _be32(List<int> b, int off) =>
      (b[off] << 24) | (b[off + 1] << 16) | (b[off + 2] << 8) | b[off + 3];
}
