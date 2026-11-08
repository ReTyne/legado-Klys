import 'package:shared_preferences/shared_preferences.dart';

import 'package:legado_md3/data/local/app_database.dart';

/// 阅读记录服务
class ReadingRecordService {
  /// 对齐 legado-E `AppConfig.enableReadRecord`：关闭后不再落库任何阅读/听书
  /// 时长记录。键名与 `ReadRecordConfig.keyEnableReadRecord` 一致（明文键，
  /// 由「阅读记录」页开关写入；此处不 import ui 层以避免 help→ui 循环依赖）。
  Future<bool> _recordEnabled() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getBool('enableReadRecord') ?? true;
    } catch (_) {
      return true;
    }
  }

  final DatabaseService _db = DatabaseService();
  DateTime? _sessionStart;
  String? _currentBook;
  String? _currentAuthor;

  /// 开始阅读会话
  void startSession(String bookName, String author) {
    _sessionStart = DateTime.now();
    _currentBook = bookName;
    _currentAuthor = author;
  }

  /// 结束阅读会话并保存记录
  Future<void> endSession({int? chapterIndex, String? chapterTitle, int? startPos, int? endPos}) async {
    if (_sessionStart == null || _currentBook == null) return;

    final duration = DateTime.now().difference(_sessionStart!).inSeconds;
    _sessionStart = null;
    if (duration < 5) return;
    // enableReadRecord 关闭时只结束会话、不落库记录
    if (!await _recordEnabled()) return;

    await _db.addReadRecord(_currentBook!, _currentAuthor!, duration, DateTime.now().millisecondsSinceEpoch);
  }

  /// 记录一次「听书」朗读时长到 `read_records`（供 tts_service 的
  /// play/pause/complete 挂钩）。与手动阅读会话共用同一张表与统计口径
  /// （[duration] 单位为秒，见 [getTodayDuration] / [getTotalDuration]）。
  ///
  /// 与 [startSession]/[endSession] 的区别：朗读由 TTS 累计「实际播放」
  /// 毫秒数（暂停不计），由调用方精确传入，避免会话式 5 秒门槛把短时
  /// 朗读片段全部丢弃。
  Future<void> recordListening(
    String bookName,
    String author,
    int seconds,
  ) async {
    if (bookName.isEmpty || seconds <= 0) return;
    // enableReadRecord 关闭时不落库听书时长记录
    if (!await _recordEnabled()) return;
    await _db.addReadRecord(
      bookName,
      author,
      seconds,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// 获取今日阅读时长（秒）
  Future<int> getTodayDuration() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    final records = await _db.getReadRecords();
    return records
        .where((r) => r.date >= startOfDay)
        .fold<int>(0, (sum, r) => sum + r.duration);
  }

  /// 获取总阅读时长（秒）
  Future<int> getTotalDuration() async {
    final records = await _db.getReadRecords();
    return records.fold<int>(0, (sum, r) => sum + r.duration);
  }

  /// 获取阅读天数
  Future<int> getReadingDays() async {
    final records = await _db.getReadRecords();
    final days = <String>{};
    for (final r in records) {
      final readDate = r.date as int?;
      if (readDate != null) {
        final date = DateTime.fromMillisecondsSinceEpoch(readDate);
        days.add('${date.year}-${date.month}-${date.day}');
      }
    }
    return days.length;
  }

  /// 连续阅读天数（从今天起，若今天无记录则从昨天起算，向前连续）
  Future<int> getContinuousDays() async {
    final records = await _db.getReadRecords();
    final days = <String>{};
    for (final r in records) {
      final t = r.date as int?;
      if (t == null) continue;
      final d = DateTime.fromMillisecondsSinceEpoch(t);
      days.add('${d.year}-${d.month}-${d.day}');
    }
    if (days.isEmpty) return 0;
    var cursor = DateTime.now();
    String key(DateTime d) => '${d.year}-${d.month}-${d.day}';
    // 今天没读则从昨天开始（保持连续 streak 不中断）
    if (!days.contains(key(cursor))) cursor = cursor.subtract(const Duration(days: 1));
    int streak = 0;
    while (days.contains(key(cursor))) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  /// 获取最近N天的阅读统计
  Future<Map<String, int>> getRecentStats(int days) async {
    final records = await _db.getReadRecords();
    final result = <String, int>{};
    final now = DateTime.now();
    for (int i = 0; i < days; i++) {
      final date = now.subtract(Duration(days: i));
      final key = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      result[key] = 0;
    }
    for (final r in records) {
      final readDate = r.date as int?;
      if (readDate != null) {
        final date = DateTime.fromMillisecondsSinceEpoch(readDate);
        final key = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        if (result.containsKey(key)) {
          result[key] = (result[key] ?? 0) + r.duration;
        }
      }
    }
    return result;
  }

  /// 获取每本书的阅读时长
  Future<Map<String, int>> getBookStats() async {
    final records = await _db.getReadRecords();
    final result = <String, int>{};
    for (final r in records) {
      final key = '${r.bookName}_${r.author}';
      result[key] = (result[key] ?? 0) + r.duration;
    }
    return result;
  }

  /// 格式化时长
  static String formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}秒';
    if (seconds < 3600) return '${seconds ~/ 60}分钟';
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    return '${hours}小时${minutes}分钟';
  }
}
