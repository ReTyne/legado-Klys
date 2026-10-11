import '../../../data/model/book_chapter.dart';
import '../../../data/repository/chapter_repository_impl.dart';
import '../../repository/chapter_repository.dart';

/// 阅读业务用例：章节导航、内容获取
class ReadUseCase {
  final ChapterRepository _repo;
  ReadUseCase([ChapterRepository? repo]) : _repo = repo ?? ChapterRepositoryImpl();

  Future<List<BookChapter>> loadToc(String name, String author) => _repo.getChapters(name, author);

  /// 上一章
  BookChapter? prev(List<BookChapter> toc, int index) =>
      index > 0 ? toc[index - 1] : null;

  /// 下一章
  BookChapter? next(List<BookChapter> toc, int index) =>
      index >= 0 && index < toc.length - 1 ? toc[index + 1] : null;

  /// 章节是否已缓存
  bool isCached(BookChapter ch) => ch.content != null && ch.content!.isNotEmpty;

  Future<void> saveContent(String name, String author, int index, String content) =>
      _repo.updateChapterContent(name, author, index, content);

  /// 统计已缓存范围
  int cachedRange(List<BookChapter> toc) =>
      toc.where((c) => c.content != null && c.content!.isNotEmpty).length;
}
