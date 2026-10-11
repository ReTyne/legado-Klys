import '../../../data/model/book.dart';
import '../../../data/model/book_chapter.dart';
import '../../../data/repository/book_repository_impl.dart';
import '../../repository/book_repository.dart';

/// 书籍业务用例：书架管理、章节存取、分组
class BookUseCase {
  final BookRepository _repo;
  BookUseCase([BookRepository? repo]) : _repo = repo ?? BookRepositoryImpl();

  Future<List<Book>> shelf() => _repo.getAllBooks();
  Future<Book?> find(String name, String author) => _repo.getBook(name, author);
  Future<void> add(Book book) => _repo.insertBook(book);
  Future<void> update(Book book) => _repo.updateBook(book);
  Future<void> remove(String name, String author) => _repo.deleteBook(name, author);

  Future<List<BookChapter>> chapters(String name, String author) => _repo.getChapters(name, author);
  Future<void> saveChapters(String name, String author, List<BookChapter> chapters) =>
      _repo.saveChapters(name, author, chapters);
  Future<void> saveProgress(String name, String author, int chapter, int page, int time) =>
      _repo.updateReadPosition(name, author, chapter, page, time);

  /// 书架分组统计
  Future<Map<String, int>> groupCount() async {
    final books = await _repo.getAllBooks();
    final map = <String, int>{};
    for (final b in books) {
      final g = (b.group?.isEmpty ?? true) ? '默认分组' : b.group!;
      map[g] = (map[g] ?? 0) + 1;
    }
    return map;
  }

  /// 统计已缓存章节数
  Future<int> cachedChapterCount(String name, String author) async {
    final chs = await _repo.getChapters(name, author);
    return chs.where((c) => c.content != null && c.content!.isNotEmpty).length;
  }
}
