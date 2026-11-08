import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_chapter.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/data/model/db_models.dart';
import 'package:legado_md3/data/model/bookmark.dart';
import 'package:legado_md3/data/model/read_record.dart';
import '../model/replace_rule.dart' hide ReadRecord;
import 'package:legado_md3/data/model/rss_source.dart';
import 'package:legado_md3/data/model/rss_article.dart';
import 'package:legado_md3/data/model/txt_toc_rule.dart';
import 'package:legado_md3/data/model/homepage_module.dart';
import 'package:legado_md3/data/model/auto_task.dart';
import 'package:legado_md3/data/model/rss_read_record.dart';
import 'package:legado_md3/data/model/book_memo.dart';
import 'package:legado_md3/data/model/book_highlight.dart';
import 'package:legado_md3/data/model/download_task.dart';
import 'package:legado_md3/data/model/v14_models.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _db;
  // v13：定时任务 / RSS 阅读记录 / 书籍备忘 / 划线高亮 / 下载队列，
  // 并为 rule_subs 增加自动更新字段。_onUpgrade 末尾统一调用 _onCreate，
  // 因此新表用 CREATE TABLE IF NOT EXISTS 即可同时覆盖新装与升级。
  static const int _dbVersion = 14;

  /// 全新安装的建表语句（公开，供生产与回归测试共用同一份 SQL，避免两边漂移）。
  /// 列集合必须与 Book.toMap / BookChapter.toMap 写入的键完全一致，否则
  /// 新用户首次写库会抛 "table X has no column named Y"。
  /// 对齐 legado-E 的 Book / BookChapter 实体，只保留模型真实读写的列。
  static const String booksTableSql =
      'CREATE TABLE IF NOT EXISTS books (name TEXT NOT NULL, author TEXT NOT NULL, '
      'coverUrl TEXT, intro TEXT, kind TEXT, lastChapter TEXT, lastChapterIndex INTEGER, '
      'durChapterIndex INTEGER, durChapterPos INTEGER, durChapterTime INTEGER, noteUrl TEXT, '
      'bookUrl TEXT, origin TEXT, originName TEXT, tag TEXT, wordCount INTEGER, '
      'canUpdate INTEGER DEFAULT 1, local INTEGER DEFAULT 0, type INTEGER DEFAULT 0, '
      'group_name TEXT, order_num INTEGER, latestChapterTime INTEGER, lastCheckTime INTEGER, '
      'infoHtml TEXT, tocHtml TEXT, variable TEXT, customOrder INTEGER, '
      'allowUpdate INTEGER DEFAULT 1, fileName TEXT, customCoverUrl TEXT, bookComment TEXT, '
      'splitLongChapter INTEGER DEFAULT 1, readConfig TEXT, '
      'PRIMARY KEY (name, author))';

  /// 与 v7 重建表、v9 迁移、BookChapter.toMap/fromMap 完全对齐：
  /// isVip / update_time 必填，否则全新安装时 insertChapters 会因缺列抛异常。
  static const String bookChaptersTableSql =
      'CREATE TABLE IF NOT EXISTS book_chapters (bookName TEXT NOT NULL, '
      'bookAuthor TEXT NOT NULL, chapter_index INTEGER NOT NULL, title TEXT, url TEXT, '
      'baseUrl TEXT, isVolume INTEGER DEFAULT 0, isVip INTEGER DEFAULT 0, '
      'isPay INTEGER DEFAULT 0, update_time TEXT, tag TEXT, resourceUrl TEXT, '
      'content TEXT, start_pos INTEGER, end_pos INTEGER, variable TEXT, '
      'startFragmentId TEXT, endFragmentId TEXT, imgUrl TEXT, titleMD5 TEXT, '
      'PRIMARY KEY (bookName, bookAuthor, chapter_index))';

  /// v13 新增 5 张表的建表 SQL（生产与回归测试共用，避免列集合漂移）。
  /// 对齐官方原版 AutoTask / RssReadRecord / BookMemo / BookHighlight / Download。
  static const List<String> v13TableSqls = [
    'CREATE TABLE IF NOT EXISTS auto_tasks (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, action TEXT, jsCode TEXT, hour INTEGER DEFAULT 8, minute INTEGER DEFAULT 0, intervalMinutes INTEGER DEFAULT 0, enabled INTEGER DEFAULT 1, lastRunTime INTEGER, note TEXT, customOrder INTEGER DEFAULT 0)',
    'CREATE TABLE IF NOT EXISTS rss_read_records (id INTEGER PRIMARY KEY AUTOINCREMENT, link TEXT UNIQUE, title TEXT, sourceUrl TEXT, durPos REAL DEFAULT 0, readTime INTEGER, enabled INTEGER DEFAULT 1)',
    'CREATE TABLE IF NOT EXISTS book_memos (id INTEGER PRIMARY KEY AUTOINCREMENT, bookName TEXT, author TEXT, chapterIndex INTEGER DEFAULT 0, chapterTitle TEXT, content TEXT, createTime INTEGER, updateTime INTEGER)',
    'CREATE TABLE IF NOT EXISTS book_highlights (id INTEGER PRIMARY KEY AUTOINCREMENT, bookName TEXT, author TEXT, chapterIndex INTEGER DEFAULT 0, chapterTitle TEXT, content TEXT, start INTEGER DEFAULT 0, end INTEGER DEFAULT 0, color INTEGER DEFAULT 0, note TEXT, createTime INTEGER)',
    'CREATE TABLE IF NOT EXISTS download_tasks (id INTEGER PRIMARY KEY AUTOINCREMENT, bookName TEXT, author TEXT, startIndex INTEGER DEFAULT 0, endIndex INTEGER DEFAULT -1, currentIndex INTEGER DEFAULT 0, total INTEGER DEFAULT 0, done INTEGER DEFAULT 0, status INTEGER DEFAULT 0, error TEXT, createTime INTEGER)',
  ];

  /// v14（第十轮，对齐 Luoyacheng/legado-E 阅读Sigma）：新增 10 张表，
  /// 覆盖 SearchBook 换源检索缓存 / 书源检测状态 / PDF 大纲 / 页数估算 /
  /// 通用 KV 缓存 / 段评 / 多套排版预设 / 弹幕缓存 / BGM / AI Agent 工具。
  /// 全部 IF NOT EXISTS，生产与回归测试共用（避免列集合漂移）。
  static const List<String> v14TableSqls = [
    'CREATE TABLE IF NOT EXISTS search_books (bookUrl TEXT PRIMARY KEY, name TEXT, author TEXT, origin TEXT, originName TEXT, type INTEGER DEFAULT 8, coverUrl TEXT, intro TEXT, latestChapterTitle TEXT, tocUrl TEXT, time INTEGER, originOrder INTEGER DEFAULT 0, chapterWordCountText TEXT, chapterWordCount INTEGER DEFAULT -1, respondTime INTEGER DEFAULT -1)',
    'CREATE INDEX IF NOT EXISTS idx_search_books_name_author ON search_books(name, author)',
    'CREATE TABLE IF NOT EXISTS book_source_check_states (id INTEGER PRIMARY KEY AUTOINCREMENT, origin TEXT UNIQUE, name TEXT, state INTEGER DEFAULT 0, respondTime INTEGER DEFAULT -1, errorMsg TEXT, checkTime INTEGER)',
    'CREATE TABLE IF NOT EXISTS pdf_outlines (id INTEGER PRIMARY KEY AUTOINCREMENT, bookName TEXT, author TEXT, title TEXT, level INTEGER DEFAULT 0, page INTEGER DEFAULT 0, sortOrder INTEGER DEFAULT 0)',
    'CREATE TABLE IF NOT EXISTS page_estimates (id INTEGER PRIMARY KEY AUTOINCREMENT, bookName TEXT, author TEXT, chapterIndex INTEGER, pageCount INTEGER DEFAULT -1, mode INTEGER DEFAULT 0, updateTime INTEGER, UNIQUE(bookName, author, chapterIndex))',
    'CREATE TABLE IF NOT EXISTS kv_caches (key TEXT PRIMARY KEY, value TEXT, deadline INTEGER DEFAULT 0)',
    'CREATE TABLE IF NOT EXISTS book_reviews (id INTEGER PRIMARY KEY AUTOINCREMENT, bookName TEXT, author TEXT, chapterIndex INTEGER, paragraphIndex INTEGER, content TEXT, userName TEXT, likes INTEGER DEFAULT 0, createTime INTEGER)',
    'CREATE TABLE IF NOT EXISTS read_presets (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, config TEXT, isDefault INTEGER DEFAULT 0, createTime INTEGER)',
    'CREATE TABLE IF NOT EXISTS danmaku_caches (id INTEGER PRIMARY KEY AUTOINCREMENT, bookUrl TEXT, chapterUrl TEXT, filePath TEXT, count INTEGER DEFAULT 0, updateTime INTEGER, UNIQUE(bookUrl, chapterUrl))',
    'CREATE TABLE IF NOT EXISTS bgm_tracks (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, artist TEXT, url TEXT, coverUrl TEXT, source TEXT, duration INTEGER DEFAULT 0, customOrder INTEGER DEFAULT 0)',
    'CREATE TABLE IF NOT EXISTS ai_agent_tools (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, description TEXT, schema TEXT, handler TEXT, enabled INTEGER DEFAULT 1)',
  ];

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
      await db.execute('CREATE TABLE IF NOT EXISTS book_chapters (bookName TEXT NOT NULL, bookAuthor TEXT NOT NULL, chapter_index INTEGER NOT NULL, title TEXT, url TEXT, baseUrl TEXT, isVolume INTEGER DEFAULT 0, isVip INTEGER DEFAULT 0, isPay INTEGER DEFAULT 0, update_time TEXT, tag TEXT, resourceUrl TEXT, content TEXT, start_pos INTEGER, end_pos INTEGER, variable TEXT, PRIMARY KEY (bookName, bookAuthor, chapter_index))');
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
    if (oldVersion < 9) {
      // v9：book_chapters 补充 isVip / update_time 列
      await _addColumnsIfMissing(db, 'book_chapters', const [
        'isVip INTEGER DEFAULT 0',
        'update_time TEXT',
      ]);
    }
    if (oldVersion < 10) {
      // v10：rss_sources 补运行时字段列（articleStyle/enableJs/loadWithBaseUrl/preload/
      // singleUrl/cacheFirst/redirectPolicy/type），与 RssSource.toMap/fromMap 对齐，
      // 否则旧库写入会抛 "table rss_sources has no column named X"。逐列 ADD 可重入。
      await _addColumnsIfMissing(db, 'rss_sources', const [
        'articleStyle INTEGER',
        'enableJs INTEGER DEFAULT 0',
        'loadWithBaseUrl INTEGER DEFAULT 0',
        'preload INTEGER DEFAULT 0',
        'singleUrl INTEGER DEFAULT 0',
        'cacheFirst INTEGER DEFAULT 0',
        'redirectPolicy TEXT',
        'type INTEGER DEFAULT 0',
      ]);
    }
    if (oldVersion < 11) {
      // v11：book_sources 补 @put:/@get: 变量规则列。BookSource.toMap 会带上
      // 这两个字段，旧库不补列会在保存书源时抛 "has no column named rulePut"。
      await _addColumnsIfMissing(db, 'book_sources', const [
        'rulePut TEXT',
        'ruleGet TEXT',
      ]);
    }
    if (oldVersion < 12) {
      // v12：books 补长章节拆分开关列（对齐 E Book.ReadConfig.splitLongChapter，
      // 仅本地 TXT 有意义；旧数据默认 1=开启）。逐列 ADD 可重入。
      await _addColumnsIfMissing(db, 'books', const [
        'splitLongChapter INTEGER DEFAULT 1',
      ]);
    }
    if (oldVersion < 13) {
      // v13：rule_subs 补自动更新字段（对齐 E ruleSubsUp() 启动期自动更新订阅）。
      await _addColumnsIfMissing(db, 'rule_subs', const [
        'autoUpdate INTEGER DEFAULT 0',
        'updateInterval INTEGER DEFAULT 0',
      ]);
      // 其余 5 张新表在末尾 _onCreate 里以 CREATE TABLE IF NOT EXISTS 建立。
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
    await db.execute(booksTableSql);
    await db.execute(bookChaptersTableSql);
    await db.execute('CREATE TABLE IF NOT EXISTS book_sources (bookSourceUrl TEXT PRIMARY KEY, bookSourceName TEXT, bookSourceGroup TEXT, bookSourceType INTEGER, bookSourceComment TEXT, lastUpdateTime INTEGER, enabled INTEGER DEFAULT 1, enabledExplore INTEGER DEFAULT 1, customOrder INTEGER, respondTime INTEGER, weight INTEGER, header TEXT, loginUrl TEXT, loginUi TEXT, loginCheckJs TEXT, bookUrlPattern TEXT, charset TEXT, coverDecodeJs TEXT, eventListener INTEGER DEFAULT 0, customButton INTEGER DEFAULT 0, enabledCookieJar INTEGER DEFAULT 0, concurrentRate TEXT, homepageModules TEXT, searchUrl TEXT, checkKeyWord TEXT, exploreUrl TEXT, exploreScreen TEXT, ruleSearch TEXT, ruleExplore TEXT, ruleBookInfo TEXT, ruleToc TEXT, ruleContent TEXT, ruleReview TEXT, ruleImage TEXT, variableComment TEXT, jsLib TEXT, variable TEXT, rulePut TEXT, ruleGet TEXT)');
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
    await db.execute('CREATE TABLE IF NOT EXISTS rss_sources (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, url TEXT, sourceIcon TEXT, group_name TEXT, sourceComment TEXT, searchUrl TEXT, sortUrl TEXT, loginUrl TEXT, loginUi TEXT, loginCheckJs TEXT, coverDecodeJs TEXT, header TEXT, variableComment TEXT, concurrentRate TEXT, jsLib TEXT, startHtml TEXT, startStyle TEXT, startJs TEXT, preloadJs TEXT, ruleArticles TEXT, ruleNextPage TEXT, ruleTitle TEXT, rulePubDate TEXT, ruleDescription TEXT, ruleImage TEXT, ruleLink TEXT, ruleContent TEXT, style TEXT, injectJs TEXT, contentWhitelist TEXT, contentBlacklist TEXT, shouldOverrideUrlLoading TEXT, enabled INTEGER DEFAULT 1, customOrder INTEGER, lastUpdateTime INTEGER, unreadCount INTEGER DEFAULT 0, variable TEXT, enabledCookieJar INTEGER DEFAULT 0, articleStyle INTEGER, enableJs INTEGER DEFAULT 0, loadWithBaseUrl INTEGER DEFAULT 0, preload INTEGER DEFAULT 0, singleUrl INTEGER DEFAULT 0, cacheFirst INTEGER DEFAULT 0, redirectPolicy TEXT, type INTEGER DEFAULT 0, "group" TEXT, icon TEXT, description TEXT)');
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
    // v13 新表（对齐官方原版 AutoTask / RssReadRecord / BookMemo /
    // BookHighlight / Download）。全部 IF NOT EXISTS，升级路径复用。
    // SQL 抽为公开常量：生产与回归测试共用同一份，避免列集合漂移。
    for (final sql in v13TableSqls) {
      await db.execute(sql);
    }
    // rule_subs 的自动更新列（新装即带，升级走上面 v13 的 _addColumnsIfMissing）。
    await _addColumnsIfMissing(db, 'rule_subs', const [
      'autoUpdate INTEGER DEFAULT 0',
      'updateInterval INTEGER DEFAULT 0',
    ]);
    // v14（第十轮）：新表 + 已有表补列。全部幂等，升级路径同样会走到这里
    // （_onUpgrade 末尾调用 _onCreate），因此无需在迁移段重复。
    for (final sql in v14TableSqls) {
      await db.execute(sql);
    }
    await _addColumnsIfMissing(db, 'books', const [
      'readConfig TEXT',
    ]);
    await _addColumnsIfMissing(db, 'book_chapters', const [
      'startFragmentId TEXT', 'endFragmentId TEXT', 'imgUrl TEXT', 'titleMD5 TEXT',
    ]);
    await _addColumnsIfMissing(db, 'read_records', const [
      'deviceId TEXT', 'readTime INTEGER', 'lastRead INTEGER',
    ]);
    await _addColumnsIfMissing(db, 'book_groups', const [
      'groupId INTEGER', 'coverStyle INTEGER', 'enableRefresh INTEGER DEFAULT 1',
    ]);
    await _addColumnsIfMissing(db, 'rule_subs', const [
      'silentUpdate INTEGER DEFAULT 0', 'js TEXT', 'showRule TEXT', 'sourceUrl TEXT',
    ]);
    await _addColumnsIfMissing(db, 'replace_rules', const [
      'useTo TEXT', 'scopeTitle INTEGER DEFAULT 0', 'scopeContent INTEGER DEFAULT 1',
    ]);
    await _addColumnsIfMissing(db, 'txt_toc_rules', const [
      'replacement TEXT',
    ]);
    await _addColumnsIfMissing(db, 'book_sources', const [
      'payAction TEXT', 'downloadUrls TEXT',
    ]);
    await _addColumnsIfMissing(db, 'book_progress', const [
      'deviceId TEXT', 'syncedTime INTEGER', 'durChapterTitle TEXT',
    ]);
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

  /// 清理超过 [days] 天未更新书籍的章节正文缓存（oc_autoClearExpired），返回清理章节数
  Future<int> clearExpiredChapterContent({int days = 30}) async {
    final db = await database;
    final cutoff = DateTime.now().millisecondsSinceEpoch - days * 24 * 3600 * 1000;
    final books = await db.query('books',
        columns: ['name', 'author'],
        where: 'lastCheckTime IS NULL OR lastCheckTime < ?',
        whereArgs: [cutoff]);
    var count = 0;
    for (final b in books) {
      final name = b['name'] as String;
      final author = b['author'] as String;
      count += await db.update('book_chapters', {'content': null},
          where: 'bookName = ? AND bookAuthor = ?', whereArgs: [name, author]);
    }
    return count;
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

  /// 更新词典规则（编辑名称/地址/规则/启停/排序后保存）
  Future<void> updateDictRule(DictRule rule) async {
    if (rule.id == null) return insertDictRule(rule);
    final db = await database;
    await db.update(
      'dict_rules',
      rule.toMap(),
      where: 'id = ?',
      whereArgs: [rule.id],
    );
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

  /// 更新自定义 HTTP TTS 引擎（编辑页与「自定义 HTTP TTS」分区共用）。
  Future<void> updateHttpTTS(HttpTTS tts) async {
    if (tts.id == null) return;
    final db = await database;
    final values = tts.toMap()..remove('id');
    await db.update('http_tts', values, where: 'id = ?', whereArgs: [tts.id]);
  }

  /// 删除自定义 HTTP TTS 引擎。
  Future<void> deleteHttpTTS(int id) async {
    final db = await database;
    await db.delete('http_tts', where: 'id = ?', whereArgs: [id]);
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

  /* ===== v13：定时任务 / RSS 阅读记录 / 备忘 / 划线 / 下载队列 DAO ===== */

  // 定时任务
  Future<List<AutoTask>> getAutoTasks() async {
    final db = await database;
    final maps = await db.query('auto_tasks', orderBy: 'customOrder ASC, id ASC');
    return maps.map(AutoTask.fromMap).toList();
  }

  Future<int> insertAutoTask(AutoTask t) async {
    final db = await database;
    return db.insert('auto_tasks', t.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateAutoTask(AutoTask t) async {
    final db = await database;
    if (t.id != null) {
      await db.update('auto_tasks', t.toMap(), where: 'id = ?', whereArgs: [t.id]);
    }
  }

  Future<void> deleteAutoTask(int id) async {
    final db = await database;
    await db.delete('auto_tasks', where: 'id = ?', whereArgs: [id]);
  }

  // RSS 阅读记录（续读）
  Future<RssReadRecord?> getRssReadRecord(String link) async {
    final db = await database;
    final maps = await db.query('rss_read_records', where: 'link = ?', whereArgs: [link], limit: 1);
    return maps.isEmpty ? null : RssReadRecord.fromMap(maps.first);
  }

  Future<List<RssReadRecord>> getRssReadRecords({int limit = 200}) async {
    final db = await database;
    final maps = await db.query('rss_read_records', orderBy: 'readTime DESC', limit: limit);
    return maps.map(RssReadRecord.fromMap).toList();
  }

  Future<void> upsertRssReadRecord(RssReadRecord r) async {
    final db = await database;
    await db.insert('rss_read_records', r.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> toggleRssReadRecordEnabled(String link, int enabled) async {
    final db = await database;
    await db.update('rss_read_records', {'enabled': enabled}, where: 'link = ?', whereArgs: [link]);
  }

  Future<void> clearRssReadRecords() async {
    final db = await database;
    await db.delete('rss_read_records');
  }

  // 书籍备忘
  Future<List<BookMemo>> getBookMemos(String bookName, String author, {int? chapterIndex}) async {
    final db = await database;
    final maps = await db.query('book_memos',
        where: chapterIndex == null
            ? 'bookName = ? AND author = ?'
            : 'bookName = ? AND author = ? AND chapterIndex = ?',
        whereArgs: chapterIndex == null
            ? [bookName, author]
            : [bookName, author, chapterIndex],
        orderBy: 'updateTime DESC');
    return maps.map(BookMemo.fromMap).toList();
  }

  Future<int> upsertBookMemo(BookMemo m) async {
    final db = await database;
    return db.insert('book_memos', m.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteBookMemo(int id) async {
    final db = await database;
    await db.delete('book_memos', where: 'id = ?', whereArgs: [id]);
  }

  // 划线 / 高亮
  Future<List<BookHighlight>> getBookHighlights(String bookName, String author) async {
    final db = await database;
    final maps = await db.query('book_highlights',
        where: 'bookName = ? AND author = ?',
        whereArgs: [bookName, author],
        orderBy: 'chapterIndex ASC, start ASC');
    return maps.map(BookHighlight.fromMap).toList();
  }

  Future<int> insertBookHighlight(BookHighlight h) async {
    final db = await database;
    return db.insert('book_highlights', h.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteBookHighlight(int id) async {
    final db = await database;
    await db.delete('book_highlights', where: 'id = ?', whereArgs: [id]);
  }

  // 下载队列
  Future<List<DownloadTask>> getDownloadTasks() async {
    final db = await database;
    final maps = await db.query('download_tasks', orderBy: 'createTime DESC');
    return maps.map(DownloadTask.fromMap).toList();
  }

  Future<int> upsertDownloadTask(DownloadTask t) async {
    final db = await database;
    return db.insert('download_tasks', t.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteDownloadTask(int id) async {
    final db = await database;
    await db.delete('download_tasks', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearFinishedDownloadTasks() async {
    final db = await database;
    await db.delete('download_tasks', where: 'status = ?', whereArgs: [2]);
  }

  // 规则订阅自动更新开关
  Future<void> setRuleSubAutoUpdate(int id, int autoUpdate, int updateInterval) async {
    final db = await database;
    await db.update('rule_subs',
        {'autoUpdate': autoUpdate, 'updateInterval': updateInterval},
        where: 'id = ?', whereArgs: [id]);
  }

  // ==================== v14 DAO（第十轮 / 阅读Sigma 对齐） ====================

  // --- SearchBook 跨源换源检索缓存 ---
  Future<List<SearchBookTable>> getSearchBooks({String? name, String? author, String? origin}) async {
    final db = await database;
    String? where;
    List<Object?> args = [];
    if (name != null && author != null) {
      where = 'name = ? AND author = ?';
      args = [name, author];
    } else if (origin != null) {
      where = 'origin = ?';
      args = [origin];
    }
    final maps = await db.query('search_books', where: where, whereArgs: args,
        orderBy: 'originOrder ASC, time DESC');
    return maps.map(SearchBookTable.fromMap).toList();
  }

  Future<SearchBookTable?> getFirstSearchBook(String name, String author) async {
    final list = await getSearchBooks(name: name, author: author);
    return list.isEmpty ? null : list.first;
  }

  Future<void> insertSearchBook(SearchBookTable s) async {
    final db = await database;
    await db.insert('search_books', s.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> insertSearchBooks(List<SearchBookTable> list) async {
    final db = await database;
    final batch = db.batch();
    for (final s in list) {
      batch.insert('search_books', s.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> clearSearchBooks({int? beforeTime}) async {
    final db = await database;
    await db.delete('search_books',
        where: beforeTime == null ? null : 'time < ?',
        whereArgs: beforeTime == null ? null : [beforeTime]);
  }

  // --- 书源检测状态 ---
  Future<List<BookSourceCheckState>> getBookSourceCheckStates() async {
    final db = await database;
    final maps = await db.query('book_source_check_states', orderBy: 'checkTime DESC');
    return maps.map(BookSourceCheckState.fromMap).toList();
  }

  Future<BookSourceCheckState?> getBookSourceCheckState(String origin) async {
    final db = await database;
    final maps = await db.query('book_source_check_states',
        where: 'origin = ?', whereArgs: [origin], limit: 1);
    return maps.isEmpty ? null : BookSourceCheckState.fromMap(maps.first);
  }

  Future<void> upsertBookSourceCheckState(BookSourceCheckState s) async {
    final db = await database;
    await db.insert('book_source_check_states', s.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearBookSourceCheckStates() async {
    final db = await database;
    await db.delete('book_source_check_states');
  }

  // --- PDF 大纲 ---
  Future<List<PdfOutline>> getPdfOutlines(String bookName, String author) async {
    final db = await database;
    final maps = await db.query('pdf_outlines',
        where: 'bookName = ? AND author = ?', whereArgs: [bookName, author],
        orderBy: 'sortOrder ASC');
    return maps.map(PdfOutline.fromMap).toList();
  }

  Future<void> replacePdfOutlines(String bookName, String author, List<PdfOutline> list) async {
    final db = await database;
    await db.delete('pdf_outlines',
        where: 'bookName = ? AND author = ?', whereArgs: [bookName, author]);
    final batch = db.batch();
    for (final o in list) {
      batch.insert('pdf_outlines', o.toMap());
    }
    await batch.commit(noResult: true);
  }

  // --- 页数估算 / 全书索引 ---
  Future<List<PageEstimate>> getPageEstimates(String bookName, String author) async {
    final db = await database;
    final maps = await db.query('page_estimates',
        where: 'bookName = ? AND author = ?', whereArgs: [bookName, author],
        orderBy: 'chapterIndex ASC');
    return maps.map(PageEstimate.fromMap).toList();
  }

  Future<void> upsertPageEstimate(PageEstimate e) async {
    final db = await database;
    await db.insert('page_estimates', e.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearPageEstimates(String bookName, String author) async {
    final db = await database;
    await db.delete('page_estimates',
        where: 'bookName = ? AND author = ?', whereArgs: [bookName, author]);
  }

  // --- 通用 KV 缓存 ---
  Future<String?> getKvCache(String key) async {
    final db = await database;
    final maps = await db.query('kv_caches', where: 'key = ?', whereArgs: [key], limit: 1);
    if (maps.isEmpty) return null;
    final c = KvCache.fromMap(maps.first);
    if (c.expired) {
      await db.delete('kv_caches', where: 'key = ?', whereArgs: [key]);
      return null;
    }
    return c.value;
  }

  Future<void> setKvCache(String key, String? value, {Duration? ttl}) async {
    final db = await database;
    final deadline = ttl == null
        ? 0
        : DateTime.now().millisecondsSinceEpoch + ttl.inMilliseconds;
    await db.insert('kv_caches', KvCache(key: key, value: value, deadline: deadline).toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearExpiredKvCaches() async {
    final db = await database;
    await db.delete('kv_caches',
        where: 'deadline > 0 AND deadline < ?',
        whereArgs: [DateTime.now().millisecondsSinceEpoch]);
  }

  // --- 段评 ---
  Future<List<BookReview>> getBookReviews(String bookName, String author, int chapterIndex) async {
    final db = await database;
    final maps = await db.query('book_reviews',
        where: 'bookName = ? AND author = ? AND chapterIndex = ?',
        whereArgs: [bookName, author, chapterIndex], orderBy: 'paragraphIndex ASC, likes DESC');
    return maps.map(BookReview.fromMap).toList();
  }

  Future<void> insertBookReview(BookReview r) async {
    final db = await database;
    await db.insert('book_reviews', r.toMap());
  }

  Future<void> likeBookReview(int id) async {
    final db = await database;
    await db.rawUpdate('UPDATE book_reviews SET likes = likes + 1 WHERE id = ?', [id]);
  }

  // --- 多套排版预设 ---
  Future<List<ReadPreset>> getReadPresets() async {
    final db = await database;
    final maps = await db.query('read_presets', orderBy: 'createTime ASC');
    return maps.map(ReadPreset.fromMap).toList();
  }

  Future<int> insertReadPreset(ReadPreset p) async {
    final db = await database;
    return db.insert('read_presets', p.toMap());
  }

  Future<void> deleteReadPreset(int id) async {
    final db = await database;
    await db.delete('read_presets', where: 'id = ?', whereArgs: [id]);
  }

  // --- 弹幕缓存索引 ---
  Future<DanmakuCache?> getDanmakuCache(String bookUrl, String chapterUrl) async {
    final db = await database;
    final maps = await db.query('danmaku_caches',
        where: 'bookUrl = ? AND chapterUrl = ?', whereArgs: [bookUrl, chapterUrl], limit: 1);
    return maps.isEmpty ? null : DanmakuCache.fromMap(maps.first);
  }

  Future<void> upsertDanmakuCache(DanmakuCache c) async {
    final db = await database;
    await db.insert('danmaku_caches', c.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearDanmakuCaches({String? bookUrl}) async {
    final db = await database;
    await db.delete('danmaku_caches',
        where: bookUrl == null ? null : 'bookUrl = ?',
        whereArgs: bookUrl == null ? null : [bookUrl]);
  }

  // --- BGM 曲目 ---
  Future<List<BgmTrack>> getBgmTracks() async {
    final db = await database;
    final maps = await db.query('bgm_tracks', orderBy: 'customOrder ASC, id ASC');
    return maps.map(BgmTrack.fromMap).toList();
  }

  Future<int> insertBgmTrack(BgmTrack t) async {
    final db = await database;
    return db.insert('bgm_tracks', t.toMap());
  }

  Future<void> deleteBgmTrack(int id) async {
    final db = await database;
    await db.delete('bgm_tracks', where: 'id = ?', whereArgs: [id]);
  }

  // --- AI Agent 工具 ---
  Future<List<AiAgentTool>> getAiAgentTools({bool onlyEnabled = false}) async {
    final db = await database;
    final maps = await db.query('ai_agent_tools',
        where: onlyEnabled ? 'enabled = 1' : null, orderBy: 'id ASC');
    return maps.map(AiAgentTool.fromMap).toList();
  }

  Future<void> upsertAiAgentTool(AiAgentTool t) async {
    final db = await database;
    await db.insert('ai_agent_tools', t.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteAiAgentTool(int id) async {
    final db = await database;
    await db.delete('ai_agent_tools', where: 'id = ?', whereArgs: [id]);
  }

  // --- 每书级阅读配置（books.readConfig 列，存 JSON） ---
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
