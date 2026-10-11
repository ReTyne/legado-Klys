import '../local/app_database.dart';
import '../model/book_source.dart';

/// 书源数据访问对象
class BookSourceDao {
  final DatabaseService _db;
  BookSourceDao([DatabaseService? db]) : _db = db ?? DatabaseService();

  Future<List<BookSource>> getAll({bool? enabled}) => _db.getAllSources(enabled: enabled);
  Future<BookSource?> get(String url) => _db.getSource(url);
  Future<void> insert(BookSource s) => _db.insertSource(s);
  Future<void> update(BookSource s) => _db.updateSource(s);
  Future<void> delete(String url) => _db.deleteSource(url);
  Future<List<String>> groups() => _db.getSourceGroups();
}
