/// 换源结果的用户评分与来源评分（基于 SharedPreferences，独立前缀键）。
///
/// - 单书评分：某书源对某本书的评分（+1 赞 / 0 中性 / -1 踩），键存**绝对分值**。
/// - 来源总分：该书源跨所有书的评分之和，等于其全部单书评分的累加。
///
/// 增量语义：改写单书评分时，来源总分按「新分 - 旧分」的增量变化，
/// 保证来源总分始终等于各单书评分之和。内存缓存避免频繁读盘：
/// [load] 从磁盘重建缓存，[setBookScore] / [removeSource] 改缓存后异步落盘。
library;

import 'package:shared_preferences/shared_preferences.dart';

class SourceScore {
  SourceScore._();

  /// 与其它偏好键隔离的独立前缀。
  static const String keyPrefix = 'sourceScore_';
  static const String _bookPrefix = '${keyPrefix}book_';
  static const String _sourcePrefix = '${keyPrefix}source_';

  static final Map<String, int> _cache = <String, int>{};
  static bool _loaded = false;

  static String _bookKey(String origin, String name, String author) =>
      '$_bookPrefix${origin}_${name}_$author';
  static String _sourceKey(String origin) => '$_sourcePrefix$origin';

  /// 从磁盘（重新）载入缓存。进入换源页、测试 setUp 时调用。
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _cache.clear();
    for (final k in prefs.getKeys()) {
      if (k.startsWith(keyPrefix)) _cache[k] = prefs.getInt(k) ?? 0;
    }
    _loaded = true;
  }

  static Future<void> _ensureLoaded() async {
    if (!_loaded) await load();
  }

  /// 设置某书源对某书的绝对评分（+1/0/-1）。
  ///
  /// 增量 newScore = preScore != 0 ? score - preScore : score；
  /// 单书键写入 score（新分），来源总分键累加 newScore。
  static Future<void> setBookScore(
    String origin,
    String name,
    String author,
    int score,
  ) async {
    await _ensureLoaded();
    final bk = _bookKey(origin, name, author);
    final sk = _sourceKey(origin);
    final preScore = _cache[bk] ?? 0;
    final newScore = (preScore != 0) ? score - preScore : score;
    final preTotal = _cache[sk] ?? 0;
    final newTotal = preTotal + newScore;

    _cache[bk] = score;
    _cache[sk] = newTotal;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(bk, score);
    await prefs.setInt(sk, newTotal);
  }

  /// 读取某书源对某书的评分（内存缓存，需先 [load] 或已调用过 [setBookScore]）。
  static int getBookScore(String origin, String name, String author) =>
      _cache[_bookKey(origin, name, author)] ?? 0;

  /// 读取某来源总分（内存缓存）。
  static int getSourceScore(String origin) => _cache[_sourceKey(origin)] ?? 0;

  /// 删除某来源的全部评分：来源总分键 + 该书源所有单书评分键。
  static Future<void> removeSource(String origin) async {
    await _ensureLoaded();
    final sk = _sourceKey(origin);
    final bookPrefix = '$_bookPrefix${origin}_';
    final keys = _cache.keys
        .where((k) => k == sk || k.startsWith(bookPrefix))
        .toList();
    for (final k in keys) {
      _cache.remove(k);
    }
    final prefs = await SharedPreferences.getInstance();
    for (final k in keys) {
      await prefs.remove(k);
    }
  }
}
