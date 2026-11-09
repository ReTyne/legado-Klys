/// book 相关 DAO（由 app_database.dart 拆分，对齐 legado-E data/dao）。
/// 以 part 归属同一库，可直接访问 DatabaseService 的私有 _db。
part of '../local/app_database.dart';

extension DatabaseServiceBookDao on DatabaseService {
  Future<List<Book>> getAllBooks() async {
    final db = await database;
    final maps = await db.query('books', orderBy: 'order_num ASC');
    return maps.map((m) => Book.fromMap(m)).toList();
  }

  /// 真·位运算 SQL：对 books.type 执行 `type & mask > 0`（对齐上游 BookDao 表达式）。
  /// 显式标注：本项目 books.type 为顺序枚举(0..4)，仅当数据已按位标志落库
  /// （如 search_books 表 type 默认 8、或导入的上游备份）时结果才与上游一致。
  Future<List<Book>> getBooksByTypeBitmask(int mask) async {
    final db = await database;
    final maps = await db.rawQuery(
      'SELECT * FROM books WHERE (type & ?) > 0',
      <Object?>[mask],
    );
    return maps.map((m) => Book.fromMap(m)).toList();
  }

  /// 虚拟分组按位规则过滤（对齐 legado-E BookDao.flowByGroup，报告 #17）。
  ///
  /// 本项目 books.type 存顺序枚举、group_name 存分组名（非位掩码），
  /// 无法直接对列套用上游 `type & mask` / `sum(groupId) & group` SQL，
  /// 故采用报告允许的等价方案：把每本书投影成位标志/位掩码，再用
  /// [BookGroupQuery.matchesGroup] 应用同一套位规则。
  /// [groupBitsOf] 由调用方把书映射成 group 位掩码（默认 0=未分组）；
  /// [userGroupsSum] 对应上游 `sum(groupId) where groupId > 0`；
  /// [netNoneShow] 为 IdNetNone 分组的 show 值。
  Future<List<Book>> getBooksByVirtualGroup(
    int groupId, {
    int userGroupsSum = 0,
    int netNoneShow = 1,
    int Function(Book book)? groupBitsOf,
  }) async {
    final List<Book> all = await getAllBooks();
    return all.where((Book b) {
      final int typeFlags = BookGroupQuery.projectFlutterType(
        b.type,
        origin: b.origin,
        local: b.local,
      );
      final int groupBits = groupBitsOf == null ? 0 : groupBitsOf(b);
      return BookGroupQuery.matchesGroup(
        typeFlags: typeFlags,
        groupBits: groupBits,
        groupId: groupId,
        userGroupsSum: userGroupsSum,
        netNoneShow: netNoneShow,
      );
    }).toList();
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
