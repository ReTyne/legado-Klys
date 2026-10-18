import '../local/app_database.dart';
import '../model/book.dart';
import '../model/book_group.dart';

/// 书籍数据访问对象
class BookDao {
  final DatabaseService _db;
  BookDao([DatabaseService? db]) : _db = db ?? DatabaseService();

  Future<List<Book>> getAll() => _db.getAllBooks();
  Future<Book?> get(String name, String author) => _db.getBook(name, author);
  Future<void> insert(Book book) => _db.insertBook(book);
  Future<void> update(Book book) => _db.updateBook(book);
  Future<void> delete(String name, String author) => _db.deleteBook(name, author);
  Future<List<BookGroup>> groups() => _db.getBookGroups();
  Future<void> insertGroup(BookGroup g) => _db.insertBookGroup(g);
  Future<void> deleteGroup(int id) => _db.deleteBookGroup(id);
  Future<void> savePosition(String name, String author, int chapter, int page, int time) =>
      _db.updateReadPosition(name, author, chapter, page, time);
}
