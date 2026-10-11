import 'package:shared_preferences/shared_preferences.dart';

/// 搜索历史关键词 DAO（基于 SharedPreferences）
class SearchKeywordDao {
  static const _key = 'search_keywords';
  static const _max = 50;

  Future<List<String>> getAll() async =>
      (await SharedPreferences.getInstance()).getStringList(_key) ?? [];

  Future<void> save(List<String> keywords) async =>
      (await SharedPreferences.getInstance()).setStringList(_key, keywords.take(_max).toList());

  /// 记录一次搜索（去重、置顶）
  Future<List<String>> record(String keyword) async {
    final list = await getAll();
    list.remove(keyword);
    list.insert(0, keyword);
    await save(list);
    return list;
  }

  Future<List<String>> delete(String keyword) async {
    final list = await getAll()..remove(keyword);
    await save(list);
    return list;
  }

  Future<void> clear() async =>
      (await SharedPreferences.getInstance()).remove(_key);
}
