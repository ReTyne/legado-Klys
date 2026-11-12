import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:enough_convert/enough_convert.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_chapter.dart';
import 'package:legado_md3/help/source/txt_parser.dart';
import 'package:legado_md3/help/storage/umd_parser.dart';
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
  // 补齐 MOBI 元数据
  static Future<Book?> _parseMobi(String filePath) async {
    try {
      final file = File(filePath);
      final fallbackName = file.uri.pathSegments.last.replaceAll('.mobi', '');
      final bytes = await file.readAsBytes();
      // PDB 头 + MOBI/EXTH 元数据区（EXTH 100=作者 103=简介 105=主题 503=书名 201=封面偏移）
      final meta = await _readMobiMetadata(bytes, filePath);
      // 正文用现有 PalmDOC/HTML 提取；HUFF/CDIC 时为 null，但元数据（EXTH）仍可读
      final text = _extractMobiText(bytes);
      final wordCount = text?.length;
      // 简介：优先 EXTH 描述/主题，缺失时用正文开头兜底（对齐本地 TXT 简介提取思路）
      final intro = (meta.intro != null && meta.intro!.trim().isNotEmpty)
          ? meta.intro
          : (text != null && text.trim().isNotEmpty ? _introFromText(text) : null);
      return Book(
        name: (meta.title != null && meta.title!.trim().isNotEmpty)
            ? meta.title!
            : fallbackName,
        author: (meta.author != null && meta.author!.trim().isNotEmpty)
            ? meta.author!
            : '未知作者',
        intro: intro,
        coverUrl: meta.coverPath,
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

  static Future<List<BookChapter>> _parseMobiToc(String filePath) async {
    return [BookChapter(title: '正文', url: 'mobi://0', index: 0, isVolume: false)];
  }

  // ========== PDF ==========
  // 补齐 PDF 元数据
  static Future<Book?> _parsePdf(String filePath) async {
    try {
      final file = File(filePath);
      final fallbackName = file.uri.pathSegments.last.replaceAll('.pdf', '');
      final bytes = await file.readAsBytes();
      // 书名/作者/简介优先取 Document Information Dictionary（未压缩对象里的明文）。
      // 现代 PDF 常把 Info 放进压缩对象流，纯 Dart 侧无交叉引用/对象流解码能力
      // （PdfFile 走 Android PdfRenderer，同样不读 Info），且不能新增依赖，
      // 故扫描失败时按约束用「文件名 + 正文流」做可靠兜底。
      final info = _extractPdfInfo(bytes);
      final text = _extractPdfText(bytes);
      final wordCount = text?.length;
      final intro = (info.subject != null && info.subject!.trim().isNotEmpty)
          ? info.subject
          : (text != null && text.trim().isNotEmpty ? _introFromText(text) : null);
      // 封面：PDF 首页渲染依赖原生 PdfRenderer（E: PdfFile.upBookCover），Dart/archive 无对应
      // 能力，作为平台边界保留（coverUrl 可由详情页「自定义封面」补充），不写假路径。
      return Book(
        name: (info.title != null && info.title!.trim().isNotEmpty)
            ? info.title!
            : fallbackName,
        author: (info.author != null && info.author!.trim().isNotEmpty)
            ? info.author!
            : '未知作者',
        intro: intro,
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

  static Future<List<BookChapter>> _parsePdfToc(String filePath) async {
    return [BookChapter(title: '正文', url: 'pdf://0', index: 0, isVolume: false)];
  }

  // ========== UMD ==========
  // 补齐 UMD 元数据
  static Future<Book?> _parseUmd(String filePath) async {
    try {
      final file = File(filePath);
      final fallbackName = file.uri.pathSegments.last.replaceAll('.umd', '');
      // 接线复用已有 UmdParser 的 TLV 解析（书名/作者/章节正文），不重复造轮子
      final res = await UmdParser.parse(filePath);
      final bytes = await file.readAsBytes();
      // 补齐 UmdParser 未覆盖的 bookType(kind) 与 0x82 封面
      final extra = await _readUmdExtra(bytes, filePath);
      final chapters = res?.chapters ?? const <BookChapter>[];
      final text = chapters.map((c) => c.content ?? '').join();
      final wordCount = text.isEmpty ? null : text.length;
      final intro = text.trim().isEmpty ? null : _introFromText(text);
      return Book(
        name: (res != null && res.book.name.trim().isNotEmpty)
            ? res.book.name
            : fallbackName,
        author: (res != null && res.book.author.trim().isNotEmpty)
            ? res.book.author
            : '未知作者',
        intro: intro,
        kind: extra.kind,
        coverUrl: extra.coverPath,
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
      // 补齐 HUFF/CDIC 明确提示：
      // compression=17480(0x4448 'DH') 为 Kindle 高压缩，正文解压暂不支持，
      // 避免笼统报「文件结构无法识别」误导用户；元数据（EXTH）仍可正常提取。
      if (_mobiCompression(bytes) == 17480) {
        return '该 MOBI 使用 HUFF/CDIC 高压缩（Kindle），当前平台暂不支持正文解压；'
            '元数据已按 EXTH 提取，正文请转为 EPUB 或无压缩 MOBI 后重新导入。';
      }
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
    // record info list：offset 78 起，每条 8 字节（offset 4B + attr 1B + uniqueID 3B）
    final offsets = _pdbRecordOffsets(bytes);
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
      // 补齐 HUFF/CDIC 平台边界说明：
      // HUFF/CDIC 需按 HUFF 记录的 256 组码长表构建 Huffman 树，再跨多个 CDIC 字典记录按位解码，
      // E 由 lib/mobi 的原生 HuffCdic 实现；archive/纯 Dart 无等价实现，项目亦缺真实 HUFF/CDIC
      // fixture 可验证，故如实标注为平台边界、不做假实现。元数据（EXTH）在 record0 明文仍可读。
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
        for (var j = 0; j < c && i < src.length; j++) {
          out.add(src[i++]);
        }
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
        data = const ZLibDecoder().decodeBytes(data);
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

  // ========== 元数据补齐：公共工具 ==========

  /// PDB record info list（offset 76 处 2 字节为记录数，78 起每条 8 字节）→ 各记录起始偏移。
  static List<int> _pdbRecordOffsets(List<int> bytes) {
    if (bytes.length < 78) return const [];
    final numRecords = _be16(bytes, 76);
    if (numRecords <= 0) return const [];
    final offsets = <int>[];
    for (var i = 0; i < numRecords; i++) {
      final p = 78 + i * 8;
      if (p + 8 > bytes.length) break;
      offsets.add(_be32(bytes, p));
    }
    return offsets;
  }

  /// 读取 MOBI 压缩类型（record0 前 2 字节），供 HUFF/CDIC 判定。
  static int _mobiCompression(List<int> bytes) {
    final offsets = _pdbRecordOffsets(bytes);
    if (offsets.isEmpty) return 1;
    final r0 = offsets[0];
    return r0 + 2 <= bytes.length ? _be16(bytes, r0) : 1;
  }

  /// 解析 MOBI 元数据区：PDB 书名 + MOBI fullName + EXTH 记录 + 首个图片记录封面。
  /// MobiReader.readMobiEntryHeaders(EXTH) / MobiBook.metadata / MobiFile.upBookCover。
  static Future<_MobiMetadata> _readMobiMetadata(
      List<int> bytes, String filePath) async {
    final meta = _MobiMetadata();
    if (bytes.length < 78) return meta;

    // PDB 头书名（offset 0..31，NUL 结尾）
    for (var end = 0; end < 32 && end < bytes.length; end++) {
      if (bytes[end] == 0) {
        final s = latin1.decode(bytes.sublist(0, end)).trim();
        if (s.isNotEmpty) meta.title = s;
        break;
      }
    }

    final offsets = _pdbRecordOffsets(bytes);
    if (offsets.isEmpty) return meta;
    final r0 = offsets[0];
    if (r0 + 16 > bytes.length) return meta;

    String? exthTitle;
    String? author;
    String? description;
    String? subject;
    String? fullName;
    int? coverRecord;

    if (r0 + 24 <= bytes.length && _ascii(bytes, r0 + 16, 4) == 'MOBI') {
      final mobiLen = _be32(bytes, r0 + 20);
      // fullName（书名）：offset/length 相对 record0 起始
      if (r0 + 92 <= bytes.length) {
        final tOff = _be32(bytes, r0 + 84);
        final tLen = _be32(bytes, r0 + 88);
        if (tLen > 0 && tLen < 4096 && r0 + tOff + tLen <= bytes.length) {
          fullName = _decodeMobiText(bytes.sublist(r0 + tOff, r0 + tOff + tLen));
        }
      }
      // firstResourceIndex（首个图片/资源记录）在 record0 @108
      if (r0 + 112 <= bytes.length) {
        final r = _be32(bytes, r0 + 108);
        if (r > 0 && r < offsets.length) coverRecord = r;
      }
      // EXTH 标志：E 用 readUInt32(128)，部分 MOBI 变体在 MOBI+0x80(144)，两处都探测
      var exthFlag = r0 + 132 <= bytes.length ? _be32(bytes, r0 + 128) : 0;
      if ((exthFlag & 0x40) == 0 && r0 + 148 <= bytes.length) {
        exthFlag = _be32(bytes, r0 + 144);
      }
      if ((exthFlag & 0x40) != 0) {
        // EXTH 紧接 MOBI header；E 用 length+16，个别实现无 16 字节 PalmDOC 前缀
        int? exthStart;
        for (final s in [r0 + 16 + mobiLen, r0 + mobiLen]) {
          if (s + 12 <= bytes.length && _ascii(bytes, s, 4) == 'EXTH') {
            exthStart = s;
            break;
          }
        }
        if (exthStart != null) {
          final count = _be32(bytes, exthStart + 8);
          var p = exthStart + 12;
          for (var i = 0; i < count && p + 8 <= bytes.length; i++) {
            final type = _be32(bytes, p);
            final len = _be32(bytes, p + 4);
            if (len < 8 || p + len > bytes.length) break;
            final data = bytes.sublist(p + 8, p + len);
            final value = _decodeMobiText(data);
            switch (type) {
              case 100: // creator（作者，E: MobiMetadata.author.first）
                author ??= value;
                break;
              case 103: // description（简介，E: MobiMetadata.description）
                description ??= value;
                break;
              case 105: // subject（主题，简介兜底，E: MobiMetadata.subject）
                subject ??= value;
                break;
              case 503: // updated title（书名，E: exth["title"] ?: mobi.title）
                exthTitle ??= value;
                break;
              case 201: // coverOffset（uint，图片记录索引，E: exth["coverOffset"]）
                if (data.length >= 4) {
                  final r = _be32(data, 0);
                  if (r > 0 && r < offsets.length) coverRecord = r;
                }
                break;
            }
            p += len;
          }
        }
      }
    }

    meta.title = _firstNonEmpty([exthTitle, fullName, meta.title]);
    meta.author = author;
    meta.intro = _firstNonEmpty([description, subject]);

    // 封面：取图片记录原始字节写入缓存目录
    if (coverRecord != null && coverRecord < offsets.length) {
      final start = offsets[coverRecord];
      final end = coverRecord + 1 < offsets.length
          ? offsets[coverRecord + 1]
          : bytes.length;
      if (start < end && end <= bytes.length) {
        meta.coverPath = await _writeCover(bytes.sublist(start, end), filePath);
      }
    }
    return meta;
  }

  /// MOBI/EXTH 字符串：textEncoding 65001(UTF-8) 优先，失败按 latin1(1252 近似) 兜底。
  static String _decodeMobiText(List<int> data) {
    if (data.isEmpty) return '';
    var end = data.length;
    while (end > 0 && data[end - 1] == 0) {
      end--;
    }
    final b = data.sublist(0, end);
    if (b.isEmpty) return '';
    try {
      return utf8.decode(b).trim();
    } catch (_) {
      return latin1.decode(b).trim();
    }
  }

  /// 从 PDF 明文扫描 Document Information Dictionary 的 /Title /Author /Subject。
  /// 支持 (...) 字面量与 <...> 十六进制字符串，及 UTF-16 BOM。
  static ({String? title, String? author, String? subject}) _extractPdfInfo(
      List<int> bytes) {
    final raw = latin1.decode(bytes);
    List<int>? decodeMatch(Match? m) {
      if (m == null) return null;
      // <...> 十六进制字符串优先（外层 group(1) 对 hex 也非 null，需先判 group(2)）
      final hex = m.group(2);
      if (hex != null) {
        var h = hex.replaceAll(RegExp(r'\s'), '');
        if (h.length.isOdd) h = '${h}0';
        final out = <int>[];
        for (var i = 0; i + 1 < h.length; i += 2) {
          out.add(int.tryParse(h.substring(i, i + 2), radix: 16) ?? 0);
        }
        return out;
      }
      final literal = m.group(1);
      if (literal != null && literal.length >= 2) {
        return _pdfLiteralBytes(literal.substring(1, literal.length - 1));
      }
      return null;
    }

    String? value(String key) {
      final re = RegExp(
          '/$key' r'\s*(\((?:[^()\\]|\\.)*\)|<([0-9A-Fa-f\s]+)>)');
      final b = decodeMatch(re.firstMatch(raw));
      if (b == null) return null;
      final s = _decodePdfString(b).trim();
      return s.isEmpty ? null : s;
    }

    return (
      title: value('Title'),
      author: value('Author'),
      subject: value('Subject'),
    );
  }

  /// PDF 字面量字符串内容 → 字节（处理 \n \r \t \b \f \( \) \\ 及 1~3 位八进制）。
  static List<int> _pdfLiteralBytes(String s) {
    final out = <int>[];
    for (var i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (c != 0x5c) {
        out.add(c & 0xff);
        continue;
      }
      if (i + 1 >= s.length) {
        out.add(c);
        break;
      }
      final n = s.codeUnitAt(i + 1);
      if (n >= 0x30 && n <= 0x37) {
        var v = n - 0x30;
        var used = 1;
        while (used < 3 && i + 1 + used < s.length) {
          final d = s.codeUnitAt(i + 1 + used);
          if (d < 0x30 || d > 0x37) break;
          v = v * 8 + (d - 0x30);
          used++;
        }
        out.add(v & 0xff);
        i += used;
      } else {
        switch (n) {
          case 0x6e:
            out.add(10);
            break; // \n
          case 0x72:
            out.add(13);
            break; // \r
          case 0x74:
            out.add(9);
            break; // \t
          case 0x62:
            out.add(8);
            break; // \b
          case 0x66:
            out.add(12);
            break; // \f
          default:
            out.add(n & 0xff); // \( \) \\ 等
        }
        i += 1;
      }
    }
    return out;
  }

  /// PDF 字符串字节 → 文本：UTF-16BE/LE BOM 或 PDFDocEncoding(latin1 近似)。
  static String _decodePdfString(List<int> b) {
    if (b.length >= 2 && b[0] == 0xFE && b[1] == 0xFF) {
      final sb = StringBuffer();
      for (var i = 2; i + 1 < b.length; i += 2) {
        sb.writeCharCode((b[i] << 8) | b[i + 1]);
      }
      return sb.toString();
    }
    if (b.length >= 2 && b[0] == 0xFF && b[1] == 0xFE) {
      final sb = StringBuffer();
      for (var i = 2; i + 1 < b.length; i += 2) {
        sb.writeCharCode(b[i] | (b[i + 1] << 8));
      }
      return sb.toString();
    }
    return latin1.decode(b);
  }

  /// UMD TLV 补扫：0x07 bookType(kind) 与 0x82 封面。
  static Future<({String? kind, String? coverPath})> _readUmdExtra(
      List<int> bytes, String filePath) async {
    String? kind;
    String? coverPath;
    var i = 0;
    while (i + 5 <= bytes.length) {
      final type = bytes[i] & 0xff;
      final len = ((bytes[i + 1] & 0xff) << 24) |
          ((bytes[i + 2] & 0xff) << 16) |
          ((bytes[i + 3] & 0xff) << 8) |
          (bytes[i + 4] & 0xff);
      if (len <= 0 || i + 5 + len > bytes.length) {
        i++;
        continue;
      }
      final data = bytes.sublist(i + 5, i + 5 + len);
      if (type == 0x07) {
        kind ??= _decodeUmdText(data);
      } else if (type == 0x82 && coverPath == null) {
        coverPath = await _writeCover(data, filePath);
      }
      i += 5 + len;
    }
    kind = (kind == null || kind.trim().isEmpty) ? null : kind.trim();
    return (kind: kind, coverPath: coverPath);
  }

  /// UMD 文本：优先 UTF-16LE，回退 GBK（复用 enough_convert），再回退 latin1。
  static String _decodeUmdText(List<int> data) {
    if (data.isEmpty) return '';
    final zeroRatio = data.where((b) => b == 0).length / data.length;
    if (data.length.isEven && zeroRatio > 0.15) {
      final sb = StringBuffer();
      for (var i = 0; i + 1 < data.length; i += 2) {
        final c = (data[i] & 0xff) | ((data[i + 1] & 0xff) << 8);
        if (c != 0 && c != 0xfeff) sb.writeCharCode(c);
      }
      final s = sb.toString();
      if (s.isNotEmpty) return s;
    }
    try {
      return const GbkCodec().decode(data).trim();
    } catch (_) {
      return latin1.decode(data).trim();
    }
  }

  /// 图片记录 / UMD 0x82 块写入系统临时目录，返回本地封面路径。
  /// 用 Directory.systemTemp（纯 dart:io，无插件依赖，离线测试可用），按文件 hash 命名。
  static const List<int> _jpgSig = [0xFF, 0xD8, 0xFF];
  static const List<int> _pngSig = [0x89, 0x50, 0x4E, 0x47];
  static const List<int> _gifSig = [0x47, 0x49, 0x46];

  static Future<String?> _writeCover(List<int> data, String filePath) async {
    // 前 16 字节内扫描图片 magic（个别实现带前置填充字节）
    for (var start = 0; start < data.length && start < 16; start++) {
      String? ext;
      if (_matchSig(data, start, _jpgSig)) {
        ext = 'jpg';
      } else if (_matchSig(data, start, _pngSig)) {
        ext = 'png';
      } else if (_matchSig(data, start, _gifSig)) {
        ext = 'gif';
      }
      if (ext == null) continue;
      try {
        final dir = Directory('${Directory.systemTemp.path}/legado_covers');
        if (!await dir.exists()) await dir.create(recursive: true);
        final out = File('${dir.path}/${filePath.hashCode.abs()}.$ext');
        await out.writeAsBytes(data.sublist(start));
        return out.path;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static bool _matchSig(List<int> data, int start, List<int> sig) {
    if (start < 0 || start + sig.length > data.length) return false;
    for (var k = 0; k < sig.length; k++) {
      if (data[start + k] != sig[k]) return false;
    }
    return true;
  }

  /// 取一组候选字符串中首个非空值（书名/简介的优先级兜底）。
  static String? _firstNonEmpty(List<String?> values) {
    for (final v in values) {
      if (v != null && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  /// 正文开头截取作为简介兜底（对齐本地 TXT 的 extractBookInfo 简介思路）。
  static String _introFromText(String text, [int maxLen = 200]) {
    final t = text.trim();
    if (t.length <= maxLen) return t;
    return '${t.substring(0, maxLen)}…';
  }

  /// 从字节读定长 ASCII 串（magic 判定，越界返回空）。
  static String _ascii(List<int> b, int off, int len) {
    if (off < 0 || off + len > b.length) return '';
    return String.fromCharCodes(b.sublist(off, off + len));
  }
}

/// MOBI 元数据区解析结果（PDB 头 + MOBI/EXTH + 封面本地路径）。
class _MobiMetadata {
  String? title;
  String? author;
  String? intro;
  String? coverPath;
}
