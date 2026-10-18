import 'dart:convert';
import 'dart:io';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_chapter.dart';

/// 本地导入结果
class LocalImportResult {
  final Book book;
  final List<BookChapter> chapters;
  LocalImportResult({required this.book, required this.chapters});
}

/// 本地文件导入服务
class LocalFileService {
  static const List<String> defaultTocPatterns = [
    r'^第[一二三四五六七八九十百千万零〇两\d]+[章节回卷集部篇].*$',
    r'^Chapter\s+\d+.*$',
    r'^\d+、.*$',
    r'^\d+\..*$',
    r'^【.*】.*$',
    r'^\[.*\].*$',
  ];

  /// 导入TXT文件，返回书籍和章节列表
  Future<LocalImportResult?> importTxt(String filePath, {List<String>? customPatterns}) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      final bytes = await file.readAsBytes();
      final content = utf8.decode(bytes, allowMalformed: true);
      final fileName = filePath.split('/').last.replaceAll('.txt', '').replaceAll('.TXT', '');

      // 提取书籍信息
      final info = _extractBookInfo(content, fileName);

      final patterns = customPatterns ?? defaultTocPatterns;
      final chapters = _parseTxtChapters(content, patterns);

      final book = Book(
        name: info['name'] ?? fileName,
        author: info['author'] ?? '未知',
        intro: info['intro'],
        origin: 'local',
        originName: '本地书籍',
        noteUrl: 'local://$filePath',
        bookUrl: 'local://$filePath',
        type: 1, // 本地书籍
        wordCount: content.length,
        lastChapter: chapters.isNotEmpty ? chapters.last.title : null,
      );

      return LocalImportResult(book: book, chapters: chapters);
    } catch (e) {
      return null;
    }
  }

  /// 从内容提取书籍信息
  Map<String, String?> _extractBookInfo(String content, String fileName) {
    final lines = const LineSplitter().convert(content);
    String? name = fileName;
    String? author;
    String? intro;

    for (var i = 0; i < lines.length && i < 20; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      final authorMatch = RegExp(r'[《【](.+?)[》】]\s*作者[：:]\s*(.+)').firstMatch(line);
      if (authorMatch != null) {
        name = authorMatch.group(1);
        author = authorMatch.group(2);
        break;
      }
      if (line.startsWith('作者') || line.startsWith('作 者')) {
        author = line.replaceAll(RegExp(r'^作\s*者[：:\s]*'), '').trim();
      }
    }

    final contentLines = lines.where((l) => l.trim().isNotEmpty).toList();
    if (contentLines.length > 2) {
      intro = contentLines.sublist(0, contentLines.length > 5 ? 5 : contentLines.length).join('\n');
      if (intro.length > 200) intro = intro.substring(0, 200) + '...';
    }

    return {'name': name, 'author': author, 'intro': intro};
  }

  List<BookChapter> _parseTxtChapters(String content, List<String> patterns) {
    final chapters = <BookChapter>[];
    final lines = content.split('\n');
    final combinedPattern = RegExp(patterns.map((p) => '($p)').join('|'));
    int chapterStart = -1;
    String currentTitle = '';
    int index = 0;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      if (combinedPattern.hasMatch(line)) {
        if (chapterStart >= 0) {
          final chapterContent = lines.sublist(chapterStart, i).join('\n').trim();
          chapters.add(BookChapter(
            title: currentTitle,
            url: 'local_$index',
            index: index,
            content: chapterContent,
          ));
          index++;
        }
        chapterStart = i + 1;
        currentTitle = line;
      }
    }

    if (chapterStart >= 0) {
      final chapterContent = lines.sublist(chapterStart).join('\n').trim();
      chapters.add(BookChapter(
        title: currentTitle,
        url: 'local_$index',
        index: index,
        content: chapterContent,
      ));
    }

    if (chapters.isEmpty) {
      chapters.add(BookChapter(
        title: '正文',
        url: 'local_0',
        index: 0,
        content: content,
      ));
    }

    return chapters;
  }

  /// 导入EPUB文件（简化实现）
  Future<LocalImportResult?> importEpub(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;
      final fileName = filePath.split('/').last.replaceAll('.epub', '');

      final book = Book(
        name: fileName,
        author: '未知',
        origin: 'local',
        originName: '本地书籍',
        noteUrl: 'local://$filePath',
        bookUrl: 'local://$filePath',
        type: 1,
      );

      return LocalImportResult(book: book, chapters: []);
    } catch (e) {
      return null;
    }
  }

  Future<int> getFileSize(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) return await file.length();
    return 0;
  }

  String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
