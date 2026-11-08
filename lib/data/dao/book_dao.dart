/// book 相关 DAO（由 app_database.dart 拆分，对齐 legado-E data/dao）。
/// 以 part 归属同一库，可直接访问 DatabaseService 的私有 _db。
part of '../local/app_database.dart';

extension DatabaseServiceBookDao on DatabaseService {
  Future<List<Book>> getAllBooks() async {
    final db = await database;
    final maps = await db.query('books', orderBy: 'order_num ASC');
    return maps.map((m) => Book.fromMap(m)).toList();
  }

  Future<Book?> getBook(String name, String author) async {
    final db = await database;
    final maps = await db.query('books', where: 'name = ? AND author = ?', whereArgs: [name, author]);
    return maps.isNotEmpty ? Book.fromMap(maps.first) : null;
  }

  Future<void> insertBook(Book book) async {
    final db = await database;
    await db.insert('books', book.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateBook(Book book) async {
    final db = await database;
    await db.update('books', book.toMap(), where: 'name = ? AND author = ?', whereArgs: [book.name, book.author]);
  }

  Future<void> deleteBook(String name, String author) async {
    final db = await database;
    await db.delete('books', where: 'name = ? AND author = ?', whereArgs: [name, author]);
    await db.delete('book_chapters', where: 'bookName = ? AND bookAuthor = ?', whereArgs: [name, author]);
  }

  // 章节DAO
  Future<List<BookChapter>> getChapters(String bookName, String bookAuthor) async {
    final db = await database;
    final maps = await db.query('book_chapters', where: 'bookName = ? AND bookAuthor = ?', whereArgs: [bookName, bookAuthor], orderBy: 'chapter_index ASC');
    return maps.map((m) => BookChapter.fromMap(m)).toList();
  }

  /// 单章查询：按主键只取一行（保留 content），避免「读一章 = 读全书正文」。
  /// 章节不存在时返回 null。
  Future<BookChapter?> getChapter(String bookName, String bookAuthor, int chapterIndex) async {
    final db = await database;
    final maps = await db.query(
      'book_chapters',
      where: 'bookName = ? AND bookAuthor = ? AND chapter_index = ?',
      whereArgs: [bookName, bookAuthor, chapterIndex],
    );
    return maps.isNotEmpty ? BookChapter.fromMap(maps.first) : null;
  }

  /// 已缓存正文总字符数（SUM(LENGTH(content))），供设置页缓存体积估算，
  /// 避免遍历所有书 × 章节在内存中累加 content.length。
  Future<int> getCachedContentLength() async {
    final db = await database;
    final rows = await db.rawQuery(
        "SELECT SUM(LENGTH(content)) AS total FROM book_chapters WHERE content IS NOT NULL AND content != ''");
    final total = rows.isNotEmpty ? rows.first['total'] : null;
    return total is num ? total.toInt() : 0;
  }

  Future<void> insertChapters(String bookName, String bookAuthor, List<BookChapter> chapters) async {
    final db = await database;
    final batch = db.batch();
    for (final ch in chapters) {
      batch.insert('book_chapters', ch.toMap(bookName, bookAuthor), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit();
  }

  Future<void> saveChapters(String bookName, String bookAuthor, List<BookChapter> chapters) async {
    final db = await database;
    await db.delete('book_chapters', where: 'bookName = ? AND bookAuthor = ?', whereArgs: [bookName, bookAuthor]);
    final batch = db.batch();
    for (final ch in chapters) {
      batch.insert('book_chapters', ch.toMap(bookName, bookAuthor), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit();
  }

  Future<void> updateChapterContent(String bookName, String author, int chapterIndex, String content) async {
    final db = await database;
    await db.update('book_chapters', {'content': content}, where: 'bookName = ? AND bookAuthor = ? AND chapter_index = ?', whereArgs: [bookName, author, chapterIndex]);
  }

  Future<void> deleteChapters(String bookName, String bookAuthor) async {
    final db = await database;
    await db.delete('book_chapters', where: 'bookName = ? AND bookAuthor = ?', whereArgs: [bookName, bookAuthor]);
  }

  // 书源DAO
}
