/// knowledge / history 相关 DAO。
/// 以 part 归属同一库，可直接访问 DatabaseService 的私有 _db。
part of '../local/app_database.dart';

extension DatabaseServiceKnowledgeHistoryDao on DatabaseService {
  Future<List<BookKnowledge>> getBookKnowledge(String bookName, String author, {String? type}) async {
    final db = await database;
    final maps = type != null
        ? await db.query('book_knowledge', where: 'bookName = ? AND author = ? AND type = ?', whereArgs: [bookName, author, type], orderBy: '"order" ASC')
        : await db.query('book_knowledge', where: 'bookName = ? AND author = ?', whereArgs: [bookName, author], orderBy: '"order" ASC');
    return maps.map((m) => BookKnowledge.fromMap(m)).toList();
  }

  Future<void> insertBookKnowledge(BookKnowledge knowledge) async {
    final db = await database;
    await db.insert('book_knowledge', knowledge.toMap());
  }

  Future<void> deleteBookKnowledge(int id) async {
    final db = await database;
    await db.delete('book_knowledge', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearBookKnowledge(String bookName, String author, {String? type}) async {
    final db = await database;
    if (type != null) {
      await db.delete('book_knowledge', where: 'bookName = ? AND author = ? AND type = ?', whereArgs: [bookName, author, type]);
    } else {
      await db.delete('book_knowledge', where: 'bookName = ? AND author = ?', whereArgs: [bookName, author]);
    }
  }

  // 书籍标记DAO
  Future<List<BookMarking>> getBookMarkings(String bookName, String author) async {
    final db = await database;
    // bookName 为空时返回全部标记（“我的-书籍标记”总览）
    final maps = bookName.isEmpty
        ? await db.query('book_markings', orderBy: 'createTime DESC')
        : await db.query('book_markings', where: 'bookName = ? AND author = ?', whereArgs: [bookName, author], orderBy: 'createTime DESC');
    return maps.map((m) => BookMarking.fromMap(m)).toList();
  }

  Future<void> insertBookMarking(BookMarking marking) async {
    final db = await database;
    await db.insert('book_markings', marking.toMap());
  }

  Future<void> deleteBookMarking(int id) async {
    final db = await database;
    await db.delete('book_markings', where: 'id = ?', whereArgs: [id]);
  }

  // 搜索历史DAO
  Future<List<String>> getSearchHistory({int limit = 20}) async {
    final db = await database;
    final maps = await db.query('search_content_history', orderBy: 'searchTime DESC', limit: limit);
    return maps.map((m) => m['content'].toString()).toList();
  }

  Future<void> saveSearchHistory(String content) async {
    final db = await database;
    await db.insert('search_content_history', {'content': content, 'searchTime': DateTime.now().millisecondsSinceEpoch}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearSearchHistory() async {
    final db = await database;
    await db.delete('search_content_history');
  }

  // 规则订阅DAO
  Future<List<RuleSub>> getRuleSubs() async {
    final db = await database;
    final maps = await db.query('rule_subs', orderBy: 'customOrder ASC');
    return maps.map((m) => RuleSub.fromMap(m)).toList();
  }

  Future<void> insertRuleSub(RuleSub sub) async {
    final db = await database;
    await db.insert('rule_subs', sub.toMap());
  }

  Future<void> deleteRuleSub(int id) async {
    final db = await database;
    await db.delete('rule_subs', where: 'id = ?', whereArgs: [id]);
  }

  // 翻译缓存DAO
}
