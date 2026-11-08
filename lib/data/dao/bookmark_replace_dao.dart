/// bookmark / replace 相关 DAO（由 app_database.dart 拆分，对齐 legado-E data/dao）。
/// 以 part 归属同一库，可直接访问 DatabaseService 的私有 _db。
part of '../local/app_database.dart';

extension DatabaseServiceBookmarkReplaceDao on DatabaseService {
  Future<List<Bookmark>> getBookmarks([String? bookName, String? author]) async {
    final db = await database;
    final maps = bookName != null
        ? await db.query('bookmarks', where: 'bookName = ? AND bookAuthor = ?', whereArgs: [bookName, author], orderBy: 'createTime DESC')
        : await db.query('bookmarks', orderBy: 'createTime DESC');
    return maps.map((m) => Bookmark.fromMap(m)).toList();
  }

  Future<void> insertBookmark(Bookmark bookmark) async {
    final db = await database;
    await db.insert('bookmarks', bookmark.toMap());
  }

  Future<void> addBookmark(Bookmark bookmark) async {
    await insertBookmark(bookmark);
  }

  Future<void> deleteBookmark(int id) async {
    final db = await database;
    await db.delete('bookmarks', where: 'id = ?', whereArgs: [id]);
  }

  // 替换规则DAO
  Future<List<ReplaceRule>> getReplaceRules() async {
    final db = await database;
    final maps = await db.query('replace_rules', orderBy: 'order_num ASC');
    return maps.map((m) => ReplaceRule.fromMap(m)).toList();
  }

  Future<void> insertReplaceRule(ReplaceRule rule) async {
    final db = await database;
    await db.insert('replace_rules', rule.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateReplaceRule(ReplaceRule rule) async {
    final db = await database;
    if (rule.id != null) await db.update('replace_rules', rule.toMap(), where: 'id = ?', whereArgs: [rule.id]);
  }

  Future<void> deleteReplaceRule(int id) async {
    final db = await database;
    await db.delete('replace_rules', where: 'id = ?', whereArgs: [id]);
  }

  // RSS DAO
}
