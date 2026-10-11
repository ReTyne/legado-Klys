import '../../data/model/book_chapter.dart';

/// 章节仓库接口
abstract class ChapterRepository {
  Future<List<BookChapter>> getChapters(String bookName, String bookAuthor);
  Future<void> saveChapters(String bookName, String bookAuthor, List<BookChapter> chapters);
  Future<void> updateChapterContent(String bookName, String author, int chapterIndex, String content);
  Future<void> deleteChapters(String bookName, String bookAuthor);
}
