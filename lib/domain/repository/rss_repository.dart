import '../../data/model/rss_article.dart';
import '../../data/model/rss_source.dart';

/// RSS 订阅仓库接口
abstract class RssRepository {
  Future<List<RssSource>> getRssSources();
  Future<void> insertRssSource(RssSource source);
  Future<void> updateRssSource(RssSource source);
  Future<void> deleteRssSource(int id);
  Future<List<RssArticle>> getRssArticles([String? sourceUrl]);
  Future<void> saveRssArticles(List<RssArticle> articles);
  Future<void> toggleRssFavorite(int id, int star);
  Future<List<Map<String, dynamic>>> getStarredRssArticles();
  Future<void> markRssArticleRead(int id);
}
