import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_chapter.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/help/source/txt_parser.dart';
import 'package:legado_md3/help/storage/epub_parser.dart';
import 'package:legado_md3/help/storage/umd_parser.dart';
import 'package:legado_md3/help/storage/mobi_parser.dart';
import 'package:legado_md3/ui/book/import/remote_book_screen.dart';

class LocalImportScreen extends StatefulWidget {
  const LocalImportScreen({super.key});

  @override
  State<LocalImportScreen> createState() => _LocalImportScreenState();
}

class _LocalImportScreenState extends State<LocalImportScreen> {
  final _db = DatabaseService();
  final _parser = TxtParserService();
  final List<File> _selectedFiles = [];
  bool _isImporting = false;
  double _progress = 0;

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'TXT', 'epub', 'EPUB', 'umd', 'UMD', 'mobi', 'MOBI', 'azw', 'AZW'],
        allowMultiple: true,
      );
      if (result != null && result.files.isNotEmpty) {
        setState(() {
          for (final file in result.files) {
            if (file.path != null) {
              final f = File(file.path!);
              if (!_selectedFiles.any((e) => e.path == f.path)) {
                _selectedFiles.add(f);
              }
            }
          }
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选择文件失败: $e')),
      );
    }
  }

  Future<void> _importBooks() async {
    if (_selectedFiles.isEmpty) return;
    setState(() {
      _isImporting = true;
      _progress = 0;
    });

    int successCount = 0;
    for (var i = 0; i < _selectedFiles.length; i++) {
      try {
        final file = _selectedFiles[i];
        final fileName = file.uri.pathSegments.last;
        final lower = fileName.toLowerCase();
        Book book;
        List<BookChapter> chapters;
        if (lower.endsWith('.epub')) {
          // EPUB：走专用解析器，逐章读取正文入库
          final parsed = await EpubParser.parse(file.path);
          if (parsed == null) throw 'EPUB 解析失败';
          book = parsed
            ..origin = 'local'
            ..originName = '本地书籍'
            ..noteUrl = 'local://${file.path}'
            ..bookUrl = 'local://${file.path}'
            ..local = true
            ..fileName = file.path;
          final toc = await EpubParser.parseToc(file.path);
          chapters = <BookChapter>[];
          for (final ch in toc) {
            final body = await EpubParser.parseChapterContent(file.path, ch.url);
            chapters.add(BookChapter(
              index: ch.index, title: ch.title, url: ch.url,
              isVolume: ch.isVolume, content: body,
            ));
          }
          if (chapters.isEmpty) chapters = [BookChapter(index: 0, title: '正文', url: '', content: await EpubParser.parseChapterContent(file.path, '') ?? '')];
          book.lastChapter = chapters.isNotEmpty ? chapters.last.title : null;
        } else if (lower.endsWith('.umd')) {
          final res = await UmdParser.parse(file.path);
          if (res == null) throw 'UMD 解析失败';
          book = res.book
            ..origin = 'local' ..originName = '本地书籍'
            ..noteUrl = 'local://${file.path}' ..bookUrl = 'local://${file.path}'
            ..local = true ..fileName = file.path;
          chapters = res.chapters;
          book.lastChapter = chapters.isNotEmpty ? chapters.last.title : null;
        } else if (lower.endsWith('.mobi') || lower.endsWith('.azw')) {
          final res = await MobiParser.parse(file.path);
          if (res == null) throw 'MOBI 解析失败（仅支持 KF7/PalmDOC）';
          book = res.book
            ..local = true
            ..fileName = file.path;
          chapters = res.chapters;
          book.lastChapter = chapters.isNotEmpty ? chapters.last.title : null;
        } else {
          // TXT
          final content = await file.readAsString();
          final info = _parser.extractBookInfo(content, fileName);
          chapters = _parser.parseChapters(content);
          book = Book(
            name: info['name'] ?? fileName,
            author: info['author'] ?? '未知',
            intro: info['intro'],
            origin: 'local',
            originName: '本地书籍',
            noteUrl: 'local://${file.path}',
            bookUrl: 'local://${file.path}',
            type: 1,
            local: true,
            fileName: file.path,
            lastChapter: chapters.isNotEmpty ? chapters.last.title : null,
            wordCount: content.length,
          );
        }

        await _db.insertBook(book);
        await _db.saveChapters(book.name, book.author, chapters);
        successCount++;
      } catch (e) {
        debugPrint('导入失败: $e');
      }
      setState(() => _progress = (i + 1) / _selectedFiles.length);
    }

    setState(() => _isImporting = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('成功导入 $successCount 本书')),
      );
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('本地导入'),
        actions: [
          IconButton(tooltip: '远程书籍', icon: const Icon(Icons.cloud_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RemoteBookScreen()))),
          if (_selectedFiles.isNotEmpty)
            TextButton(
              onPressed: _isImporting ? null : _importBooks,
              child: Text('导入 (${_selectedFiles.length})'),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_isImporting)
            LinearProgressIndicator(value: _progress),
          Expanded(
            child: _selectedFiles.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.folder_open, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        const Text('还没有选择文件', style: TextStyle(color: Colors.grey)),
                        const SizedBox(height: 8),
                        const Text('支持TXT格式', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _selectedFiles.length,
                    itemBuilder: (context, index) {
                      final file = _selectedFiles[index];
                      return ListTile(
                        leading: const Icon(Icons.description),
                        title: Text(file.uri.pathSegments.last, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${(file.lengthSync() / 1024).toStringAsFixed(1)} KB'),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() => _selectedFiles.removeAt(index)),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isImporting ? null : _pickFiles,
        icon: const Icon(Icons.add),
        label: const Text('选择文件'),
      ),
    );
  }
}
