import '../../domain/repository/rss_repository.dart';
import '../../data/model/rss_article.dart';
import '../../data/model/rss_source.dart';
import '../local/app_database.dart';

class RssRepositoryImpl implements RssRepository {
  final DatabaseService _db;
  RssRepositoryImpl([DatabaseService? db]) : _db = db ?? DatabaseService();

  @override
  Future<List<RssSource>> getRssSources() => _db.getRssSources();
  @override
  Future<void> insertRssSource(RssSource source) => _db.insertRssSource(source);
  @override
  Future<void> updateRssSource(RssSource source) => _db.updateRssSource(source);
  @override
  Future<void> deleteRssSource(int id) => _db.deleteRssSource(id);
  @override
  Future<List<RssArticle>> getRssArticles([String? sourceUrl]) => _db.getRssArticles(sourceUrl);
  @override
  Future<void> saveRssArticles(List<RssArticle> articles) => _db.saveRssArticles(articles);
  @override
  Future<void> toggleRssFavorite(int id, int star) => _db.toggleRssFavorite(id, star);
  @override
  Future<List<Map<String, dynamic>>> getStarredRssArticles() => _db.getStarredRssArticles();
  @override
  Future<void> markRssArticleRead(int id) => _db.markRssArticleRead(id);
}
