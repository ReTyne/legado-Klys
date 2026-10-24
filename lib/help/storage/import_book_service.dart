import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_chapter.dart';
import 'package:legado_md3/help/source/txt_parser.dart';
import 'package:legado_md3/help/storage/epub_parser.dart';
import 'package:legado_md3/help/storage/umd_parser.dart';
import 'package:legado_md3/help/storage/mobi_parser.dart';

/// 本地书籍导入结果
class ImportResult {
  final Book book;
  final int chapterCount;

  /// 压缩包导入时可能一次导入多本，[totalBooks] 为实际导入总数（普通文件为 1）
  final int totalBooks;
  ImportResult(this.book, this.chapterCount, {this.totalBooks = 1});
}

/// 统一的本地书籍导入：按文件路径解析 TXT/EPUB/UMD/MOBI/PDF/ZIP 并入库。
///
/// 对齐 legado-E `LocalBook.importFile/importArchiveFile`：
/// * PDF 以「单章正文 + fileName」入库，阅读路由据此分流到 PDF 阅读器；
/// * 压缩包（zip）解压后按 `bookFileRegex`（txt|epub|umd|pdf|mobi|azw3|azw）
///   过滤，逐本导入，`origin` 标记为 `local::<压缩包名>`；
/// * rar/7z 压缩包需原生解压支持（见 `legado/archive` 平台通道），
///   Dart 侧会给出明确错误而不是静默失败。
class ImportBookService {
  final DatabaseService _db = DatabaseService();
  final TxtParserService _txt = TxtParserService();

  /// 支持的书籍文件扩展名（对齐 E `AppPattern.bookFileRegex`）
  static const supported = [
    'txt', 'epub', 'umd', 'mobi', 'azw', 'azw3', 'pdf',
  ];

  /// 压缩包扩展名（对齐 E `AppPattern.archiveFileRegex`）
  static const archiveExts = ['zip', 'rar', '7z'];

  /// 压缩包内参与导入的文件名正则（与 supported 一致）
  static final _bookFileRegex =
      RegExp(r'.*\.(txt|epub|umd|pdf|mobi|azw3|azw)$', caseSensitive: false);

  Future<ImportResult> importPath(String path) async {
    final fileName = path.split('/').last;
    final lower = fileName.toLowerCase();
    final ext = lower.contains('.') ? lower.split('.').last : '';

    if (archiveExts.contains(ext)) {
      return _importArchive(path, fileName);
    }
    return _importSingle(path, ext, fileName);
  }

  /// 压缩包导入：解压 → 过滤书籍文件 → 逐本导入（E: importArchiveFile）。
  Future<ImportResult> _importArchive(String path, String archiveName) async {
    if (!archiveName.toLowerCase().endsWith('.zip')) {
      throw '暂不支持 ${archiveName.split('.').last.toUpperCase()} 压缩包（仅支持 ZIP；RAR/7z 需在 Android 端启用原生解压）';
    }
    final bytes = await File(path).readAsBytes();
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw 'ZIP 解压失败（文件可能已损坏）';
    }
    // 解压到 documents/legado_files/unzip/<md5(压缩包名)>/，避免重复解压互相覆盖
    final dir = await getApplicationDocumentsDirectory();
    final outDir = Directory(
        '${dir.path}/legado_files/unzip/${md5.convert(utf8.encode(archiveName))}');
    if (!outDir.existsSync()) outDir.createSync(recursive: true);

