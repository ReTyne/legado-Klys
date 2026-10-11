import '../local/app_database.dart';
import '../model/read_record.dart';

class ReadRecordDao {
  final DatabaseService _db;
  ReadRecordDao([DatabaseService? db]) : _db = db ?? DatabaseService();

  Future<List<ReadRecord>> getAll([int? limit]) => _db.getReadRecords(limit);
  Future<void> add(String bookName, String author, int duration, int date) =>
      _db.addReadRecord(bookName, author, duration, date);
}
