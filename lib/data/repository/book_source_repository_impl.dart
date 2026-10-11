import '../../domain/repository/book_source_repository.dart';
import '../../data/model/book_source.dart';
import '../local/app_database.dart';

class BookSourceRepositoryImpl implements BookSourceRepository {
  final DatabaseService _db;
  BookSourceRepositoryImpl([DatabaseService? db]) : _db = db ?? DatabaseService();

  @override
  Future<List<BookSource>> getAllSources({bool? enabled}) => _db.getAllSources(enabled: enabled);
  @override
  Future<BookSource?> getSource(String url) => _db.getSource(url);
  @override
  Future<void> insertSource(BookSource source) => _db.insertSource(source);
  @override
  Future<void> updateSource(BookSource source) => _db.updateSource(source);
  @override
  Future<void> deleteSource(String url) => _db.deleteSource(url);
  @override
  Future<List<String>> getSourceGroups() => _db.getSourceGroups();
}
