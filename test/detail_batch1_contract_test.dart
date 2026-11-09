import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String src(String p) => File(p).readAsStringSync();

void main() {
  group('假开关治理：每个开关都有业务消费方', () {
    test('媒体键三开关在 bootstrap 与 TtsService 中被真实读取', () {
      final boot = src('lib/help/storage/bootstrap_service.dart');
      expect(boot, contains("prefs.getBool('readAloudByMediaButton')"));
      expect(boot, contains("prefs.getBool('mediaButtonOnExit')"));
      expect(boot, contains("prefs.getBool('ignoreAudioFocus')"));
      expect(boot, contains('_ReadAloudExitObserver'));
      expect(src('lib/help/readaloud/tts_service.dart'),
          contains('static bool ignoreAudioFocus'));
      expect(src('lib/help/readaloud/tts_service.dart'),
          contains('static bool stopReadAloudOnExit'));
      expect(src('lib/ui/book/read/reading_screen.dart'),
          contains('!TtsService.ignoreAudioFocus'));
    });

    test('bitmapCacheSize 应用到引擎图片缓存；processText 门控注册', () {
      final c = src('lib/help/config/app_constants.dart');
      expect(c, contains('applyBitmapCacheSize()'));
      expect(c, contains('maximumSizeBytes'));
      expect(c, contains('1024 * 1024'));
      expect(src('lib/help/storage/bootstrap_service.dart'),
          contains('AppPrefs.applyBitmapCacheSize()'));
      expect(src('lib/help/storage/bootstrap_service.dart'),
          contains('if (!AppPrefs.processText) return;'));
    });

    test('漫画界面开关两处入口统一到同一键且即时同步全局', () {
      expect(src('lib/ui/book/manga/manga_config_screen.dart'),
          contains("_set('oc_showMangaUi', v); showMangaUi = v;"));
      expect(src('lib/ui/config/other_config_screen.dart'),
          contains("if (key == 'showMangaUi') showMangaUi = v;"));
      expect(src('lib/ui/book/manga/manga_config_screen.dart'),
          contains("p.getBool('oc_showMangaUi') ?? p.getBool('manga_ui')"));
    });
  });

  group('RSS articleStyle 五档布局', () {
    test('五档循环并写回源表', () {
      final s = src('lib/ui/rss/rss_articles_screen.dart');
      expect(s, contains('(_articleStyle + 1) % 5'));
      expect(s, contains('await _db.updateRssSource(source)'));
      expect(s, contains("'标准列表', '紧凑列表', '双列网格', '瀑布流', '大图卡片'"));
      expect(s, contains('case 3:'));
      expect(s, contains('case 4:'));
      expect(s, contains('Orientation.landscape'));
      expect(s.contains('_gridLayout'), isFalse, reason: '旧的布尔二选一应已移除');
    });

    test('字段语义纠正为列表布局而非正文渲染方式', () {
      final s = src('lib/data/model/rss_source.dart');
      expect(s, contains('文章列表布局 0..4'));
      expect(s, contains('非正文渲染方式'));
    });
  });
}
