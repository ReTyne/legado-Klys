import 'dart:convert';

import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/db_models.dart';
import 'package:legado_md3/help/storage/webdav_service.dart';

/// 云进度同步（对齐 Sigma `syncBookProgress` / `syncBookProgressPlus`
/// 与阅读菜单 `menu_get_progress` / `menu_cover_progress`）。
///
/// - [pull]：从 WebDAV 拉取进度，按 `lastReadTime` 与本地比较，较新者写回本地
///   书籍阅读位置（Book.durChapterIndex / durChapterPos / durChapterTime）并落
///   `book_progress` 表。
/// - [push]：把本地全部书籍进度覆盖上传到 WebDAV。
/// - 使用 WebDAV 根目录 `bookProgress/` 之外的既有 `reading_progress.json`，
///   与 WebDavService 现有实现完全复用，不引入新存储协议。
class BookProgressSync {
  BookProgressSync._();
  static final BookProgressSync instance = BookProgressSync._();

  final WebDavService _dav = WebDavService();

  /// 拉取云进度（返回同步到的书籍数；无云数据返回 0）。
  Future<int> pull() async {
    final remote = await _dav.downloadReadingProgress();
    if (remote == null || remote.isEmpty) return 0;
    final db = await DatabaseService().database;
    var changed = 0;
    for (final item in remote) {
      final name = (item['bookName'] ?? item['name'] ?? '') as String;
      final author = (item['author'] ?? '') as String;
      if (name.isEmpty) continue;
      final chapterIndex = (item['chapterIndex'] ?? item['durChapterIndex'] ?? 0) as int;
      final pagePos = (item['pagePos'] ?? item['durChapterPos'] ?? 0) as int;
      final lastReadTime = (item['lastReadTime'] ?? item['time'] ?? 0) as int;

      // 与本地进度比较：仅云更新时写回
      final local = await DatabaseService().getBookProgress(name, author);
      if (local != null && local.lastReadTime >= lastReadTime) continue;

      await db.update(
        'books',
        {
          'durChapterIndex': chapterIndex,
          'durChapterPos': pagePos,
          'durChapterTime': lastReadTime,
        },
        where: 'name = ? AND author = ?',
        whereArgs: [name, author],
      );
      await DatabaseService().saveBookProgress(BookProgress(
        bookName: name,
        author: author,
        chapterIndex: chapterIndex,
        pagePos: pagePos,
        lastReadTime: lastReadTime,
      ));
      changed++;
    }
    return changed;
  }

  /// 覆盖上传本地全部书籍进度（返回是否成功）。
  Future<bool> push() async {
    final books = await DatabaseService().getAllBooks();
    final list = <Map<String, dynamic>>[];
    for (final b in books) {
      final p = await DatabaseService().getBookProgress(b.name, b.author);
      list.add({
        'bookName': b.name,
        'author': b.author,
        'chapterIndex': p?.chapterIndex ?? b.durChapterIndex,
        'pagePos': p?.pagePos ?? b.durChapterPos,
        'lastReadTime': p?.lastReadTime ?? b.durChapterTime,
        'deviceId': p?.toMap()['deviceId'] ?? '',
      });
    }
    return _dav.uploadReadingProgress(list);
  }

  /// 记录一次本地阅读进度（供 tts_service / reading_screen 挂钩）。
  Future<void> record(Book book, {int? chapterIndex, int? pagePos, int? durationMs}) async {
    await DatabaseService().saveBookProgress(BookProgress(
      bookName: book.name,
      author: book.author,
      chapterIndex: chapterIndex ?? book.durChapterIndex,
      pagePos: pagePos ?? book.durChapterPos,
      duration: durationMs ?? 0,
      lastReadTime: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  /// 生成本地进度快照 JSON（用于备份 / 调试导出）。
  Future<String> snapshotJson() async {
    final all = await DatabaseService().getAllBookProgress();
    return jsonEncode({
      'progress': all.map((p) => p.toMap()).toList(),
      'time': DateTime.now().millisecondsSinceEpoch,
    });
  }
}
