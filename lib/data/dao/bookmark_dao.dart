import '../local/app_database.dart';
import '../model/bookmark.dart';

class BookmarkDao {
  final DatabaseService _db;
  BookmarkDao([DatabaseService? db]) : _db = db ?? DatabaseService();

  Future<List<Bookmark>> getAll([String? bookName, String? author]) => _db.getBookmarks(bookName, author);
  Future<void> insert(Bookmark b) => _db.insertBookmark(b);
  Future<void> add(Bookmark b) => _db.addBookmark(b);
  Future<void> delete(int id) => _db.deleteBookmark(id);
}
