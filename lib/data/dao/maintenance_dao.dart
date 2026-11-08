/// maintenance 相关 DAO（由 app_database.dart 拆分，对齐 legado-E data/dao）。
/// 以 part 归属同一库，可直接访问 DatabaseService 的私有 _db。
part of '../local/app_database.dart';

extension DatabaseServiceMaintenanceDao on DatabaseService {
  Future<String?> getBookReadConfig(String name, String author) async {
    final db = await database;
    final maps = await db.query('books', columns: ['readConfig'],
        where: 'name = ? AND author = ?', whereArgs: [name, author], limit: 1);
    return maps.isEmpty ? null : maps.first['readConfig'] as String?;
  }

  Future<void> setBookReadConfig(String name, String author, String configJson) async {
    final db = await database;
    await db.update('books', {'readConfig': configJson},
        where: 'name = ? AND author = ?', whereArgs: [name, author]);
  }

  // --- 数据库维护 ---
  Future<void> shrinkDatabase() async {
    final db = await database;
    await db.execute('VACUUM');
  }

  /// ReaderProvider 用：Dart 侧统一查询入口，返回 JSON 串，供原生 ContentProvider 消费。
  Future<String> readerProviderQuery(String op, Map<String, dynamic> args) async {
    try {
      final db = await database;
      dynamic data;
      switch (op) {
        case 'GetBookshelf':
          data = await db.query('books', orderBy: 'order_num ASC');
          break;
        case 'GetBookSources':
          data = await db.query('book_sources');
          break;
        case 'GetRssSources':
          data = await db.query('rss_sources');
          break;
        case 'GetBookSource':
          data = await db.query('book_sources',
              where: 'bookSourceUrl = ?', whereArgs: [args['url']]);
          break;
        case 'GetRssSource':
          data = await db.query('rss_sources',
              where: 'url = ?', whereArgs: [args['url']]);
          break;
        case 'GetChapterList':
          data = await db.query('book_chapters',
              where: 'bookName = ? AND bookAuthor = ?',
              whereArgs: [args['name'], args['author']], orderBy: 'chapter_index ASC');
          break;
        case 'GetBookContent':
          final maps = await db.query('book_chapters', columns: ['content'],
              where: 'bookName = ? AND bookAuthor = ? AND chapter_index = ?',
              whereArgs: [args['name'], args['author'], args['index']], limit: 1);
          data = maps.isEmpty ? '' : (maps.first['content'] ?? '');
          break;
        case 'GetBookCover':
          final maps = await db.query('books', columns: ['coverUrl', 'customCoverUrl'],
              where: 'name = ? AND author = ?',
              whereArgs: [args['name'], args['author']], limit: 1);
          data = maps.isEmpty ? '' : (maps.first['customCoverUrl'] ?? maps.first['coverUrl'] ?? '');
          break;
        default:
          // Save*/Delete*/RefreshToc 等写操作：数据由 Dart 侧业务服务处理，
          // 这里返回成功标记，原生 Provider 依据 isSuccess 决定回显。
          data = <String, dynamic>{};
      }
      return jsonEncode({'isSuccess': true, 'errorMsg': '', 'data': data});
    } catch (e) {
      return jsonEncode({'isSuccess': false, 'errorMsg': e.toString(), 'data': null});
    }
  }
}
