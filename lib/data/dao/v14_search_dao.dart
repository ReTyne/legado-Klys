/// v14 / search 相关 DAO。
/// 以 part 归属同一库，可直接访问 DatabaseService 的私有 _db。
part of '../local/app_database.dart';

extension DatabaseServiceV14SearchDao on DatabaseService {
  Future<List<SearchBookTable>> getSearchBooks({String? name, String? author, String? origin}) async {
    final db = await database;
    String? where;
    List<Object?> args = [];
    if (name != null && author != null) {
      where = 'name = ? AND author = ?';
      args = [name, author];
    } else if (origin != null) {
      where = 'origin = ?';
      args = [origin];
    }
    final maps = await db.query('search_books', where: where, whereArgs: args,
        orderBy: 'originOrder ASC, time DESC');
    return maps.map(SearchBookTable.fromMap).toList();
  }

  Future<SearchBookTable?> getFirstSearchBook(String name, String author) async {
    final list = await getSearchBooks(name: name, author: author);
    return list.isEmpty ? null : list.first;
  }

  Future<void> insertSearchBook(SearchBookTable s) async {
    final db = await database;
    await db.insert('search_books', s.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> insertSearchBooks(List<SearchBookTable> list) async {
    final db = await database;
    final batch = db.batch();
    for (final s in list) {
      batch.insert('search_books', s.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> clearSearchBooks({int? beforeTime}) async {
    final db = await database;
    await db.delete('search_books',
        where: beforeTime == null ? null : 'time < ?',
        whereArgs: beforeTime == null ? null : [beforeTime]);
  }

  // --- 书源检测状态 ---
  Future<List<BookSourceCheckState>> getBookSourceCheckStates() async {
    final db = await database;
    final maps = await db.query('book_source_check_states', orderBy: 'checkTime DESC');
    return maps.map(BookSourceCheckState.fromMap).toList();
  }

  Future<BookSourceCheckState?> getBookSourceCheckState(String origin) async {
    final db = await database;
    final maps = await db.query('book_source_check_states',
        where: 'origin = ?', whereArgs: [origin], limit: 1);
    return maps.isEmpty ? null : BookSourceCheckState.fromMap(maps.first);
  }

  Future<void> upsertBookSourceCheckState(BookSourceCheckState s) async {
    final db = await database;
    await db.insert('book_source_check_states', s.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearBookSourceCheckStates() async {
    final db = await database;
    await db.delete('book_source_check_states');
  }

  // --- PDF 大纲 ---
}
