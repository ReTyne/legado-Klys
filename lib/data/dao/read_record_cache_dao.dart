/// read / record / cache 相关 DAO。
/// 以 part 归属同一库，可直接访问 DatabaseService 的私有 _db。
part of '../local/app_database.dart';

extension DatabaseServiceReadRecordCacheDao on DatabaseService {
  Future<List<TxtTocRule>> getTxtTocRules() async {
    final db = await database;
    final maps = await db.query('txt_toc_rules', orderBy: 'serialNumber ASC');
    return maps.map((m) => TxtTocRule.fromMap(m)).toList();
  }

  Future<void> insertTxtTocRule(TxtTocRule rule) async {
    final db = await database;
    await db.insert('txt_toc_rules', rule.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteTxtTocRule(int id) async {
    final db = await database;
    await db.delete('txt_toc_rules', where: 'id = ?', whereArgs: [id]);
  }

  // 阅读记录DAO
  Future<void> updateReadPosition(String bookName, String author, int chapterIndex, int pagePos, int time) async {
    final db = await database;
    await db.insert('read_records', {'bookName': bookName, 'author': author, 'chapterIndex': chapterIndex, 'pagePos': pagePos, 'duration': 0, 'date': time});
  }

  Future<List<ReadRecord>> getReadRecords([int? limit]) async {
    final db = await database;
    final maps = await db.query('read_records', orderBy: 'date DESC', limit: limit);
    return maps.map((m) => ReadRecord.fromMap(m)).toList();
  }

  Future<void> addReadRecord(String bookName, String author, int duration, int date) async {
    final db = await database;
    await db.insert('read_records', {'bookName': bookName, 'author': author, 'duration': duration, 'date': date});
  }

  // 缓存DAO
  Future<List<Cache>> getCaches() async {
    final db = await database;
    final maps = await db.query('caches', orderBy: 'saveTime DESC');
    return maps.map((m) => Cache.fromMap(m)).toList();
  }

  Future<void> insertCache(Cache cache) async {
    final db = await database;
    await db.insert('caches', cache.toMap());
  }

  Future<void> clearCaches() async {
    final db = await database;
    await db.delete('caches');
  }

  /// 收缩数据库，回收已删除数据占用的空闲页（VACUUM 不能在事务中执行）
  Future<void> vacuum() async {
    final db = await database;
    await db.execute('VACUUM');
  }

  /// 清空所有书籍的章节正文缓存（保留目录结构，仅把 content 置空）
  Future<void> clearChapterContent() async {
    final db = await database;
    await db.update('book_chapters', {'content': null});
  }

  /// 清理超过 [days] 天未更新书籍的章节正文缓存（oc_autoClearExpired），返回清理章节数
  Future<int> clearExpiredChapterContent({int days = 30}) async {
    final db = await database;
    final cutoff = DateTime.now().millisecondsSinceEpoch - days * 24 * 3600 * 1000;
    final books = await db.query('books',
        columns: ['name', 'author'],
        where: 'lastCheckTime IS NULL OR lastCheckTime < ?',
        whereArgs: [cutoff]);
    var count = 0;
    for (final b in books) {
      final name = b['name'] as String;
      final author = b['author'] as String;
      count += await db.update('book_chapters', {'content': null},
          where: 'bookName = ? AND bookAuthor = ?', whereArgs: [name, author]);
    }
    return count;
  }

  /// 清空单本书籍的章节正文缓存
  Future<void> clearBookChapterContent(String bookName, String bookAuthor) async {
    final db = await database;
    await db.update(
      'book_chapters',
      {'content': null},
      where: 'bookName = ? AND bookAuthor = ?',
      whereArgs: [bookName, bookAuthor],
    );
  }

  // 字典规则DAO
}
