import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/ui/book/manga/manga_reader_screen.dart';
import 'package:legado_md3/ui/book/manga/manga_view_config.dart';

void main() {
  group('漫画 5 通道色彩滤镜配置', () {
    test('JSON 往返与越界钳制', () {
      const cfg = MangaColorFilterConfig(r: 51, g: 102, b: 153, a: 204, l: 128);
      final round = MangaColorFilterConfig.fromJson(cfg.toJson());
      expect(round.r, 51);
      expect(round.g, 102);
      expect(round.b, 153);
      expect(round.a, 204);
      expect(round.l, 128);
      final bad = MangaColorFilterConfig.fromJson(<String, dynamic>{
        'r': 999,
        'g': -10,
        'b': 'x',
        'a': 255,
        'l': 1,
      });
      expect(bad.r, 255);
      expect(bad.g, 0);
      expect(bad.b, 0);
      expect(bad.a, 255);
    });

    test('颜色矩阵按 (255-value)/255 削减，0 为原色', () {
      const none = MangaColorFilterConfig();
      expect(none.hasColorAdjust, false);
      final m = none.matrix;
      expect(m[0], 1.0);
      expect(m[6], 1.0);
      expect(m[12], 1.0);
      expect(m[18], 1.0);
      final half = const MangaColorFilterConfig(r: 128).matrix;
      expect(half[0], closeTo(127 / 255, 1e-6));
      expect(half[6], 1.0);
    });

    test('亮度 0 不接管窗口，非 0 换算 0~1', () {
      expect(const MangaColorFilterConfig().windowBrightness, isNull);
      expect(const MangaColorFilterConfig(l: 255).windowBrightness, 1.0);
      expect(const MangaColorFilterConfig(l: 128).windowBrightness,
          closeTo(128 / 255, 1e-6));
    });
  });

  group('漫画页脚信息栏', () {
    MangaFooterConfig cfgWith({bool hideAll = false}) => MangaFooterConfig(
          hideChapterName: hideAll,
          hidePageNumber: hideAll,
          hideChapter: hideAll,
          hideProgressRatio: hideAll,
          hideFooter: false,
        );

    test('四段信息齐备并含对应标签', () {
      final text = cfgWith().buildInfo(
        chapterName: '第1话',
        chapterPos: 2,
        imageCount: 10,
        chapterIndex: 3,
        chapterSize: 20,
      );
      expect(text, contains('第1话'));
      expect(text, contains('页码 3/10'));
      expect(text, contains('章节 4/20'));
      expect(text, contains('进度 '));
    });

    test('隐藏标签后仅保留数值', () {
      const cfg = MangaFooterConfig(
        hidePageNumberLabel: true,
        hideChapterLabel: true,
        hideProgressRatioLabel: true,
      );
      final text = cfg.buildInfo(
        chapterName: 'A',
        chapterPos: 0,
        imageCount: 5,
        chapterIndex: 0,
        chapterSize: 10,
      );
      expect(text, isNot(contains('页码')));
      expect(text, contains('1/5'));
      expect(text, contains('1/10'));
    });

    test('整栏隐藏返回空串', () {
      final text = const MangaFooterConfig(hideFooter: true).buildInfo(
        chapterName: 'A',
        chapterPos: 0,
        imageCount: 5,
        chapterIndex: 0,
        chapterSize: 10,
      );
      expect(text, isEmpty);
    });

    test('进度计算：末页 100%，非末页封顶 99.9%，空数据 0%', () {
      String percent(int ci, int cs, int cp, int ic) =>
          const MangaFooterConfig().buildInfo(
            chapterName: '',
            chapterPos: cp,
            imageCount: ic,
            chapterIndex: ci,
            chapterSize: cs,
          );
      expect(percent(0, 0, 0, 0), contains('0.0%'));
      expect(percent(9, 10, 9, 10), contains('100.0%'));
      expect(percent(0, 10, 0, 10), contains('1.0%'));
      // 浮点舍入到 100.0% 但并非最后一页时封顶 99.9%
      expect(percent(0, 1, 199998, 200000), contains('99.9%'));
    });
  });

  group('双页拼合', () {
    test('页数按 ceil(n/2) 且末屏仅左页', () {
      expect(mangaPageCount(5, true), 3);
      expect(mangaPageCount(6, true), 3);
      expect(mangaPageCount(5, false), 5);
      expect(mangaDoublePageIndices(2, 5), <int>[4]);
      expect(mangaDoublePageIndices(0, 5), <int>[0, 1]);
    });
  });
}
