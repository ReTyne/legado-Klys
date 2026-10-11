import '../../../data/local/app_database.dart';
import '../../../data/model/read_record.dart';

/// 阅读记录用例：阅读时长统计与聚合
class ReadRecordUseCase {
  final DatabaseService _db;
  ReadRecordUseCase([DatabaseService? db]) : _db = db ?? DatabaseService();

  Future<List<ReadRecord>> recent([int? limit]) => _db.getReadRecords(limit);

  Future<void> record(String bookName, String author, int duration, int date) =>
      _db.addReadRecord(bookName, author, duration, date);

  /// 汇总总阅读时长（毫秒）
  Future<int> totalMillis() async {
    final list = await _db.getReadRecords();
    return list.fold<int>(0, (sum, r) => sum + r.duration);
  }

  /// 按“自然日”聚合阅读时长，key 为当天 0 点的毫秒时间戳，value 为累计毫秒
  Future<Map<int, int>> millisByDay() async {
    final list = await _db.getReadRecords();
    final map = <int, int>{};
    for (final r in list) {
      final d = DateTime.fromMillisecondsSinceEpoch(r.date);
      final dayStart = DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
      map[dayStart] = (map[dayStart] ?? 0) + r.duration;
    }
    return map;
  }
}
