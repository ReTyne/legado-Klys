import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_group.dart';
import 'package:legado_md3/di/book_provider.dart';

Book _b(String name, {String? group, int? lastChapterIndex, int dur = 0}) =>
    Book(name: name, author: '作者', group: group,
        lastChapterIndex: lastChapterIndex, durChapterIndex: dur);

void main() {
  group('书架分组 resolveGroups', () {
    test('合并书籍实际分组与元数据，首位为全部', () {
      final books = [_b('A', group: '玄幻'), _b('B', group: '都市')];
      final meta = [BookGroup(name: '玄幻', order: 1), BookGroup(name: '科幻', order: 0)];
      final g = BookProvider.resolveGroups(books, meta);
      expect(g.first, '全部');
      // 科幻(元数据空分组, order0) 在前，玄幻(order1)，都市(无元数据)按拼音
      expect(g.contains('科幻'), true);
      expect(g.contains('玄幻'), true);
      expect(g.contains('都市'), true);
      expect(g.indexOf('科幻'), lessThan(g.indexOf('玄幻')));
    });

    test('show=0 的分组被隐藏', () {
      final books = [_b('A', group: '玄幻'), _b('B', group: '隐藏')];
      final meta = [
        BookGroup(name: '玄幻', order: 0, show: 1),
        BookGroup(name: '隐藏', order: 1, show: 0),
      ];
      final g = BookProvider.resolveGroups(books, meta);
      expect(g.contains('玄幻'), true);
      expect(g.contains('隐藏'), false);
    });

    test('hideEmpty 时无书的分组不展示', () {
      final books = [_b('A', group: '玄幻')];
      final meta = [BookGroup(name: '玄幻', order: 0), BookGroup(name: '空', order: 1)];
      expect(BookProvider.resolveGroups(books, meta).contains('空'), true);
      expect(BookProvider.resolveGroups(books, meta, hideEmpty: true).contains('空'), false);
    });
  });
}
