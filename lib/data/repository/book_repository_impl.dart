import '../../domain/repository/book_repository.dart';
import '../../data/model/book.dart';
import '../../data/model/book_chapter.dart';
import '../../data/model/book_group.dart';
import '../local/app_database.dart';

/// 书籍仓库实现：委托 DatabaseService 完成持久化
class BookRepositoryImpl implements BookRepository {
  final DatabaseService _db;
  BookRepositoryImpl([DatabaseService? db]) : _db = db ?? DatabaseService();

  @override
  Future<List<Book>> getAllBooks() => _db.getAllBooks();

  @override
  Future<Book?> getBook(String name, String author) => _db.getBook(name, author);

  @override
  Future<void> insertBook(Book book) => _db.insertBook(book);

  @override
  Future<void> updateBook(Book book) => _db.updateBook(book);

  @override
  Future<void> deleteBook(String name, String author) => _db.deleteBook(name, author);

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

  @override
  Future<List<BookGroup>> getBookGroups() => _db.getBookGroups();

  @override
  Future<void> insertBookGroup(BookGroup group) => _db.insertBookGroup(group);

  @override
  Future<void> deleteBookGroup(int id) => _db.deleteBookGroup(id);

  @override
  Future<void> updateReadPosition(String bookName, String author, int chapterIndex, int pagePos, int time) =>
      _db.updateReadPosition(bookName, author, chapterIndex, pagePos, time);

  @override
  Future<void> clearChapterContent() => _db.clearChapterContent();
}
