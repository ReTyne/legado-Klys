import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_chapter.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/data/model/book_group.dart';
import 'package:legado_md3/data/model/book_knowledge.dart';
import 'package:legado_md3/data/model/book_progress.dart';
import 'package:legado_md3/data/model/book_marking.dart';
import 'package:legado_md3/data/model/bookmark.dart';
import 'package:legado_md3/data/model/cache.dart';
import 'package:legado_md3/data/model/cloud_tts_engine.dart';
import 'package:legado_md3/data/model/dict_rule.dart';
import 'package:legado_md3/data/model/highlight_rule.dart';
import 'package:legado_md3/data/model/highlight_tag_rule.dart';
import 'package:legado_md3/data/model/http_tts.dart';
import 'package:legado_md3/data/model/read_record.dart';
import '../model/replace_rule.dart' hide ReadRecord;
import 'package:legado_md3/data/model/rss_source.dart';
import 'package:legado_md3/data/model/rss_article.dart';
import 'package:legado_md3/data/model/rss_star.dart';
import 'package:legado_md3/data/model/rule_sub.dart';
import 'package:legado_md3/data/model/server.dart';
import 'package:legado_md3/data/model/tag_group_rule.dart';
import 'package:legado_md3/data/model/txt_toc_rule.dart';
import 'package:legado_md3/data/model/keyboard_assist.dart';
import 'package:legado_md3/data/model/homepage_module.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _db;
  static const int _dbVersion = 8;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final fullPath = path.join(dbPath, 'legado_md3.db');
    return openDatabase(fullPath, version: _dbVersion, onCreate: _onCreate, onUpgrade: _onUpgrade);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 6) {
      try { await db.execute('ALTER TABLE replace_rules ADD COLUMN isTitle INTEGER DEFAULT 0'); } catch (_) {}
      try { await db.execute('ALTER TABLE replace_rules ADD COLUMN isContent INTEGER DEFAULT 1'); } catch (_) {}
      try { await db.execute('ALTER TABLE replace_rules ADD COLUMN isRegex INTEGER DEFAULT 1'); } catch (_) {}
    }
    if (oldVersion < 7) {
      // book_chapters 旧表用保留字 "index" 且缺 start_pos/end_pos/variable，重建并迁移
      try {
        await db.execute('ALTER TABLE book_chapters RENAME TO book_chapters_old');
      } catch (_) {}
      await db.execute('CREATE TABLE IF NOT EXISTS book_chapters (bookName TEXT NOT NULL, bookAuthor TEXT NOT NULL, chapter_index INTEGER NOT NULL, title TEXT, url TEXT, baseUrl TEXT, isVolume INTEGER DEFAULT 0, isPay INTEGER DEFAULT 0, tag TEXT, resourceUrl TEXT, content TEXT, start_pos INTEGER, end_pos INTEGER, variable TEXT, PRIMARY KEY (bookName, bookAuthor, chapter_index))');
      try {
        await db.execute('INSERT OR REPLACE INTO book_chapters (bookName, bookAuthor, chapter_index, title, url, baseUrl, isVolume, isPay, tag, resourceUrl, content) SELECT bookName, bookAuthor, "index", title, url, baseUrl, isVolume, isPay, tag, resourceUrl, content FROM book_chapters_old');
        await db.execute('DROP TABLE book_chapters_old');
      } catch (_) {}
    }
    if (oldVersion < 8) {
      // v8：让所有表结构与各模型 toMap/fromMap 对齐（旧建表语句缺列会导致写入抛
      // “table X has no column named Y”）。逐列 ADD，已存在/失败均忽略，保证可重入。
      await _addColumnsIfMissing(db, 'books', const [
        'coverUrl TEXT', 'intro TEXT', 'kind TEXT', 'lastChapter TEXT', 'lastChapterIndex INTEGER',
        'durChapterIndex INTEGER', 'durChapterPos INTEGER', 'durChapterTime INTEGER', 'noteUrl TEXT',
        'bookUrl TEXT', 'origin TEXT', 'originName TEXT', 'tag TEXT', 'wordCount INTEGER',
        'canUpdate INTEGER DEFAULT 1', 'local INTEGER DEFAULT 0', 'type INTEGER DEFAULT 0',
        'group_name TEXT', 'order_num INTEGER', 'latestChapterTime INTEGER', 'lastCheckTime INTEGER',
        'infoHtml TEXT', 'tocHtml TEXT', 'variable TEXT', 'customOrder INTEGER',
        'allowUpdate INTEGER DEFAULT 1', 'fileName TEXT', 'customCoverUrl TEXT', 'bookComment TEXT',
      ]);
      await _addColumnsIfMissing(db, 'book_sources', const [
        'loginUi TEXT', 'loginCheckJs TEXT', 'coverDecodeJs TEXT', 'eventListener INTEGER DEFAULT 0',
        'customButton INTEGER DEFAULT 0', 'enabledCookieJar INTEGER DEFAULT 0', 'concurrentRate TEXT',
        'homepageModules TEXT', 'checkKeyWord TEXT', 'exploreScreen TEXT', 'ruleImage TEXT',
        'variableComment TEXT', 'jsLib TEXT', 'variable TEXT',
      ]);
      await _addColumnsIfMissing(db, 'bookmarks', const [
        'bookAuthor TEXT', 'pageIndex INTEGER DEFAULT 0',
      ]);
      await _addColumnsIfMissing(db, 'replace_rules', const ['order_num INTEGER']);
      await _addColumnsIfMissing(db, 'rss_sources', const [
        'sourceIcon TEXT', 'group_name TEXT', 'sourceComment TEXT', 'searchUrl TEXT', 'sortUrl TEXT',
        'loginUrl TEXT', 'loginUi TEXT', 'loginCheckJs TEXT', 'coverDecodeJs TEXT', 'header TEXT',
        'variableComment TEXT', 'concurrentRate TEXT', 'jsLib TEXT', 'startHtml TEXT', 'startStyle TEXT',
        'startJs TEXT', 'preloadJs TEXT', 'ruleArticles TEXT', 'ruleNextPage TEXT', 'ruleTitle TEXT',
        'rulePubDate TEXT', 'ruleDescription TEXT', 'ruleImage TEXT', 'ruleLink TEXT', 'ruleContent TEXT',
        'style TEXT', 'injectJs TEXT', 'contentWhitelist TEXT', 'contentBlacklist TEXT',
        'shouldOverrideUrlLoading TEXT', 'customOrder INTEGER', 'unreadCount INTEGER DEFAULT 0',
        'variable TEXT', 'enabledCookieJar INTEGER DEFAULT 0',
      ]);
      await _addColumnsIfMissing(db, 'rss_articles', const [
        'description TEXT', 'author TEXT', 'category TEXT', 'sourceName TEXT',
        'isRead INTEGER DEFAULT 0', 'starred INTEGER DEFAULT 0', 'readTime INTEGER',
        'image TEXT', 'content TEXT',
      ]);
      await _addColumnsIfMissing(db, 'txt_toc_rules', const [
        'name TEXT', 'volumeRule TEXT', 'example TEXT', 'serialNumber INTEGER DEFAULT -1',
      ]);
    }
    await _onCreate(db, newVersion);
  }

  /// 给已存在的表逐列补列（SQLite 不支持 ADD COLUMN IF NOT EXISTS，逐列 try/catch）
  Future<void> _addColumnsIfMissing(Database db, String table, List<String> columns) async {
    for (final col in columns) {
      try {
        await db.execute('ALTER TABLE $table ADD COLUMN $col');
      } catch (_) {
        // 列已存在等情况：忽略
      }
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('CREATE TABLE IF NOT EXISTS books (name TEXT NOT NULL, author TEXT NOT NULL, coverUrl TEXT, intro TEXT, kind TEXT, lastChapter TEXT, lastChapterIndex INTEGER, durChapterIndex INTEGER, durChapterPos INTEGER, durChapterTime INTEGER, noteUrl TEXT, bookUrl TEXT, origin TEXT, originName TEXT, tag TEXT, wordCount INTEGER, canUpdate INTEGER DEFAULT 1, local INTEGER DEFAULT 0, type INTEGER DEFAULT 0, group_name TEXT, order_num INTEGER, latestChapterTime INTEGER, lastCheckTime INTEGER, infoHtml TEXT, tocHtml TEXT, variable TEXT, customOrder INTEGER, allowUpdate INTEGER DEFAULT 1, fileName TEXT, customCoverUrl TEXT, bookComment TEXT, latestChapterTitle TEXT, lastChapterTime INTEGER, updateTime INTEGER, "order" INTEGER, groupId INTEGER, PRIMARY KEY (name, author))');
    await db.execute('CREATE TABLE IF NOT EXISTS book_chapters (bookName TEXT NOT NULL, bookAuthor TEXT NOT NULL, chapter_index INTEGER NOT NULL, title TEXT, url TEXT, baseUrl TEXT, isVolume INTEGER DEFAULT 0, isPay INTEGER DEFAULT 0, tag TEXT, resourceUrl TEXT, content TEXT, start_pos INTEGER, end_pos INTEGER, variable TEXT, PRIMARY KEY (bookName, bookAuthor, chapter_index))');
    await db.execute('CREATE TABLE IF NOT EXISTS book_sources (bookSourceUrl TEXT PRIMARY KEY, bookSourceName TEXT, bookSourceGroup TEXT, bookSourceType INTEGER, bookSourceComment TEXT, lastUpdateTime INTEGER, enabled INTEGER DEFAULT 1, enabledExplore INTEGER DEFAULT 1, customOrder INTEGER, respondTime INTEGER, weight INTEGER, header TEXT, loginUrl TEXT, loginUi TEXT, loginCheckJs TEXT, bookUrlPattern TEXT, charset TEXT, coverDecodeJs TEXT, eventListener INTEGER DEFAULT 0, customButton INTEGER DEFAULT 0, enabledCookieJar INTEGER DEFAULT 0, concurrentRate TEXT, homepageModules TEXT, searchUrl TEXT, checkKeyWord TEXT, exploreUrl TEXT, exploreScreen TEXT, ruleSearch TEXT, ruleExplore TEXT, ruleBookInfo TEXT, ruleToc TEXT, ruleContent TEXT, ruleReview TEXT, ruleImage TEXT, variableComment TEXT, jsLib TEXT, variable TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS book_groups (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, "order" INTEGER, show INTEGER DEFAULT 1, cover TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS book_knowledge (id INTEGER PRIMARY KEY AUTOINCREMENT, bookName TEXT, author TEXT, type TEXT, name TEXT, content TEXT, cover TEXT, "order" INTEGER)');
    await db.execute('CREATE TABLE IF NOT EXISTS book_progress (id INTEGER PRIMARY KEY AUTOINCREMENT, bookName TEXT, author TEXT, chapterIndex INTEGER, pagePos INTEGER, duration INTEGER, lastReadTime INTEGER)');
    await db.execute('CREATE TABLE IF NOT EXISTS book_markings (id INTEGER PRIMARY KEY AUTOINCREMENT, bookName TEXT, author TEXT, chapterIndex INTEGER, chapterTitle TEXT, pagePos INTEGER, content TEXT, note TEXT, color INTEGER, createTime INTEGER)');
    await db.execute('CREATE TABLE IF NOT EXISTS bookmarks (id INTEGER PRIMARY KEY AUTOINCREMENT, bookName TEXT, bookAuthor TEXT, chapterIndex INTEGER, chapterTitle TEXT, pageIndex INTEGER DEFAULT 0, content TEXT, createTime INTEGER, author TEXT, pagePos INTEGER, note TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS caches (id INTEGER PRIMARY KEY AUTOINCREMENT, bookName TEXT, author TEXT, chapterIndex INTEGER, chapterTitle TEXT, content TEXT, size INTEGER, saveTime INTEGER)');
    await db.execute('CREATE TABLE IF NOT EXISTS cloud_tts_engines (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, type TEXT, url TEXT, apiKey TEXT, region TEXT, voice TEXT, rate INTEGER, pitch INTEGER, enabled INTEGER DEFAULT 1, concurrentRate INTEGER)');
    await db.execute('CREATE TABLE IF NOT EXISTS cookies (id INTEGER PRIMARY KEY AUTOINCREMENT, url TEXT, cookie TEXT, lastUpdateTime INTEGER)');
    await db.execute('CREATE TABLE IF NOT EXISTS dict_rules (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, summary TEXT, url TEXT, rule TEXT, enabled INTEGER DEFAULT 1, "order" INTEGER)');
    await db.execute('CREATE TABLE IF NOT EXISTS highlight_rules (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, pattern TEXT, color INTEGER, enabled INTEGER DEFAULT 1, "order" INTEGER)');
    await db.execute('CREATE TABLE IF NOT EXISTS highlight_tag_rules (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, pattern TEXT, color INTEGER, enabled INTEGER DEFAULT 1, "order" INTEGER, scope TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS http_tts (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, url TEXT, method TEXT, headers TEXT, body TEXT, enabled INTEGER DEFAULT 1, concurrentRate INTEGER)');
    await db.execute('CREATE TABLE IF NOT EXISTS read_records (id INTEGER PRIMARY KEY AUTOINCREMENT, bookName TEXT, author TEXT, duration INTEGER, date INTEGER, chapterIndex INTEGER, pagePos INTEGER)');
    await db.execute('CREATE TABLE IF NOT EXISTS replace_rules (id INTEGER PRIMARY KEY AUTOINCREMENT, replaceSummary TEXT, replaceRule TEXT, replacement TEXT, enable INTEGER DEFAULT 1, isTitle INTEGER DEFAULT 0, isContent INTEGER DEFAULT 1, isRegex INTEGER DEFAULT 1, scope TEXT, order_num INTEGER, "order" INTEGER)');
    await db.execute('CREATE TABLE IF NOT EXISTS rss_sources (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, url TEXT, sourceIcon TEXT, group_name TEXT, sourceComment TEXT, searchUrl TEXT, sortUrl TEXT, loginUrl TEXT, loginUi TEXT, loginCheckJs TEXT, coverDecodeJs TEXT, header TEXT, variableComment TEXT, concurrentRate TEXT, jsLib TEXT, startHtml TEXT, startStyle TEXT, startJs TEXT, preloadJs TEXT, ruleArticles TEXT, ruleNextPage TEXT, ruleTitle TEXT, rulePubDate TEXT, ruleDescription TEXT, ruleImage TEXT, ruleLink TEXT, ruleContent TEXT, style TEXT, injectJs TEXT, contentWhitelist TEXT, contentBlacklist TEXT, shouldOverrideUrlLoading TEXT, enabled INTEGER DEFAULT 1, customOrder INTEGER, lastUpdateTime INTEGER, unreadCount INTEGER DEFAULT 0, variable TEXT, enabledCookieJar INTEGER DEFAULT 0, "group" TEXT, icon TEXT, description TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS rss_articles (id INTEGER PRIMARY KEY AUTOINCREMENT, sourceUrl TEXT, title TEXT, link TEXT, description TEXT, content TEXT, image TEXT, pubDate INTEGER, author TEXT, category TEXT, sourceName TEXT, isRead INTEGER DEFAULT 0, starred INTEGER DEFAULT 0, readTime INTEGER, star INTEGER DEFAULT 0, desc TEXT, read INTEGER DEFAULT 0)');
    await db.execute('CREATE TABLE IF NOT EXISTS rss_stars (id INTEGER PRIMARY KEY AUTOINCREMENT, sourceUrl TEXT, title TEXT, link TEXT, desc TEXT, content TEXT, starTime INTEGER)');
    await db.execute('CREATE TABLE IF NOT EXISTS rule_subs (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, url TEXT, type TEXT, enabled INTEGER DEFAULT 1, lastUpdateTime INTEGER, customOrder INTEGER)');
    await db.execute('CREATE TABLE IF NOT EXISTS search_content_history (id INTEGER PRIMARY KEY AUTOINCREMENT, content TEXT, searchTime INTEGER)');
    await db.execute('CREATE TABLE IF NOT EXISTS servers (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, host TEXT, port INTEGER, path TEXT, username TEXT, password TEXT, enabled INTEGER DEFAULT 1)');
    await db.execute('CREATE TABLE IF NOT EXISTS tag_group_rules (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, pattern TEXT, "group" TEXT, enabled INTEGER DEFAULT 1, "order" INTEGER)');
    await db.execute('CREATE TABLE IF NOT EXISTS translation_caches (id INTEGER PRIMARY KEY AUTOINCREMENT, source TEXT, target TEXT, original TEXT, translated TEXT, saveTime INTEGER)');
    await db.execute('CREATE TABLE IF NOT EXISTS txt_toc_rules (id INTEGER PRIMARY KEY, name TEXT, chapterRule TEXT, volumeRule TEXT, example TEXT, serialNumber INTEGER DEFAULT -1, enable INTEGER DEFAULT 1, "order" INTEGER)');
    await db.execute('CREATE TABLE IF NOT EXISTS keyboard_assists (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, rule TEXT, enabled INTEGER DEFAULT 1, "order" INTEGER)');
    await db.execute('CREATE TABLE IF NOT EXISTS homepage_modules (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, type INTEGER, sourceUrl TEXT, exploreUrl TEXT, config TEXT, customOrder INTEGER, enabled INTEGER DEFAULT 1)');
    await db.execute('CREATE TABLE IF NOT EXISTS homepage_custom_sets (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, moduleIds TEXT, customOrder INTEGER)');
  }

  // 书籍DAO
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
  Future<List<BookSource>> getAllSources({bool? enabled}) async {
    final db = await database;
    final maps = enabled != null
        ? await db.query('book_sources', where: 'enabled = ?', whereArgs: [enabled ? 1 : 0], orderBy: 'customOrder ASC')
        : await db.query('book_sources', orderBy: 'customOrder ASC');
    return maps.map((m) => BookSource.fromMap(m)).toList();
  }

  Future<BookSource?> getSource(String url) async {
    final db = await database;
    final maps = await db.query('book_sources', where: 'bookSourceUrl = ?', whereArgs: [url]);
    return maps.isNotEmpty ? BookSource.fromMap(maps.first) : null;
  }

  Future<void> insertSource(BookSource source) async {
    final db = await database;
    await db.insert('book_sources', source.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateSource(BookSource source) async {
    final db = await database;
    await db.update('book_sources', source.toMap(), where: 'bookSourceUrl = ?', whereArgs: [source.bookSourceUrl]);
  }

  /// 仅更新书源运行时变量 variable（JS setVariable 落库，避免整行覆盖）。
  Future<void> updateSourceVariable(String sourceUrl, String variable) async {
    final db = await database;
    await db.update('book_sources', {'variable': variable},
        where: 'bookSourceUrl = ?', whereArgs: [sourceUrl]);
  }

  /// 仅更新订阅源运行时变量 variable（JS setVariable 落库）。
  Future<void> updateRssSourceVariable(String sourceUrl, String variable) async {
    final db = await database;
    await db.update('rss_sources', {'variable': variable},
        where: 'url = ?', whereArgs: [sourceUrl]);
  }

  Future<void> deleteSource(String url) async {
    final db = await database;
    await db.delete('book_sources', where: 'bookSourceUrl = ?', whereArgs: [url]);
  }

  Future<List<String>> getSourceGroups() async {
    final db = await database;
    final maps = await db.rawQuery('SELECT DISTINCT bookSourceGroup FROM book_sources WHERE bookSourceGroup IS NOT NULL AND bookSourceGroup != ""');
    return maps.map((m) => m['bookSourceGroup'].toString()).toList();
  }

  // 分组DAO
  Future<List<BookGroup>> getBookGroups() async {
    final db = await database;
    final maps = await db.query('book_groups', orderBy: '"order" ASC');
    return maps.map((m) => BookGroup.fromMap(m)).toList();
  }

  Future<void> insertBookGroup(BookGroup group) async {
    final db = await database;
    // 带 id 时按主键覆盖，避免显隐/排序保存产生重复行
    await db.insert('book_groups', group.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteBookGroup(int id) async {
    final db = await database;
    await db.delete('book_groups', where: 'id = ?', whereArgs: [id]);
  }

  /// 按名称删除分组元数据
  Future<void> deleteBookGroupByName(String name) async {
    final db = await database;
    await db.delete('book_groups', where: 'name = ?', whereArgs: [name]);
  }

  /// 重命名分组：同步更新元数据与该分组下所有书籍
  Future<void> renameBookGroup(String oldName, String newName) async {
    final db = await database;
    await db.update('book_groups', {'name': newName},
        where: 'name = ?', whereArgs: [oldName]);
    await db.update('books', {'group_name': newName},
        where: 'group_name = ?', whereArgs: [oldName]);
  }

  /// 解散分组：分组下书籍回到未分组，并删除元数据
  Future<void> dissolveBookGroup(String name) async {
    final db = await database;
    await db.update('books', {'group_name': null},
        where: 'group_name = ?', whereArgs: [name]);
    await db.delete('book_groups', where: 'name = ?', whereArgs: [name]);
  }

  // 书签DAO
  Future<List<Bookmark>> getBookmarks([String? bookName, String? author]) async {
    final db = await database;
    final maps = bookName != null
        ? await db.query('bookmarks', where: 'bookName = ? AND bookAuthor = ?', whereArgs: [bookName, author], orderBy: 'createTime DESC')
        : await db.query('bookmarks', orderBy: 'createTime DESC');
    return maps.map((m) => Bookmark.fromMap(m)).toList();
  }

  Future<void> insertBookmark(Bookmark bookmark) async {
    final db = await database;
    await db.insert('bookmarks', bookmark.toMap());
  }

  Future<void> addBookmark(Bookmark bookmark) async {
    await insertBookmark(bookmark);
  }

  Future<void> deleteBookmark(int id) async {
    final db = await database;
    await db.delete('bookmarks', where: 'id = ?', whereArgs: [id]);
  }

  // 替换规则DAO
  Future<List<ReplaceRule>> getReplaceRules() async {
    final db = await database;
    final maps = await db.query('replace_rules', orderBy: 'order_num ASC');
    return maps.map((m) => ReplaceRule.fromMap(m)).toList();
  }

  Future<void> insertReplaceRule(ReplaceRule rule) async {
    final db = await database;
    await db.insert('replace_rules', rule.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateReplaceRule(ReplaceRule rule) async {
    final db = await database;
    if (rule.id != null) await db.update('replace_rules', rule.toMap(), where: 'id = ?', whereArgs: [rule.id]);
  }

  Future<void> deleteReplaceRule(int id) async {
    final db = await database;
    await db.delete('replace_rules', where: 'id = ?', whereArgs: [id]);
  }

  // RSS DAO
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
  Future<List<TxtTocRule>> getTxtTocRules() async {
    final db = await database;
    final maps = await db.query('txt_toc_rules', orderBy: 'serialNumber ASC');
    return maps.map((m) => TxtTocRule.fromMap(m)).toList();
  }

  Future<void> insertTxtTocRule(TxtTocRule rule) async {
    final db = await database;
    await db.insert('txt_toc_rules', rule.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteTxtTocRule(int id) async {
    final db = await database;
    await db.delete('txt_toc_rules', where: 'id = ?', whereArgs: [id]);
  }

  // 阅读记录DAO
  Future<void> updateReadPosition(String bookName, String author, int chapterIndex, int pagePos, int time) async {
    final db = await database;
    await db.insert('read_records', {'bookName': bookName, 'author': author, 'chapterIndex': chapterIndex, 'pagePos': pagePos, 'duration': 0, 'date': time});
  }

  Future<List<ReadRecord>> getReadRecords([int? limit]) async {
    final db = await database;
    final maps = await db.query('read_records', orderBy: 'date DESC', limit: limit);
    return maps.map((m) => ReadRecord.fromMap(m)).toList();
  }

  Future<void> addReadRecord(String bookName, String author, int duration, int date) async {
    final db = await database;
    await db.insert('read_records', {'bookName': bookName, 'author': author, 'duration': duration, 'date': date});
  }

  // 缓存DAO
  Future<List<Cache>> getCaches() async {
    final db = await database;
    final maps = await db.query('caches', orderBy: 'saveTime DESC');
    return maps.map((m) => Cache.fromMap(m)).toList();
  }

  Future<void> insertCache(Cache cache) async {
    final db = await database;
    await db.insert('caches', cache.toMap());
  }

  Future<void> clearCaches() async {
    final db = await database;
    await db.delete('caches');
  }

  /// 收缩数据库，回收已删除数据占用的空闲页（VACUUM 不能在事务中执行）
  Future<void> vacuum() async {
    final db = await database;
    await db.execute('VACUUM');
  }

  /// 清空所有书籍的章节正文缓存（保留目录结构，仅把 content 置空）
  Future<void> clearChapterContent() async {
    final db = await database;
    await db.update('book_chapters', {'content': null});
  }

  /// 清空单本书籍的章节正文缓存
  Future<void> clearBookChapterContent(String bookName, String bookAuthor) async {
    final db = await database;
    await db.update(
      'book_chapters',
      {'content': null},
      where: 'bookName = ? AND bookAuthor = ?',
      whereArgs: [bookName, bookAuthor],
    );
  }

  // 字典规则DAO
  Future<List<DictRule>> getDictRules() async {
    final db = await database;
    final maps = await db.query('dict_rules', orderBy: '"order" ASC');
    return maps.map((m) => DictRule.fromMap(m)).toList();
  }

  Future<void> insertDictRule(DictRule rule) async {
    final db = await database;
    await db.insert('dict_rules', rule.toMap());
  }

  Future<void> deleteDictRule(int id) async {
    final db = await database;
    await db.delete('dict_rules', where: 'id = ?', whereArgs: [id]);
  }

  // 高亮规则DAO
  Future<List<HighlightRule>> getHighlightRules() async {
    final db = await database;
    final maps = await db.query('highlight_rules', orderBy: '"order" ASC');
    return maps.map((m) => HighlightRule.fromMap(m)).toList();
  }

  Future<void> insertHighlightRule(HighlightRule rule) async {
    final db = await database;
    await db.insert('highlight_rules', rule.toMap());
  }

  Future<void> deleteHighlightRule(int id) async {
    final db = await database;
    await db.delete('highlight_rules', where: 'id = ?', whereArgs: [id]);
  }

  // 高亮标签规则DAO
  Future<List<HighlightTagRule>> getHighlightTagRules() async {
    final db = await database;
    final maps = await db.query('highlight_tag_rules', orderBy: '"order" ASC');
    return maps.map((m) => HighlightTagRule.fromMap(m)).toList();
  }

  Future<void> insertHighlightTagRule(HighlightTagRule rule) async {
    final db = await database;
    await db.insert('highlight_tag_rules', rule.toMap());
  }

  Future<void> deleteHighlightTagRule(int id) async {
    final db = await database;
    await db.delete('highlight_tag_rules', where: 'id = ?', whereArgs: [id]);
  }

  // 云TTS DAO
  Future<List<CloudTtsEngine>> getCloudTtsEngines() async {
    final db = await database;
    final maps = await db.query('cloud_tts_engines');
    return maps.map((m) => CloudTtsEngine.fromMap(m)).toList();
  }

  Future<void> insertCloudTtsEngine(CloudTtsEngine engine) async {
    final db = await database;
    await db.insert('cloud_tts_engines', engine.toMap());
  }

  Future<void> updateCloudTtsEngine(CloudTtsEngine engine) async {
    final db = await database;
    if (engine.id != null) await db.update('cloud_tts_engines', engine.toMap(), where: 'id = ?', whereArgs: [engine.id]);
  }

  Future<void> deleteCloudTtsEngine(int id) async {
    final db = await database;
    await db.delete('cloud_tts_engines', where: 'id = ?', whereArgs: [id]);
  }

  // Cookie DAO
  Future<String?> getCookie(String url) async {
    final db = await database;
    final maps = await db.query('cookies', where: 'url = ?', whereArgs: [url]);
    return maps.isNotEmpty ? maps.first['cookie'].toString() : null;
  }

  Future<void> saveCookie(String url, String cookie) async {
    final db = await database;
    await db.insert('cookies', {'url': url, 'cookie': cookie, 'lastUpdateTime': DateTime.now().millisecondsSinceEpoch}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 删除指定 URL（精确）与同域的持久化 Cookie
  Future<void> deleteCookie(String url) async {
    final db = await database;
    String? host;
    try { host = Uri.parse(url).host; } catch (_) {}
    if (host != null && host.isNotEmpty) {
      await db.delete('cookies', where: 'url = ?', whereArgs: [url]);
      // 同域 cookie 一并清理（url 可能以域名/完整地址两种形式保存）
      final all = await db.query('cookies', columns: ['url']);
      for (final row in all) {
        final u = row['url']?.toString() ?? '';
        try {
          final h = Uri.parse(u).host;
          if (h == host || h.endsWith('.$host') || host.endsWith(h)) {
            await db.delete('cookies', where: 'url = ?', whereArgs: [u]);
          }
        } catch (_) {}
      }
    } else {
      await db.delete('cookies', where: 'url = ?', whereArgs: [url]);
    }
  }

  // 书籍知识DAO
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
  Future<String?> getTranslation(String source, String target, String original) async {
    final db = await database;
    final maps = await db.query('translation_caches', where: 'source = ? AND target = ? AND original = ?', whereArgs: [source, target, original]);
    return maps.isNotEmpty ? maps.first['translated'].toString() : null;
  }

  Future<void> saveTranslation(String source, String target, String original, String translated) async {
    final db = await database;
    await db.insert('translation_caches', {'source': source, 'target': target, 'original': original, 'translated': translated, 'saveTime': DateTime.now().millisecondsSinceEpoch});
  }

  // 键盘辅助DAO
  Future<List<KeyboardAssist>> getKeyboardAssists() async {
    final db = await database;
    final maps = await db.query('keyboard_assists', orderBy: '"order" ASC');
    return maps.map((m) => KeyboardAssist.fromMap(m)).toList();
  }

  Future<void> insertKeyboardAssist(KeyboardAssist assist) async {
    final db = await database;
    await db.insert('keyboard_assists', assist.toMap());
  }

  // HTTP TTS DAO
  Future<List<HttpTTS>> getHttpTTS() async {
    final db = await database;
    final maps = await db.query('http_tts');
    return maps.map((m) => HttpTTS.fromMap(m)).toList();
  }

  Future<void> insertHttpTTS(HttpTTS tts) async {
    final db = await database;
    await db.insert('http_tts', tts.toMap());
  }

  // RSS收藏DAO
  Future<List<RssStar>> getRssStars() async {
    final db = await database;
    final maps = await db.query('rss_stars', orderBy: 'starTime DESC');
    return maps.map((m) => RssStar.fromMap(m)).toList();
  }

  Future<void> insertRssStar(RssStar star) async {
    final db = await database;
    await db.insert('rss_stars', star.toMap());
  }

  Future<void> deleteRssStar(int id) async {
    final db = await database;
    await db.delete('rss_stars', where: 'id = ?', whereArgs: [id]);
  }

  // 服务器DAO
  Future<List<Server>> getServers() async {
    final db = await database;
    final maps = await db.query('servers');
    return maps.map((m) => Server.fromMap(m)).toList();
  }

  Future<void> insertServer(Server server) async {
    final db = await database;
    await db.insert('servers', server.toMap());
  }

  // 标签分组规则DAO
  Future<List<TagGroupRule>> getTagGroupRules() async {
    final db = await database;
    final maps = await db.query('tag_group_rules', orderBy: '"order" ASC');
    return maps.map((m) => TagGroupRule.fromMap(m)).toList();
  }

  Future<void> insertTagGroupRule(TagGroupRule rule) async {
    final db = await database;
    await db.insert('tag_group_rules', rule.toMap());
  }

  Future<void> updateTagGroupRule(TagGroupRule rule) async {
    final db = await database;
    if (rule.id != null) await db.update('tag_group_rules', rule.toMap(), where: 'id = ?', whereArgs: [rule.id]);
  }

  Future<void> deleteTagGroupRule(int id) async {
    final db = await database;
    await db.delete('tag_group_rules', where: 'id = ?', whereArgs: [id]);
  }

  // 阅读进度DAO
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
}
