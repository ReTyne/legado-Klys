import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/data/model/auto_task.dart';
import 'package:legado_md3/data/model/read_config.dart';
import 'package:legado_md3/help/storage/auto_task_service.dart';

/// 与基准版逐文件深度对比后补齐的确定性差距回归。
///
/// 覆盖：周期任务永不触发、ReadConfig 页眉页脚字段序列化丢失、
/// 事件回调真假语义、@webjs 列表字段、源变量假开关、
/// RSS 多分组过滤、书架配置重载、默认首页缺项等。
void main() {
  String src(String rel) => File(rel).readAsStringSync();

  group('周期任务到期判定（此前 interval>1 分钟恒不执行）', () {
    final now = DateTime(2026, 11, 24, 10, 0).millisecondsSinceEpoch;

    test('间隔任务从未运行时立即到期', () {
      final t = AutoTask(name: 't', intervalMinutes: 5);
      expect(AutoTaskService.isDue(t, now), isTrue);
    });

    test('间隔任务未到间隔不到期，到达间隔后到期', () {
      final t = AutoTask(name: 't', intervalMinutes: 5,
          lastRunTime: now - 4 * 60 * 1000);
      expect(AutoTaskService.isDue(t, now), isFalse);
      final due = AutoTask(name: 't', intervalMinutes: 5,
          lastRunTime: now - 5 * 60 * 1000);
      expect(AutoTaskService.isDue(due, now), isTrue);
    });

    test('每日任务：计划时刻前不到期，过时刻且当天未跑则到期，跑过不到期', () {
      final at9 = AutoTask(name: 'd', hour: 9, minute: 0,
          lastRunTime: DateTime(2026, 11, 24, 9, 0).millisecondsSinceEpoch);
      // 当前 10:00，日任务 9:00 已过且当天跑过
      expect(AutoTaskService.isDue(at9, now), isFalse);
      final notRun = AutoTask(name: 'd', hour: 9, minute: 0);
      expect(AutoTaskService.isDue(notRun, now), isTrue);
      final future = AutoTask(name: 'd', hour: 11, minute: 0);
      expect(AutoTaskService.isDue(future, now), isFalse);
    });

    test('_tick 使用 isDue 而非 nextRunTime 展示值', () {
      expect(src('lib/help/storage/auto_task_service.dart'),
          contains('if (!isDue(t, now)) continue;'));
    });
  });

  group('ReadConfig 页眉页脚字段序列化', () {
    test('toJson 输出页眉页脚对齐与颜色，往返不丢失', () {
      final cfg = ReadConfig(
        headerAlignCenter: false,
        headerColor: 0xFF112233,
        footerAlignCenter: true,
        footerColor: 0xFF445566,
      );
      final json = cfg.toJson();
      expect(json['headerAlignCenter'], false);
      expect(json['headerColor'], 0xFF112233);
      expect(json['footerAlignCenter'], true);
      expect(json['footerColor'], 0xFF445566);
      final round = ReadConfig.fromJson(json);
      expect(round.headerAlignCenter, false);
      expect(round.headerColor, 0xFF112233);
      expect(round.footerAlignCenter, true);
      expect(round.footerColor, 0xFF445566);
    });

    test('fromJson 缺省颜色与构造函数默认值一致', () {
      final round = ReadConfig.fromJson({});
      expect(round.headerColor, 0xFF6B6B6B);
      expect(round.footerColor, 0xFF6B6B6B);
    });
  });

  group('事件回调真假语义（返回 true = 消费事件）', () {
    test('dispatch 正常求值结果取反表示是否放行', () {
      final s = src('lib/help/source/source_event_callback.dart');
      expect(s, contains('return !_jsTruthy(out.value);'));
    });
  });

  group('列表元素 @webjs 字段分支', () {
    test('_fieldFromElementAsync 具备 webJs 求值分支', () {
      final s = src('lib/help/source/source_engine.dart');
      expect(s, contains('webJsScriptOf(selector)?.trim().isNotEmpty'));
    });
  });

  group('详情页变量假开关修复', () {
    test('写 DB 而非 SharedPreferences', () {
      final s = src('lib/ui/book/detail/book_detail_screen.dart');
      expect(s, contains('await _db.updateSourceVariable(source.bookSourceUrl, v);'));
      expect(s, isNot(contains("sourceVar::")));
      expect(s, isNot(contains("bookVar::")));
    });
  });

  group('RSS 多分组过滤', () {
    test('两处过滤按逗号拆分分组', () {
      final a = src('lib/ui/rss/rss_source_screen.dart');
      final b = src('lib/ui/main/subscribe/subscribe_screen.dart');
      expect(a, contains("_splitGroups(s.sourceGroup).contains(_groupFilter)"));
      expect(b, contains(".split(RegExp(r'[,，]'))"));
    });
    test('启用过滤切换重算可见列表', () {
      final s = src('lib/ui/rss/rss_source_screen.dart');
      expect(s, contains('_applyFilter();'));
    });
  });

  group('书架配置重载与默认首页', () {
    test('配置页保存发信号、书架页监听', () {
      final cfg = src('lib/ui/main/bookshelf/bookshelf_config_screen.dart');
      final sh = src('lib/ui/main/bookshelf/parts/bookshelf_screen_state.dart');
      expect(cfg, contains('bookshelfConfigRevision.value++'));
      expect(sh, contains('bookshelfConfigRevision.addListener(_onConfigChanged)'));
      expect(sh, contains('bookshelfConfigRevision.removeListener(_onConfigChanged)'));
    });
    test('默认首页包含「我的」', () {
      final s = src('lib/ui/config/settings_screen.dart');
      expect(s, contains("_homePageNames = ['书架', '发现', '订阅', '我的']"));
    });
  });

  group('其它 UI 确定性修复', () {
    test('词典规则拖拽用真实 index', () {
      final s = src('lib/ui/config/dict_rule_screen.dart');
      expect(s, contains('ReorderableDragStartListener(\n                          index: index'));
      expect(s, isNot(contains('index: 0, child: Icon(Icons.drag_handle)')));
    });
    test('书源置顶判断用 customOrder < 0', () {
      final s = src('lib/ui/book/source/source_manage_screen.dart');
      expect(s, contains("source.customOrder < 0 ? '取消置顶' : '置顶'"));
    });
    test('WebDAV 备份目录不再硬编码', () {
      final s = src('lib/help/storage/webdav_service.dart');
      expect(s, isNot(contains("'\${_baseUrl}legado_backup/\$fileName'")));
      expect(s, contains('_backupDirPath'));
    });
    test('划词朗读解析云引擎并走云端', () {
      final s = src('lib/help/readaloud/tts_service.dart');
      expect(s, contains("await _cloudSpeak(_currentText!);"));
    });
    test('BGM 朗读 duck 在 TTS 页绑定 probe', () {
      final s = src('lib/ui/book/read/tts_player_screen.dart');
      expect(s, contains('BgmService.instance.bindReadAloudProbe'));
    });
    test('MOBI HUFF/CDIC 阅读路径接上原生解码', () {
      final s = src('lib/help/storage/local_book_parser.dart');
      expect(s, contains('MobiHuffDecompressor.decompressFile(filePath)'));
      expect(s, isNot(contains('当前平台暂不支持正文解压')));
    });
  });
}
