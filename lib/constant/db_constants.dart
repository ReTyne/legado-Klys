/// 数据库常量：库名、版本、表名
class DbConstants {
  DbConstants._();

  static const String dbName = 'legado.db';
  static const int dbVersion = 6;

  static const String tableBooks = 'books';
  static const String tableBookChapters = 'book_chapters';
  static const String tableBookSources = 'book_sources';
  static const String tableBookGroups = 'book_groups';
  static const String tableBookKnowledge = 'book_knowledge';
  static const String tableBookProgress = 'book_progress';
  static const String tableBookMarkings = 'book_markings';
  static const String tableBookmarks = 'bookmarks';
  static const String tableCaches = 'caches';
  static const String tableCloudTtsEngines = 'cloud_tts_engines';
  static const String tableCookies = 'cookies';
  static const String tableDictRules = 'dict_rules';
  static const String tableHighlightRules = 'highlight_rules';
  static const String tableHighlightTagRules = 'highlight_tag_rules';
  static const String tableHttpTts = 'http_tts';
  static const String tableReadRecords = 'read_records';
  static const String tableReplaceRules = 'replace_rules';
  static const String tableRssSources = 'rss_sources';
  static const String tableRssArticles = 'rss_articles';
  static const String tableRssStars = 'rss_stars';
  static const String tableTxtTocRules = 'txt_toc_rules';
  static const String tableTagGroupRules = 'tag_group_rules';
}