    final extracted = <File>[];
    for (final f in archive.files) {
      if (!f.isFile) continue;
      final name = f.name.split('/').last; // 丢掉压缩包内目录层级
      if (!_bookFileRegex.hasMatch(name)) continue;
      final out = File('${outDir.path}/$name');
      final data = f.content;
      await out.writeAsBytes(data is List<int> ? data : const <int>[]);
      extracted.add(out);
    }
    if (extracted.isEmpty) {
      throw '压缩包内未找到可导入的书籍文件（支持 txt/epub/umd/pdf/mobi/azw3/azw）';
    }
    // 与 E 一致：一次导入包内全部书籍，origin 标记来源压缩包
    ImportResult? first;
    var count = 0;
    for (final f in extracted) {
      try {
        final res = await _importSingle(
            f.path, p.extension(f.path).replaceFirst('.', '').toLowerCase(), f.uri.pathSegments.last);
        res.book.origin = 'local::$archiveName';
        await _db.insertBook(res.book);
        count++;
        first ??= res;
      } catch (_) {
        // 单本失败不阻断其余导入
      }
    }
    if (first == null) throw '压缩包内书籍导入失败';
    return ImportResult(first.book, first.chapterCount, totalBooks: count);
  }

  Future<ImportResult> _importSingle(
      String path, String ext, String fileName) async {
    final file = File(path);

    Book book;
    late List<BookChapter> chapters;

    if (ext == 'epub') {
      final parsed = await EpubParser.parse(path);
      if (parsed == null) throw 'EPUB 解析失败';
      book = parsed
        ..origin = 'local'
        ..originName = '本地书籍'
        ..noteUrl = 'local://$path'
        ..bookUrl = 'local://$path'
        ..local = true;
      final toc = await EpubParser.parseToc(path);
      chapters = <BookChapter>[];
      for (final ch in toc) {
        chapters.add(BookChapter(
          index: ch.index, title: ch.title, url: ch.url,
          isVolume: ch.isVolume,
          content: await EpubParser.parseChapterContent(path, ch.url),
        ));
      }
      if (chapters.isEmpty) {
        chapters = [BookChapter(index: 0, title: '正文', url: '', content: await EpubParser.parseChapterContent(path, '') ?? '')];
      }
      book.lastChapter = chapters.isNotEmpty ? chapters.last.title : null;
    } else if (ext == 'umd') {
      final res = await UmdParser.parse(path);
      if (res == null) throw 'UMD 解析失败';
      book = res.book
        ..origin = 'local'
        ..originName = '本地书籍'
        ..noteUrl = 'local://$path'
        ..bookUrl = 'local://$path'
        ..type = 1
        ..local = true;
      chapters = res.chapters;
      book.lastChapter = chapters.isNotEmpty ? chapters.last.title : null;
    } else if (ext == 'mobi' || ext == 'azw' || ext == 'azw3') {
      final res = await MobiParser.parse(path);
      if (res == null) throw 'MOBI 解析失败（仅支持 KF7/PalmDOC，KF8 高压缩请先转 EPUB）';
      book = res.book
        ..origin = 'local'
        ..originName = '本地书籍'
        ..noteUrl = 'local://$path'
        ..bookUrl = 'local://$path'
        ..type = 1
        ..local = true;
      chapters = res.chapters;
      book.lastChapter = chapters.isNotEmpty ? chapters.last.title : null;
    } else if (ext == 'pdf') {
      // PDF：单章「正文」，阅读路由按 fileName 分流到 PdfReaderScreen，
      // 进度以 durChapterPos 保存页码（对齐 PdfReaderScreen 约定）。
      book = Book(
        name: _stripExt(fileName),
        author: '未知',
        origin: 'local',
        originName: '本地书籍',
        noteUrl: 'local://$path',
        bookUrl: 'local://$path',
        type: 1,
        local: true,
        fileName: path,
        lastChapter: '正文',
      );
      chapters = [BookChapter(index: 0, title: '正文', url: '')];
    } else {
      // TXT：与读取侧（readTxtChapter）保持同一套编码识别，避免 GBK 等文件
      // 导入用 UTF-8 硬解码导致标题乱码、位置偏移与读取侧不一致。
      final content = await TxtParserService.readFileAutoDetect(file);
      final info = _txt.extractBookInfo(content, fileName);
      var chapters = _txt.parseChapters(content);
      book = Book(
        name: info['name'] ?? fileName,
        author: info['author'] ?? '未知',
        intro: info['intro'],
        origin: 'local', originName: '本地书籍',
        noteUrl: 'local://$path', bookUrl: 'local://$path', type: 1,
        local: true,
        lastChapter: chapters.isNotEmpty ? chapters.last.title : null,
        wordCount: content.length,
      );
      // 长章节拆分（E: Book.splitLongChapter，仅本地 TXT 生效，默认开启）
      if (book.splitLongChapter) {
        chapters = TxtParserService.splitLongChapters(
          chapters,
          fullText: const LineSplitter().convert(content).join('\n'),
        );
        book.lastChapter = chapters.isNotEmpty ? chapters.last.title : null;
      }
    }

    await _db.insertBook(book);
    await _db.saveChapters(book.name, book.author, chapters);
    return ImportResult(book, chapters.length);
  }

  static String _stripExt(String name) {
    final i = name.lastIndexOf('.');
    return i > 0 ? name.substring(0, i) : name;
  }

  /// 重新解析本地 TXT 目录（切换长章节拆分开关时调用，E: TextFile.analyze）。
  /// 返回带位置信息的新章节列表；调用方负责 saveChapters 落库。
  static Future<List<BookChapter>> reparseTxtToc(
    String filePath, {
    required bool splitLong,
  }) async {
    final content = await TxtParserService.readFileAutoDetect(File(filePath));
    final chapters = TxtParserService().parseChapters(content);
    if (!splitLong) return chapters;
    return TxtParserService.splitLongChapters(
      chapters,
      fullText: const LineSplitter().convert(content).join('\n'),
    );
  }

  /// 切换本地 TXT 书籍的长章节拆分开关（E: menu_split_long_chapter）：
  /// 更新书籍标记 → 重新解析目录入库 → 按标题迁移阅读进度。
  /// 返回新的 durChapterIndex；非本地 TXT 时原样返回不入库。
  static Future<int> toggleSplitLongChapter(Book book, DatabaseService db) async {
    final filePath = book.fileName;
    if (filePath == null || !book.local) return book.durChapterIndex;
    final oldChapters = await db.getChapters(book.name, book.author);
    final next = !book.splitLongChapter;
    book.splitLongChapter = next;
    await db.updateBook(book);
    final chapters = await reparseTxtToc(filePath, splitLong: next);
    await db.saveChapters(book.name, book.author, chapters);
    // 阅读进度迁移：章节边界已变，页内偏移失效，章索引按标题重映射
    book.durChapterIndex =
        TxtParserService.remapChapterIndex(oldChapters, book.durChapterIndex, chapters);
    book.durChapterPos = 0;
    book.lastChapter = chapters.isNotEmpty ? chapters.last.title : book.lastChapter;
    await db.updateBook(book);
    return book.durChapterIndex;
  }
}
