/// rss 相关 DAO（由 app_database.dart 拆分，对齐 legado-E data/dao）。
/// 以 part 归属同一库，可直接访问 DatabaseService 的私有 _db。
part of '../local/app_database.dart';

extension DatabaseServiceRssDao on DatabaseService {
  Future<List<RssSource>> getRssSources() async {
    final db = await database;
    final maps = await db.query('rss_sources', orderBy: 'lastUpdateTime DESC');
    return maps.map((m) => RssSource.fromMap(m)).toList();
  }

  Future<void> insertRssSource(RssSource source) async {
    final db = await database;
    await db.insert('rss_sources', source.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateRssSource(RssSource source) async {
    final db = await database;
    if (source.id != null) await db.update('rss_sources', source.toMap(), where: 'id = ?', whereArgs: [source.id]);
  }

  Future<void> deleteRssSource(int id) async {
    final db = await database;
    await db.delete('rss_sources', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<RssArticle>> getRssArticles([String? sourceUrl]) async {
    final db = await database;
    final maps = sourceUrl != null
        ? await db.query('rss_articles', where: 'sourceUrl = ?', whereArgs: [sourceUrl], orderBy: 'pubDate DESC')
        : await db.query('rss_articles', orderBy: 'pubDate DESC');
    return maps.map((m) => RssArticle.fromMap(m)).toList();
  }

  Future<void> insertRssArticle(RssArticle article) async {
    final db = await database;
    await db.insert('rss_articles', article.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> saveRssArticles(List<RssArticle> articles) async {
    final db = await database;
    final batch = db.batch();
    for (final a in articles) {
      batch.insert('rss_articles', a.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit();
  }

  Future<void> toggleRssFavorite(int id, int star) async {
    final db = await database;
    // 同时写入旧列 star 与模型读取的 starred，保证列表/收藏两处状态一致
    await db.update('rss_articles', {'star': star, 'starred': star}, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getStarredRssArticles() async {
    final db = await database;
    return db.query('rss_articles', where: 'star = 1 OR starred = 1', orderBy: 'pubDate DESC');
  }

  Future<void> markRssArticleRead(int id) async {
    final db = await database;
    await db.update('rss_articles', {'read': 1, 'isRead': 1, 'readTime': DateTime.now().millisecondsSinceEpoch}, where: 'id = ?', whereArgs: [id]);
  }

  /// 设置一篇 RSS 文章已读/未读
  Future<void> setRssArticleRead(int id, bool read) async {
    final db = await database;
    await db.update('rss_articles', {'read': read ? 1 : 0, 'isRead': read ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
  }

  /// 将某订阅源（或全部）文章标为已读
  Future<void> markAllRssRead({String? sourceUrl}) async {
    final db = await database;
    final values = {'read': 1, 'isRead': 1, 'readTime': DateTime.now().millisecondsSinceEpoch};
    if (sourceUrl == null) {
      await db.update('rss_articles', values);
    } else {
      await db.update('rss_articles', values, where: 'sourceUrl = ?', whereArgs: [sourceUrl]);
    }
  }

  /// 星标/取消星标一篇 RSS 文章
  Future<void> setRssArticleStar(int id, bool star) async {
    final db = await database;
    final v = star ? 1 : 0;
    await db.update('rss_articles', {'star': v, 'starred': v}, where: 'id = ?', whereArgs: [id]);
  }

  // TXT目录规则DAO
}
