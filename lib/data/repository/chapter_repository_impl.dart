import '../../domain/repository/chapter_repository.dart';
import '../../data/model/book_chapter.dart';
import '../local/app_database.dart';

class ChapterRepositoryImpl implements ChapterRepository {
  final DatabaseService _db;
  ChapterRepositoryImpl([DatabaseService? db]) : _db = db ?? DatabaseService();

  @override
  Future<List<BookChapter>> getChapters(String bookName, String bookAuthor) =>
      _db.getChapters(bookName, bookAuthor);
  @override
  Future<void> saveChapters(String bookName, String bookAuthor, List<BookChapter> chapters) =>
      _db.saveChapters(bookName, bookAuthor, chapters);
  @override
  Future<void> updateChapterContent(String bookName, String author, int chapterIndex, String content) =>
      _db.updateChapterContent(bookName, author, chapterIndex, content);
  @override
  Future<void> deleteChapters(String bookName, String bookAuthor) =>
      _db.deleteChapters(bookName, bookAuthor);
}
