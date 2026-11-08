import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/v14_models.dart';

/// 第十轮（v14，对齐 Luoyacheng/legado-E 阅读Sigma）回归测试：
/// - 10 张新表在「全新安装」路径下建成（直接执行生产常量 v14TableSqls，零漂移）；
/// - 主要模型 toMap/fromMap 往返保真；
/// - 关键调用链用源码契约锁定（原生通道 / Bootstrap 接线 / WebSocket /
///   EPUB 分流 / 归档解码注册 / 首页 Feed 容错 / 阅读页新菜单）。
void main() {
  String read(String p) => File(p).readAsStringSync();

  group('v14 建表与 DAO', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    Future<Database> onCreateDb() async {
      final db = await databaseFactory.openDatabase(':memory:');
      // 生产常量，测试与源码零漂移
      for (final sql in DatabaseService.v14TableSqls) {
        await db.execute(sql);
      }
      return db;
    }

    test('10 张新表 + 索引都在 onCreate 建成', () async {
      final db = await onCreateDb();
      addTearDown(() => db.close());
      final rows = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type IN ('table','index') AND name IN "
          "('search_books','idx_search_books_name_author','book_source_check_states',"
          "'pdf_outlines','page_estimates','kv_caches','book_reviews',"
          "'read_presets','danmaku_caches','bgm_tracks','ai_agent_tools')");
      final names = rows.map((r) => r['name'] as String).toSet();
      for (final t in [
        'search_books', 'idx_search_books_name_author',
        'book_source_check_states', 'pdf_outlines', 'page_estimates',
        'kv_caches', 'book_reviews', 'read_presets', 'danmaku_caches',
        'bgm_tracks', 'ai_agent_tools',
      ]) {
        expect(names, contains(t), reason: '缺表/索引：$t');
      }
    });

    test('v14 表列集合覆盖各模型 toMap 全部键', () async {
      final db = await onCreateDb();
      addTearDown(() => db.close());
      final cases = <String, Map<String, dynamic>>{
        'search_books': SearchBookTable(bookUrl: 'u', origin: 'o').toMap(),
        'book_source_check_states':
            BookSourceCheckState(origin: 'o').toMap(),
        'pdf_outlines': PdfOutline(bookName: 'b', title: 't').toMap(),
        'page_estimates':
            PageEstimate(bookName: 'b', chapterIndex: 0).toMap(),
        'kv_caches': KvCache(key: 'k').toMap(),
        'book_reviews': BookReview(
            bookName: 'b', chapterIndex: 0, paragraphIndex: 0).toMap(),
        'read_presets': ReadPreset(name: 'n', config: '{}').toMap(),
        'danmaku_caches': DanmakuCache(
            bookUrl: 'b', chapterUrl: 'c', filePath: 'f').toMap(),
        'bgm_tracks': BgmTrack(title: 't', url: 'u').toMap(),
        'ai_agent_tools':
            const AiAgentTool(name: 'n', handler: 'h').toMap(),
      };
      for (final entry in cases.entries) {
        final cols = await db.rawQuery('PRAGMA table_info(${entry.key})');
        final colNames = cols.map((c) => c['name'] as String).toSet();
        for (final key in entry.value.keys) {
          expect(colNames, contains(key),
              reason: '${entry.key} 缺列 $key（模型 toMap 会写入）');
        }
      }
    });

    test('模型往返保真', () {
      final s = SearchBookTable.fromMap(SearchBookTable(
          bookUrl: 'u', name: '书名', author: '作者', origin: 'o',
          type: 8, respondTime: 123).toMap());
      expect(s.name, '书名');
      expect(s.author, '作者');
      expect(s.respondTime, 123);

      final o = PdfOutline.fromMap(
          PdfOutline(bookName: 'b', title: '第一章', level: 2, page: 7, order: 3)
              .toMap());
      expect(o.title, '第一章');
      expect(o.page, 7);
      expect(o.order, 3);

      final r = BookReview.fromMap(BookReview(
          bookName: 'b', chapterIndex: 1, paragraphIndex: 2,
          content: '好', likes: 9).toMap());
      expect(r.content, '好');
      expect(r.likes, 9);
    });

    test('KvCache 过期判定', () {
      final alive = KvCache(key: 'k', value: 'v', deadline: 0);
      expect(alive.expired, isFalse);
      final expired = KvCache(key: 'k', value: 'v',
          deadline: DateTime.now().millisecondsSinceEpoch - 1000);
      expect(expired.expired, isTrue);
    });
  });

  group('第十轮调用链契约', () {
    test('readerProviderQuery 与 v14 DAO 在 DatabaseService 落地', () {
      final src = read('lib/data/local/app_database.dart');
      expect(src, contains('static const int _dbVersion = 14'));
      expect(src, contains('v14TableSqls'));
      expect(src, contains('readerProviderQuery'));
      expect(src, contains('shrinkDatabase'));
      expect(src, contains('upsertPageEstimate'));
      expect(src, contains('insertBookReview'));
    });

    test('NativeBridge 覆盖全部 12 个原生通道', () {
      final src = read('lib/help/device/native_bridge.dart');
      for (final ch in [
        'legado/network', 'legado/shortcut', 'legado/media_button',
        'legado/pip', 'legado/pdf_cover', 'legado/mobi_huff',
        'legado/launcher_icon', 'legado/battery', 'legado/brightness',
        'legado/process_text', 'legado/saf', 'legado/reader_provider',
      ]) {
        expect(src, contains(ch), reason: '缺原生通道：$ch');
      }
      expect(src, contains('seedReaderProvider'));
    });

    test('MainActivity 注册全部新通道且 AndroidManifest 注册 Provider/Receiver',
        () {
      final kt = read(
          'android/app/src/main/kotlin/com/legado/md3/MainActivity.kt');
      for (final ch in [
        'legado/reader_provider', 'legado/shortcut', 'legado/media_button',
        'legado/pip', 'legado/pdf_cover', 'legado/mobi_huff',
        'legado/launcher_icon', 'legado/battery', 'legado/brightness',
        'legado/process_text', 'legado/saf',
      ]) {
        expect(kt, contains(ch), reason: 'Kotlin 缺通道：$ch');
      }
      final manifest = read('android/app/src/main/AndroidManifest.xml');
      expect(manifest, contains('ReaderProvider'));
      expect(manifest, contains('MediaButtonReceiver'));
      expect(manifest, contains('supportsPictureInPicture'));
    });

    test('BootstrapService 在 main.dart 启动并串起归档/快捷方式/媒体键', () {
      final main = read('lib/main.dart');
      expect(main, contains('BootstrapService.instance.run'));
      final boot = read('lib/help/storage/bootstrap_service.dart');
      expect(boot, contains('registerExternalDecoder'));
      expect(boot, contains('mediaButtonEvents'));
      expect(boot, contains('readClipboardShibboleth'));
      expect(boot, contains("startsWith('#L:')"));
      expect(boot, contains('setShortcuts'));
    });

    test('RAR/7z 与 MOBI HUFF 在 import_book_service 真实接入（无「暂不支持」）',
        () {
      final src = read('lib/help/storage/import_book_service.dart');
      expect(src, contains('ArchiveImportHelper.open'));
      expect(src, contains('MobiHuffDecompressor.decompressFile'));
      expect(src.contains('暂不支持'), isFalse,
          reason: '不得再留「暂不支持 RAR/7z」的死分支');
    });

    test('3 个 WebSocket 端点真实落地（并列 HTTP/SSE 兼容端点）', () {
      final src = read('lib/help/web/web_service.dart');
      final handlers =
          read('lib/help/web/web_socket_handlers.dart');
      expect(handlers, contains('webSocketHandler'));
      expect(handlers, contains('Duration(seconds: 30)')); // 30s ping
      for (final ep in [
        '/bookSourceDebug', '/rssSourceDebug', '/searchBook'
      ]) {
        expect('$src $handlers', contains(ep), reason: '缺 WS 端点：$ep');
      }
      // 真 WS 升级分派已接入路由（不再只是 SSE/HTTP 兼容端点）
      expect(src, contains('WebSocketHandlers'));
      expect(src, contains('wsHandlers'));
      // 注释不再声称「降级」为 SSE/HTTP（文档与代码一致）
      expect(src.contains('降级为 SSE'), isFalse);
      expect(src.contains('降级 HTTP'), isFalse);
    });

    test('网络监听事件化 + 听书进度挂钩', () {
      final net = read('lib/help/net/network_monitor.dart');
      expect(
          net.contains('connectivity_plus') || net.contains('Connectivity'),
          isTrue);
      expect(net, contains('onConnectivityChanged'));
      final tts = read('lib/help/readaloud/tts_service.dart');
      expect(tts, contains('reading_record'));
      expect(tts, contains('BookProgressSync'));
    });

    test('EPUB 保版式分流接入 reader_router 与 main', () {
      final router = read('lib/ui/book/reader_router.dart');
      expect(router, contains('useEpubLayoutReader'));
      expect(router, contains('EpubReaderScreen'));
      final main = read('lib/main.dart');
      expect(main, contains('ui_epubLayoutReader'));
    });

    test('首页 Feed 容错：DB 异常不无限转圈', () {
      final feed = read('lib/ui/main/discover/homepage_feed.dart');
      expect(feed, contains('try {'));
      expect(feed, contains('_loading = false'));
      expect(feed, contains('首页暂无模块'));
    });

    test('自适应导航：宽屏 NavigationRail + 静态切页回调', () {
      final src = read('lib/ui/main/main_screen.dart');
      expect(src, contains('NavigationRail'));
      expect(src, contains('width >= 720'));
      expect(src, contains('MainScreenSwitch'));
    });

    test('阅读页接入 BGM 面板与 EPUB 切换', () {
      final src = read('lib/ui/book/read/reading_screen.dart');
      expect(src, contains('showBgmPanel'));
      expect(src, contains('useEpubLayoutReader'));
      expect(src, contains('BGM'));
    });
  });
}
