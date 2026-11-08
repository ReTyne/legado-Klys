import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/auto_task.dart';
import 'package:legado_md3/data/model/rss_read_record.dart';
import 'package:legado_md3/data/model/book_memo.dart';
import 'package:legado_md3/data/model/book_highlight.dart';
import 'package:legado_md3/data/model/download_task.dart';
import 'package:legado_md3/data/model/db_models.dart';

import 'helpers/lib_source_helper.dart';

/// 本轮（v13）新增子系统的回归测试：
/// - 5 张新表在「全新安装」路径下必须建成（_onCreate 的 CREATE TABLE IF NOT EXISTS）；
/// - 5 个模型的 toMap/fromMap 往返保真；
/// - RuleSub 自动更新字段不丢；
/// - 关键调用链用源码契约锁定，防止再次出现「数据孤岛 / 孤儿 UI」。
void main() {
  String read(String p) =>
      File(p).readAsStringSync() + extraLibrarySources(p);

  group('v13 建表', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    Future<Database> onCreateDb() async {
      final db = await databaseFactory.openDatabase(':memory:');
      // 直接执行生产常量，测试与源码零漂移
      for (final sql in DatabaseService.v13TableSqls) {
        await db.execute(sql);
      }
      return db;
    }

    test('5 张新表都在 onCreate 建成', () async {
      final db = await onCreateDb();
      addTearDown(() => db.close());
      final rows = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name IN "
          "('auto_tasks','rss_read_records','book_memos','book_highlights','download_tasks')");
      expect(rows.map((r) => r['name']).toSet(), {
        'auto_tasks', 'rss_read_records', 'book_memos',
        'book_highlights', 'download_tasks',
      });
    });

    test('新表列集合覆盖各模型 toMap 全部键', () async {
      final db = await onCreateDb();
      addTearDown(() => db.close());
      final cases = <String, Map<String, dynamic>>{
        'auto_tasks': AutoTask(name: '刷新', action: 'refresh').toMap(),
        'rss_read_records': RssReadRecord(link: 'u').toMap(),
        'book_memos': BookMemo(bookName: 'b', author: 'a').toMap(),
        'book_highlights': BookHighlight(bookName: 'b', author: 'a').toMap(),
        'download_tasks': DownloadTask(bookName: 'b', author: 'a').toMap(),
      };
      for (final entry in cases.entries) {
        final cols = await db.rawQuery('PRAGMA table_info(${entry.key})');
        final names = cols.map((r) => r['name'] as String).toSet();
        for (final key in entry.value.keys) {
          expect(names.contains(key), isTrue,
              reason: '${entry.key} 缺列: $key');
        }
      }
    });
  });

  group('模型往返', () {
    test('AutoTask 往返 + 每日定点下次运行时间', () {
      final t = AutoTask(
          id: 3, name: '每日备份', action: 'backup', hour: 9, minute: 30,
          enabled: 1, note: '说明');
      final back = AutoTask.fromMap(t.toMap());
      expect(back.id, 3);
      expect(back.action, 'backup');
      expect(back.hour, 9);
      expect(back.scheduleLabel, '每日 09:30');
      final next = t.nextRunTime(from: DateTime(2026, 1, 1, 8, 0).millisecondsSinceEpoch);
      expect(DateTime.fromMillisecondsSinceEpoch(next).hour, 9);
    });

    test('AutoTask 间隔调度标签', () {
      expect(AutoTask(name: 'x', intervalMinutes: 45).scheduleLabel, '每 45 分钟');
    });

    test('RssReadRecord 兼容 int 型 durPos', () {
      final r = RssReadRecord.fromMap({'link': 'u', 'durPos': 12});
      expect(r.durPos, 12.0);
    });

    test('BookHighlight JSON 往返', () {
      final h = BookHighlight(
          bookName: 'b', author: 'a', chapterIndex: 2,
          content: '选中文本', start: 4, end: 8, color: 123, note: '批注');
      final back = BookHighlight.fromJson(h.toJson());
      expect(back.content, '选中文本');
      expect(back.start, 4);
      expect(back.end, 8);
      expect(back.note, '批注');
    });

    test('DownloadTask 进度与状态名', () {
      final t = DownloadTask(bookName: 'b', author: 'a', total: 10, done: 4);
      expect(t.progress, 0.4);
      expect(t.active, isTrue);
      expect(DownloadTask.statusName(2), '已完成');
      expect(DownloadTask.statusName(4), '已暂停');
    });

    test('RuleSub 自动更新字段往返', () {
      final s = RuleSub(
          name: '源', url: 'https://x', type: 'bookSource',
          autoUpdate: 1, updateInterval: 12);
      final back = RuleSub.fromMap(s.toMap());
      expect(back.autoUpdate, 1);
      expect(back.updateInterval, 12);
    });
  });

  group('调用链契约', () {
    test('main.dart 启动期接线 AutoTask / JS 执行器 / 订阅自动更新', () {
      final src = read('lib/main.dart');
      expect(src, contains('AutoTaskService.instance.jsRunner'));
      expect(src, contains('AutoTaskService.instance.start()'));
      expect(src, contains('RuleSubAutoUpdate.runDue()'));
      expect(src, contains('MiniLegadoJs()'));
    });

    test('自定义 HTTP TTS 经适配器进入朗读链路（消除数据孤岛）', () {
      final providers = read('lib/help/readaloud/cloud_tts_providers.dart');
      expect(providers, contains('class HttpTtsProvider extends CloudTtsProvider'));
      expect(providers, contains('{{speakText}}'));
      final tts = read('lib/help/readaloud/tts_service.dart');
      expect(tts, contains('getHttpTTS()'));
      expect(tts, contains('HttpTtsProvider(h)'));
    });

    test('仅 WiFi 加载封面：Dart 侧 + Kotlin 原生两侧闭环', () {
      final monitor = read('lib/help/net/network_monitor.dart');
      expect(monitor, contains("MethodChannel('legado/network')"));
      expect(monitor, contains('isWifi'));
      final kt = read('android/app/src/main/kotlin/com/legado/md3/MainActivity.kt');
      expect(kt, contains('"legado/network"'));
      expect(kt, contains('NetworkCapabilities.TRANSPORT_WIFI'));
      expect(kt, contains('"isWifi" ->'));
      final shelf = read('lib/ui/main/bookshelf/bookshelf_screen.dart');
      expect(shelf, contains('NetworkMonitor.instance.isWifi'));
    });

    test('划线动作双写 book_highlights，供目录第 3 个高亮 Tab 消费', () {
      final reading = read('lib/ui/book/read/reading_screen.dart');
      expect(reading, contains('_db.insertBookMarking(marking)'));
      expect(reading, contains('_db.insertBookHighlight('));
      final toc = read('lib/ui/book/chapter/chapter_list_screen.dart');
      expect(toc, contains('getBookHighlights'));
      expect(toc, contains('length: 3'));
    });

    test('深链补齐 autoTask / highlightRule 导入分支', () {
      final src = read('lib/common/deep_link_service.dart');
      expect(src, contains("return 'autoTask'"));
      expect(src, contains("return 'highlightRule'"));
      expect(src, contains('_importAutoTasks'));
      expect(src, contains('_importHighlightRules'));
    });

    test('订阅页复用共享服务的 importByType，不再两处解析分叉', () {
      final ui = read('lib/ui/rss/rule_subscription_screen.dart');
      expect(ui, contains('RuleSubAutoUpdate.importByType'));
      expect(ui, contains('RuleSubAutoUpdate.runDue()'));
    });

    test('RSS 续读上报与恢复位置', () {
      final ui = read('lib/ui/rss/rss_read_screen.dart');
      expect(ui, contains('getRssReadRecord'));
      expect(ui, contains('upsertRssReadRecord'));
    });

    test('我的页接入新增管理入口', () {
      final p = read('lib/ui/main/my/profile_screen.dart');
      for (final cls in ['AutoTaskScreen', 'HomepageModuleScreen',
          'DownloadManageScreen', 'CloudTtsScreen', 'ReadingStatsScreen']) {
        expect(p, contains(cls), reason: '我的页缺入口: $cls');
      }
    });
  });
}
