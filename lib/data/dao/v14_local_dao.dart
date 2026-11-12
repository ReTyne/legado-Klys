/// v14 / local 相关 DAO。
/// 以 part 归属同一库，可直接访问 DatabaseService 的私有 _db。
part of '../local/app_database.dart';

extension DatabaseServiceV14LocalDao on DatabaseService {
  Future<List<BookMemo>> getBookMemos(String bookName, String author, {int? chapterIndex}) async {
    final db = await database;
    final maps = await db.query('book_memos',
        where: chapterIndex == null
            ? 'bookName = ? AND author = ?'
            : 'bookName = ? AND author = ? AND chapterIndex = ?',
        whereArgs: chapterIndex == null
            ? [bookName, author]
            : [bookName, author, chapterIndex],
        orderBy: 'updateTime DESC');
    return maps.map(BookMemo.fromMap).toList();
  }

  Future<int> upsertBookMemo(BookMemo m) async {
    final db = await database;
    return db.insert('book_memos', m.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteBookMemo(int id) async {
    final db = await database;
    await db.delete('book_memos', where: 'id = ?', whereArgs: [id]);
  }

  // 划线 / 高亮
  Future<List<BookHighlight>> getBookHighlights(String bookName, String author) async {
    final db = await database;
    final maps = await db.query('book_highlights',
        where: 'bookName = ? AND author = ?',
        whereArgs: [bookName, author],
        orderBy: 'chapterIndex ASC, start ASC');
    return maps.map(BookHighlight.fromMap).toList();
  }

  Future<int> insertBookHighlight(BookHighlight h) async {
    final db = await database;
    return db.insert('book_highlights', h.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteBookHighlight(int id) async {
    final db = await database;
    await db.delete('book_highlights', where: 'id = ?', whereArgs: [id]);
  }

  // 下载队列
  Future<List<DownloadTask>> getDownloadTasks() async {
    final db = await database;
    final maps = await db.query('download_tasks', orderBy: 'createTime DESC');
    return maps.map(DownloadTask.fromMap).toList();
  }

  Future<int> upsertDownloadTask(DownloadTask t) async {
    final db = await database;
    return db.insert('download_tasks', t.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteDownloadTask(int id) async {
    final db = await database;
    await db.delete('download_tasks', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearFinishedDownloadTasks() async {
    final db = await database;
    await db.delete('download_tasks', where: 'status = ?', whereArgs: [2]);
  }

  // 规则订阅自动更新开关
  Future<void> setRuleSubAutoUpdate(int id, int autoUpdate, int updateInterval) async {
    final db = await database;
    await db.update('rule_subs',
        {'autoUpdate': autoUpdate, 'updateInterval': updateInterval},
        where: 'id = ?', whereArgs: [id]);
  }

  // ==================== v14 DAO（第十轮 / 阅读Sigma 对齐） ====================

  // --- SearchBook 跨源换源检索缓存 ---
}
