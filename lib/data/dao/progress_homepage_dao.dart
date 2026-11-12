/// progress / homepage 相关 DAO。
/// 以 part 归属同一库，可直接访问 DatabaseService 的私有 _db。
part of '../local/app_database.dart';

extension DatabaseServiceProgressHomepageDao on DatabaseService {
  Future<BookProgress?> getBookProgress(String bookName, String author) async {
    final db = await database;
    final maps = await db.query('book_progress', where: 'bookName = ? AND author = ?', whereArgs: [bookName, author], orderBy: 'lastReadTime DESC', limit: 1);
    return maps.isNotEmpty ? BookProgress.fromMap(maps.first) : null;
  }

  Future<void> saveBookProgress(BookProgress progress) async {
    final db = await database;
    await db.insert('book_progress', progress.toMap());
  }

  /// 读取全部书籍的最新阅读进度（每本书取 lastReadTime 最新一条），用于 WebDAV 进度同步
  Future<List<BookProgress>> getAllBookProgress() async {
    final db = await database;
    final maps = await db.rawQuery(
      'SELECT * FROM book_progress p WHERE lastReadTime = '
      '(SELECT MAX(lastReadTime) FROM book_progress WHERE bookName = p.bookName AND author = p.author)',
    );
    return maps.map(BookProgress.fromMap).toList();
  }

  // 首页模块DAO
  Future<List<HomepageModule>> getHomepageModules() async {
    final db = await database;
    final maps = await db.query('homepage_modules', orderBy: 'customOrder ASC');
    return maps.map((m) => HomepageModule.fromMap(m)).toList();
  }

  Future<void> insertHomepageModule(HomepageModule module) async {
    final db = await database;
    await db.insert('homepage_modules', module.toMap());
  }

  Future<void> updateHomepageModule(HomepageModule module) async {
    final db = await database;
    if (module.id != null) {
      await db.update('homepage_modules', module.toMap(), where: 'id = ?', whereArgs: [module.id]);
    }
  }

  Future<void> deleteHomepageModule(int id) async {
    final db = await database;
    await db.delete('homepage_modules', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<HomepageCustomSet>> getHomepageCustomSets() async {
    final db = await database;
    final maps = await db.query('homepage_custom_sets', orderBy: 'customOrder ASC');
    return maps.map((m) => HomepageCustomSet.fromMap(m)).toList();
  }

  Future<void> insertHomepageCustomSet(HomepageCustomSet set) async {
    final db = await database;
    await db.insert('homepage_custom_sets', set.toMap());
  }

  Future<void> deleteHomepageCustomSet(int id) async {
    final db = await database;
    await db.delete('homepage_custom_sets', where: 'id = ?', whereArgs: [id]);
  }

  /* ===== v13：定时任务 / RSS 阅读记录 / 备忘 / 划线 / 下载队列 DAO ===== */

  // 定时任务
}
