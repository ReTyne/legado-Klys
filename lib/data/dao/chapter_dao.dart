import '../local/app_database.dart';
import '../model/book_chapter.dart';

/// 章节数据访问对象
class ChapterDao {
  final DatabaseService _db;
  ChapterDao([DatabaseService? db]) : _db = db ?? DatabaseService();

  Future<List<BookChapter>> get(String bookName, String author) => _db.getChapters(bookName, author);
  Future<void> insert(String bookName, String author, List<BookChapter> chapters) =>
      _db.insertChapters(bookName, author, chapters);
  Future<void> save(String bookName, String author, List<BookChapter> chapters) =>
      _db.saveChapters(bookName, author, chapters);
  Future<void> updateContent(String bookName, String author, int index, String content) =>
      _db.updateChapterContent(bookName, author, index, content);
  Future<void> delete(String bookName, String author) => _db.deleteChapters(bookName, author);
  Future<void> clearAllContent() => _db.clearChapterContent();
}
