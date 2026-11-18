import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/data/model/book_chapter.dart';
import 'package:legado_md3/help/source/chapter_relocator.dart';

List<dynamic> chapters(List<String> titles) =>
    titles.map((t) => <String, dynamic>{'title': t}).toList();

void main() {
  group('getDurChapter 智能重定位', () {
    test('标题完全一致', () {
      final newChapters =
          chapters(['序章', '第1章 破晓', '第2章 微光', '第3章 远行']);
      expect(getDurChapter(2, '第2章 微光', newChapters, 4), 2);
    });

    test('新源标题带前缀', () {
      final newChapters =
          chapters(['第1章 破晓', '【精校】第2章 微光', '第3章 远行']);
      expect(getDurChapter(1, '第2章 微光', newChapters, 3), 1);
    });

    test('中文数字序号归一化', () {
      final newChapters =
          chapters(['第1章 破晓', '第二章 微光', '第三章 远行']);
      expect(getDurChapter(1, '第2章 微光', newChapters, 3), 1);
    });

    test('卷标漂移不影响定位', () {
      final newChapters = chapters([
        '第1卷 第1章 破晓',
        '第2卷 第2章 微光',
        '第2卷 第3章 远行',
      ]);
      expect(getDurChapter(1, '第1卷 第2章 微光', newChapters, 3), 1);
    });

    test('章节号跳跃：靠章节号跨越跳号重新定位', () {
      final newChapters = <dynamic>[];
      for (var n = 1; n <= 47; n++) {
        newChapters.add({'title': '第$n章 旧事'});
      }
      // 新源跳过 48..59，第60章落在下标 47；下标 57 对应第70章。
      for (var n = 60; n <= 100; n++) {
        newChapters.add({'title': '第$n章 旧事'});
      }
      newChapters[57] = {'title': '【精校】第70章·破晓'};
      expect(getDurChapter(70, '第七十章 破晓', newChapters, 100), 57);
    });

    test('旧目录长度变化：比例映射候选位命中', () {
      final newChapters = <dynamic>[];
      for (var n = 1; n <= 200; n++) {
        newChapters.add({'title': '第$n章 正文'});
      }
      // 旧 100 章读到第 50 章，新 200 章时同一章位于下标 100。
      newChapters[100] = {'title': '第50章 正文'};
      expect(getDurChapter(50, '第50章 正文', newChapters, 100), 100);
    });

    test('越界钳制到新目录末章', () {
      final newChapters = chapters(['序章', '第1章', '第2章']);
      // round(9 * 3 / 10) = 3，超出 0..2，应钳制为 2。
      expect(getDurChapter(9, '完全无关的标题', newChapters, 10), 2);
    });

    test('oldSize <= 0 时直接用旧下标作候选位', () {
      final newChapters = chapters(['A', 'B', 'C', 'D', 'E']);
      expect(getDurChapter(3, '无数字标题', newChapters, 0), 3);
    });

    test('新目录为空返回 -1', () {
      expect(getDurChapter(0, '第1章', <dynamic>[], 10), -1);
    });

    test('支持 BookChapter.title 字段', () {
      final newChapters = <dynamic>[
        BookChapter(title: '第1章 A', url: '', index: 0),
        BookChapter(title: '第2章 B', url: '', index: 1),
      ];
      expect(getDurChapter(1, '第2章 B', newChapters, 2), 1);
    });
  });
}
