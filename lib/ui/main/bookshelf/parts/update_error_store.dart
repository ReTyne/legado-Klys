import 'package:shared_preferences/shared_preferences.dart';

import 'package:legado_md3/data/model/book.dart';

/// 「更新目录失败」标记存储。
///
/// 对齐 legado-E `ui/main/MainViewModel.kt:176,199,215` 的
/// `BookType.updateError` 位标志：书源缺失 / 目录抓取失败时 `addType`，
/// 成功时 `removeType`，关闭「允许更新」时也会清掉。
///
/// 平台差异（显式降级）：本工程 `Book` 目前只有 `int type`（0 文本/1 本地/
/// 2 音频/3 图片/4 视频），没有 BookType 位标志体系（属批次 5 范围，本批
/// 不改数据模型），故用 SharedPreferences 维护一个 `name::author` 集合来
/// 承载该状态，并在书架封面角标与「允许更新」开关处真实消费，避免假状态。
const String kUpdateErrorBooksPref = 'update_error_books';

/// 与 `_db.deleteBook(name, author)` 一致的书标识。
String updateErrorBookKey(Book book) => '${book.name}::${book.author}';

Future<Set<String>> loadUpdateErrorBooks() async {
  final p = await SharedPreferences.getInstance();
  return (p.getStringList(kUpdateErrorBooksPref) ?? const <String>[]).toSet();
}

/// 对齐 E `book.addType(BookType.updateError)`：幂等加入。
Future<void> markUpdateError(Book book) async {
  final p = await SharedPreferences.getInstance();
  final set = (p.getStringList(kUpdateErrorBooksPref) ?? const <String>[]).toSet();
  if (set.add(updateErrorBookKey(book))) {
    await p.setStringList(kUpdateErrorBooksPref, set.toList());
  }
}

/// 对齐 E `book.removeType(BookType.updateError)`：幂等移除。
Future<void> clearUpdateError(Book book) async {
  final p = await SharedPreferences.getInstance();
  final set = (p.getStringList(kUpdateErrorBooksPref) ?? const <String>[]).toSet();
  if (set.remove(updateErrorBookKey(book))) {
    await p.setStringList(kUpdateErrorBooksPref, set.toList());
  }
}
