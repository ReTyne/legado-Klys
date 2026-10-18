import '../local/app_database.dart';
import '../model/rss_article.dart';
import '../model/rss_source.dart';

class RssSourceDao {
  final DatabaseService _db;
  RssSourceDao([DatabaseService? db]) : _db = db ?? DatabaseService();

  Future<List<RssSource>> sources() => _db.getRssSources();
  Future<void> insertSource(RssSource s) => _db.insertRssSource(s);
  Future<void> updateSource(RssSource s) => _db.updateRssSource(s);
  Future<void> deleteSource(int id) => _db.deleteRssSource(id);
  Future<List<RssArticle>> articles([String? url]) => _db.getRssArticles(url);
  Future<void> saveArticles(List<RssArticle> list) => _db.saveRssArticles(list);
  Future<void> toggleFavorite(int id, int star) => _db.toggleRssFavorite(id, star);
  Future<List<Map<String, dynamic>>> starred() => _db.getStarredRssArticles();
  Future<void> markRead(int id) => _db.markRssArticleRead(id);
}
