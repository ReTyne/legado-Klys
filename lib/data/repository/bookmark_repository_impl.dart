import '../../domain/repository/bookmark_repository.dart';
import '../../data/model/bookmark.dart';
import '../local/app_database.dart';

class BookmarkRepositoryImpl implements BookmarkRepository {
  final DatabaseService _db;
  BookmarkRepositoryImpl([DatabaseService? db]) : _db = db ?? DatabaseService();

  @override
  Future<List<Bookmark>> getBookmarks([String? bookName, String? author]) =>
      _db.getBookmarks(bookName, author);
  @override
  Future<void> addBookmark(Bookmark bookmark) => _db.addBookmark(bookmark);
  @override
  Future<void> deleteBookmark(int id) => _db.deleteBookmark(id);
}
