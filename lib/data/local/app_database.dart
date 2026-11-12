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
import 'package:legado_md3/constant/book_group_virtual.dart';
part '../dao/book_dao.dart';
part '../dao/book_source_dao.dart';
part '../dao/book_group_dao.dart';
part '../dao/bookmark_replace_dao.dart';
part '../dao/rss_dao.dart';
part '../dao/read_record_cache_dao.dart';
part '../dao/rule_tts_cookie_dao.dart';
part '../dao/knowledge_history_dao.dart';
part '../dao/misc_rules_dao.dart';
part '../dao/progress_homepage_dao.dart';
part '../dao/auto_task_dao.dart';
part '../dao/v14_local_dao.dart';
part '../dao/v14_search_dao.dart';
part '../dao/v14_content_dao.dart';
part '../dao/v14_media_dao.dart';
part '../dao/maintenance_dao.dart';


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
  /// Book / BookChapter 实体，只保留模型真实读写的列。
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

  /// v14：新增 10 张表，
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
    // onOpen 在 onCreate/onUpgrade 之后、每次开库都会调用（对齐
    // 数据库打开回调，用于幂等补插虚拟分组与脏数据修复。
    return openDatabase(
      fullPath,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: _onOpen,
    );
  }

  /// 每次开库执行：
  /// 1) 7 个内置虚拟分组 `where not exists` 幂等补插；
  /// 2) 开库脏数据修复 SQL（loginUi='null' 转 NULL、concurrentRate 空值补 0）。
  /// 全部 try/catch：旧库缺 groupId/enableRefresh 列时不影响开库。
  /// 无法等价实现的部分（httpTTS.loginUi / keyboardAssists 默认数据）
  /// 已在 VirtualBookGroup.buildRepairSqls 注释中显式标注并跳过。
  Future<void> _onOpen(Database db) async {
    for (final sql in VirtualBookGroup.buildInsertSqls()) {
      try {
        await db.execute(sql);
      } catch (_) {}
    }
    for (final sql in VirtualBookGroup.buildRepairSqls()) {
      try {
        await db.execute(sql);
      } catch (_) {}
    }
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
      // v12：books 补长章节拆分开关列（ Book.ReadConfig.splitLongChapter，
      // 仅本地 TXT 有意义；旧数据默认 1=开启）。逐列 ADD 可重入。
      await _addColumnsIfMissing(db, 'books', const [
        'splitLongChapter INTEGER DEFAULT 1',
      ]);
    }
    if (oldVersion < 13) {
      // v13：rule_subs 补自动更新字段。
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
    await db.execute('CREATE TABLE IF NOT EXISTS replace_rules (id INTEGER PRIMARY KEY AUTOINCREMENT, replaceSummary TEXT, replaceRule TEXT, replacement TEXT, enable INTEGER DEFAULT 1, isTitle INTEGER DEFAULT 0, isContent INTEGER DEFAULT 1, isRegex INTEGER DEFAULT 1, scope TEXT, order_num INTEGER, "order" INTEGER, excludeScope TEXT, group_name TEXT, timeoutMillisecond INTEGER DEFAULT 3000, sortOrder INTEGER)');
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
    // 细节轮： ReplaceRule 实体，补齐排除范围/分组/超时/排序字段。
    // _onUpgrade 末尾会复用 _onCreate，因此新装与升级路径都会执行，且幂等。
    await _addColumnsIfMissing(db, 'replace_rules', const [
      'excludeScope TEXT',
      'group_name TEXT',
      'timeoutMillisecond INTEGER DEFAULT 3000',
      'sortOrder INTEGER',
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
}
