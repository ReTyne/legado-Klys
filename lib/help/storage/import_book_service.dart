import 'dart:io';
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
  ImportResult(this.book, this.chapterCount);
}

/// 统一的本地书籍导入：按文件路径解析 TXT/EPUB/UMD 并入库
class ImportBookService {
  final DatabaseService _db = DatabaseService();
  final TxtParserService _txt = TxtParserService();

  static const supported = ['txt', 'epub', 'umd', 'mobi', 'azw'];

  Future<ImportResult> importPath(String path) async {
    final file = File(path);
    final fileName = path.split('/').last;
    final lower = fileName.toLowerCase();
    final ext = lower.contains('.') ? lower.split('.').last : '';

    Book book;
    List<BookChapter> chapters;

    if (ext == 'epub') {
      final parsed = await EpubParser.parse(path);
      if (parsed == null) throw 'EPUB 解析失败';
      book = parsed
        ..origin = 'local'
        ..originName = '本地书籍'
        ..noteUrl = 'local://$path'
        ..bookUrl = 'local://$path';
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
        ..type = 1;
      chapters = res.chapters;
      book.lastChapter = chapters.isNotEmpty ? chapters.last.title : null;
    } else if (ext == 'mobi' || ext == 'azw') {
      final res = await MobiParser.parse(path);
      if (res == null) throw 'MOBI 解析失败（仅支持 KF7/PalmDOC，KF8 高压缩请先转 EPUB）';
      book = res.book;
      chapters = res.chapters;
      book.lastChapter = chapters.isNotEmpty ? chapters.last.title : null;
    } else {
      final content = await file.readAsString();
      final info = _txt.extractBookInfo(content, fileName);
      chapters = _txt.parseChapters(content);
      book = Book(
        name: info['name'] ?? fileName,
        author: info['author'] ?? '未知',
        intro: info['intro'],
        origin: 'local', originName: '本地书籍',
        noteUrl: 'local://$path', bookUrl: 'local://$path', type: 1,
        lastChapter: chapters.isNotEmpty ? chapters.last.title : null,
        wordCount: content.length,
      );
    }

    await _db.insertBook(book);
    await _db.saveChapters(book.name, book.author, chapters);
    return ImportResult(book, chapters.length);
  }
}
