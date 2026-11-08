/// book / source 相关 DAO（由 app_database.dart 拆分，对齐 legado-E data/dao）。
/// 以 part 归属同一库，可直接访问 DatabaseService 的私有 _db。
part of '../local/app_database.dart';

extension DatabaseServiceBookSourceDao on DatabaseService {
  Future<List<BookSource>> getAllSources({bool? enabled}) async {
    final db = await database;
    final maps = enabled != null
        ? await db.query('book_sources', where: 'enabled = ?', whereArgs: [enabled ? 1 : 0], orderBy: 'customOrder ASC')
        : await db.query('book_sources', orderBy: 'customOrder ASC');
    return maps.map((m) => BookSource.fromMap(m)).toList();
  }

  Future<BookSource?> getSource(String url) async {
    final db = await database;
    final maps = await db.query('book_sources', where: 'bookSourceUrl = ?', whereArgs: [url]);
    return maps.isNotEmpty ? BookSource.fromMap(maps.first) : null;
  }

  Future<void> insertSource(BookSource source) async {
    final db = await database;
    await db.insert('book_sources', source.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateSource(BookSource source) async {
    final db = await database;
    await db.update('book_sources', source.toMap(), where: 'bookSourceUrl = ?', whereArgs: [source.bookSourceUrl]);
  }

  /// 仅更新书源运行时变量 variable（JS setVariable 落库，避免整行覆盖）。
  Future<void> updateSourceVariable(String sourceUrl, String variable) async {
    final db = await database;
    await db.update('book_sources', {'variable': variable},
        where: 'bookSourceUrl = ?', whereArgs: [sourceUrl]);
  }

  /// 仅更新订阅源运行时变量 variable（JS setVariable 落库）。
  Future<void> updateRssSourceVariable(String sourceUrl, String variable) async {
    final db = await database;
    await db.update('rss_sources', {'variable': variable},
        where: 'url = ?', whereArgs: [sourceUrl]);
  }

  Future<void> deleteSource(String url) async {
    final db = await database;
    await db.delete('book_sources', where: 'bookSourceUrl = ?', whereArgs: [url]);
  }

  Future<List<String>> getSourceGroups() async {
    final db = await database;
    final maps = await db.rawQuery('SELECT DISTINCT bookSourceGroup FROM book_sources WHERE bookSourceGroup IS NOT NULL AND bookSourceGroup != ""');
    return maps.map((m) => m['bookSourceGroup'].toString()).toList();
  }

  // 分组DAO
}
