import '../../data/model/bookmark.dart';

/// 书签仓库接口
abstract class BookmarkRepository {
  Future<List<Bookmark>> getBookmarks([String? bookName, String? author]);
  Future<void> addBookmark(Bookmark bookmark);
  Future<void> deleteBookmark(int id);
}
