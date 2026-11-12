import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/ui/book/manga/manga_reader_screen.dart';

import 'helpers/lib_source_helper.dart';

void main() {
  group('漫画双页页数与页对映射', () {
    test('单页模式页数 = 图片数', () {
      expect(mangaPageCount(0, false), 0);
      expect(mangaPageCount(1, false), 1);
      expect(mangaPageCount(5, false), 5);
    });

    test('双页模式页数 = ceil(n/2)', () {
      expect(mangaPageCount(0, true), 0);
      expect(mangaPageCount(1, true), 1);
      expect(mangaPageCount(2, true), 1);
      expect(mangaPageCount(3, true), 2);
      expect(mangaPageCount(4, true), 2);
      expect(mangaPageCount(5, true), 3);
    });

    test('相邻两页拼进同屏，奇数张时最后一屏仅一张', () {
      expect(mangaDoublePageIndices(0, 5), [0, 1]);
      expect(mangaDoublePageIndices(1, 5), [2, 3]);
      expect(mangaDoublePageIndices(2, 5), [4]);
      expect(mangaDoublePageIndices(0, 2), [0, 1]);
      expect(mangaDoublePageIndices(0, 1), [0]);
      expect(mangaDoublePageIndices(3, 5), isEmpty); // 越界屏不渲染图片
    });

    test('所有屏的下标连续覆盖全部图片（无重复无遗漏）', () {
      for (var n = 0; n <= 9; n++) {
        final pages = mangaPageCount(n, true);
        final all = <int>[];
        for (var p = 0; p < pages; p++) {
          all.addAll(mangaDoublePageIndices(p, n));
        }
        expect(all, List<int>.generate(n, (i) => i), reason: '图片数=$n');
      }
    });
  });

  // 双页是 UI 结构改动：除上面的纯函数单测外，再用源码静态断言确认接线
  // （与项目 real_source_compat_test.dart 断言 legado_bridge_js.dart 源码的风格一致）。
  group('双页实现接线（源码静态断言）', () {
    const srcPath = 'lib/ui/book/manga/manga_reader_screen.dart';
    final src = File(srcPath).readAsStringSync() + extraLibrarySources(srcPath);

    test('_scrollMode==2 走双页分支并用 Row/Expanded 并排两张图', () {
      expect(src.contains('final doublePage = _scrollMode == 2;'), isTrue);
      expect(src.contains('return Row('), isTrue);
      expect(src.contains('mangaDoublePageIndices(index, images.length)'), isTrue);
      expect(src.contains('Expanded('), isTrue);
    });

    test('PageView 页数与自动翻页章末判断都用 mangaPageCount', () {
      expect(src.contains('itemCount: mangaPageCount(images.length, doublePage)'),
          isTrue);
      expect(src.contains('mangaPageCount(images.length, _scrollMode == 2) - 1'),
          isTrue);
    });

    test('已移除「降级为普通翻页 / 暂未实现双页拼合」占位说明', () {
      expect(src.contains('降级为普通翻页'), isFalse);
      expect(src.contains('暂未实现双页拼合'), isFalse);
    });
  });
}
