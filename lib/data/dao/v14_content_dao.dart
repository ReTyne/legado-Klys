/// v14 / content 相关 DAO（由 app_database.dart 拆分，对齐 legado-E data/dao）。
/// 以 part 归属同一库，可直接访问 DatabaseService 的私有 _db。
part of '../local/app_database.dart';

extension DatabaseServiceV14ContentDao on DatabaseService {
  Future<List<PdfOutline>> getPdfOutlines(String bookName, String author) async {
    final db = await database;
    final maps = await db.query('pdf_outlines',
        where: 'bookName = ? AND author = ?', whereArgs: [bookName, author],
        orderBy: 'sortOrder ASC');
    return maps.map(PdfOutline.fromMap).toList();
  }

  Future<void> replacePdfOutlines(String bookName, String author, List<PdfOutline> list) async {
    final db = await database;
    await db.delete('pdf_outlines',
        where: 'bookName = ? AND author = ?', whereArgs: [bookName, author]);
    final batch = db.batch();
    for (final o in list) {
      batch.insert('pdf_outlines', o.toMap());
    }
    await batch.commit(noResult: true);
  }

  // --- 页数估算 / 全书索引 ---
  Future<List<PageEstimate>> getPageEstimates(String bookName, String author) async {
    final db = await database;
    final maps = await db.query('page_estimates',
        where: 'bookName = ? AND author = ?', whereArgs: [bookName, author],
        orderBy: 'chapterIndex ASC');
    return maps.map(PageEstimate.fromMap).toList();
  }

  Future<void> upsertPageEstimate(PageEstimate e) async {
    final db = await database;
    await db.insert('page_estimates', e.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearPageEstimates(String bookName, String author) async {
    final db = await database;
    await db.delete('page_estimates',
        where: 'bookName = ? AND author = ?', whereArgs: [bookName, author]);
  }

  // --- 通用 KV 缓存 ---
  Future<String?> getKvCache(String key) async {
    final db = await database;
    final maps = await db.query('kv_caches', where: 'key = ?', whereArgs: [key], limit: 1);
    if (maps.isEmpty) return null;
    final c = KvCache.fromMap(maps.first);
    if (c.expired) {
      await db.delete('kv_caches', where: 'key = ?', whereArgs: [key]);
      return null;
    }
    return c.value;
  }

  Future<void> setKvCache(String key, String? value, {Duration? ttl}) async {
    final db = await database;
    final deadline = ttl == null
        ? 0
        : DateTime.now().millisecondsSinceEpoch + ttl.inMilliseconds;
    await db.insert('kv_caches', KvCache(key: key, value: value, deadline: deadline).toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearExpiredKvCaches() async {
    final db = await database;
    await db.delete('kv_caches',
        where: 'deadline > 0 AND deadline < ?',
        whereArgs: [DateTime.now().millisecondsSinceEpoch]);
  }

  // --- 段评 ---
  Future<List<BookReview>> getBookReviews(String bookName, String author, int chapterIndex) async {
    final db = await database;
    final maps = await db.query('book_reviews',
        where: 'bookName = ? AND author = ? AND chapterIndex = ?',
        whereArgs: [bookName, author, chapterIndex], orderBy: 'paragraphIndex ASC, likes DESC');
    return maps.map(BookReview.fromMap).toList();
  }

  Future<void> insertBookReview(BookReview r) async {
    final db = await database;
    await db.insert('book_reviews', r.toMap());
  }

  Future<void> likeBookReview(int id) async {
    final db = await database;
    await db.rawUpdate('UPDATE book_reviews SET likes = likes + 1 WHERE id = ?', [id]);
  }

  // --- 多套排版预设 ---
  Future<List<ReadPreset>> getReadPresets() async {
    final db = await database;
    final maps = await db.query('read_presets', orderBy: 'createTime ASC');
    return maps.map(ReadPreset.fromMap).toList();
  }

  Future<int> insertReadPreset(ReadPreset p) async {
    final db = await database;
    return db.insert('read_presets', p.toMap());
  }

  Future<void> deleteReadPreset(int id) async {
    final db = await database;
    await db.delete('read_presets', where: 'id = ?', whereArgs: [id]);
  }

  // --- 弹幕缓存索引 ---
}
