/// auto / task 相关 DAO。
/// 以 part 归属同一库，可直接访问 DatabaseService 的私有 _db。
part of '../local/app_database.dart';

extension DatabaseServiceAutoTaskDao on DatabaseService {
  Future<List<AutoTask>> getAutoTasks() async {
    final db = await database;
    final maps = await db.query('auto_tasks', orderBy: 'customOrder ASC, id ASC');
    return maps.map(AutoTask.fromMap).toList();
  }

  Future<int> insertAutoTask(AutoTask t) async {
    final db = await database;
    return db.insert('auto_tasks', t.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateAutoTask(AutoTask t) async {
    final db = await database;
    if (t.id != null) {
      await db.update('auto_tasks', t.toMap(), where: 'id = ?', whereArgs: [t.id]);
    }
  }

  Future<void> deleteAutoTask(int id) async {
    final db = await database;
    await db.delete('auto_tasks', where: 'id = ?', whereArgs: [id]);
  }

  // RSS 阅读记录（续读）
  Future<RssReadRecord?> getRssReadRecord(String link) async {
    final db = await database;
    final maps = await db.query('rss_read_records', where: 'link = ?', whereArgs: [link], limit: 1);
    return maps.isEmpty ? null : RssReadRecord.fromMap(maps.first);
  }

  Future<List<RssReadRecord>> getRssReadRecords({int limit = 200}) async {
    final db = await database;
    final maps = await db.query('rss_read_records', orderBy: 'readTime DESC', limit: limit);
    return maps.map(RssReadRecord.fromMap).toList();
  }

  Future<void> upsertRssReadRecord(RssReadRecord r) async {
    final db = await database;
    await db.insert('rss_read_records', r.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> toggleRssReadRecordEnabled(String link, int enabled) async {
    final db = await database;
    await db.update('rss_read_records', {'enabled': enabled}, where: 'link = ?', whereArgs: [link]);
  }

  Future<void> clearRssReadRecords() async {
    final db = await database;
    await db.delete('rss_read_records');
  }

  // 书籍备忘
}
