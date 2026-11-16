import 'package:legado_md3/constant/app_const.dart';
import 'package:legado_md3/constant/source_type.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/data/model/rss_source.dart';

/// 书源 / 订阅源的统一入口。
///
/// 按「先书源后订阅源」查找，删除时级联清理变量、检查状态与相关文章，
/// 插入书源时整理来源基数排序号。
class SourceHelp {
  SourceHelp({DatabaseService? db}) : _db = db ?? DatabaseService();

  final DatabaseService _db;

  /// 源类型常量（与 [SourceType] 一致）。
  static const int sourceTypeBook = SourceType.book;
  static const int sourceTypeRss = SourceType.rss;

  /// 每个来源占用的排序号基数间隔。
  static const int sortNumberBase = 1000;

  /// 统一入口：先查书源，再查 RSS 订阅源，都没有返回 null。
  Future<Object?> getSource(String key) async {
    final book = await getBookSource(key);
    if (book != null) return book;
    return getRssSource(key);
  }

  Future<BookSource?> getBookSource(String key) => _db.getSource(key);

  Future<RssSource?> getRssSource(String key) async {
    final db = await _db.database;
    final maps = await db.query(
      'rss_sources',
      where: 'url = ?',
      whereArgs: [key],
      limit: 1,
    );
    return maps.isEmpty ? null : RssSource.fromMap(maps.first);
  }

  /// 返回 key 对应的源类型；未找到返回 -1。
  Future<int> getSourceType(String key) async {
    if (await _db.has(key)) return SourceType.book;
    if (await getRssSource(key) != null) return SourceType.rss;
    return -1;
  }

  /// 级联删除：书源行（含变量列）、检查状态、相关 RSS 源 / 文章 / 收藏、
  /// 以及该书源的变量缓存。全部在一个事务内完成。
  Future<void> deleteSource(String key) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn
          .delete('book_sources', where: 'bookSourceUrl = ?', whereArgs: [key]);
      await txn.delete('book_source_check_states',
          where: 'origin = ?', whereArgs: [key]);
      await txn.delete('rss_sources', where: 'url = ?', whereArgs: [key]);
      await txn
          .delete('rss_articles', where: 'sourceUrl = ?', whereArgs: [key]);
      await txn.delete('rss_stars', where: 'sourceUrl = ?', whereArgs: [key]);
      await txn.delete('kv_caches',
          where: 'key LIKE ?', whereArgs: ['sourceVariable_$key%']);
    });
  }

  /// 启用 / 禁用一个源（自动分发到书源或订阅源）。
  Future<void> enableSource(String key, bool value) async {
    final type = await getSourceType(key);
    if (type == SourceType.book) {
      await _db.enable(key, value);
    } else if (type == SourceType.rss) {
      final db = await _db.database;
      await db.update('rss_sources', {'enabled': value ? 1 : 0},
          where: 'url = ?', whereArgs: [key]);
    }
  }

  /// 插入书源并整理来源基数排序号。
  Future<void> insertBookSource(BookSource source) async {
    await _db.insertSource(source);
    await adjustSortNumber();
  }

  /// 按来源（书源地址域名）分组整理 customOrder：
  /// 每个来源占用一段基数区间，组内按原排序号紧邻编号，来源之间留整段间隔。
  Future<void> adjustSortNumber() async {
    final sources = await _db.getAllSources();
    final groups = <String, List<BookSource>>{};
    for (final s in sources) {
      final origin = _originOf(s.bookSourceUrl);
      groups.putIfAbsent(origin, () => <BookSource>[]).add(s);
    }
    final origins = groups.keys.toList()..sort(AppConst.compareGroups);
    final updates = <String, int>{};
    var base = 0;
    for (final origin in origins) {
      final list = groups[origin]!
        ..sort((a, b) {
          final c = a.customOrder.compareTo(b.customOrder);
          return c != 0 ? c : a.bookSourceUrl.compareTo(b.bookSourceUrl);
        });
      for (var i = 0; i < list.length; i++) {
        updates[list[i].bookSourceUrl] = base + i;
      }
      base += (list.length ~/ sortNumberBase + 1) * sortNumberBase;
    }
    final db = await _db.database;
    await db.transaction((txn) async {
      for (final entry in updates.entries) {
        await txn.update('book_sources', {'customOrder': entry.value},
            where: 'bookSourceUrl = ?', whereArgs: [entry.key]);
      }
    });
  }

  static String _originOf(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    return host.isNotEmpty ? host : url;
  }
}
