import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/help/config/app_config.dart';

/// 搜索范围（对照 legado-E ui/book/search/SearchScope.kt）
///
/// scope 三种形态：
///  - 空串：全部启用书源
///  - `分组1,分组2`：按分组多选
///  - `名称::url`：单书源（不缓存，每次需指定）
class SearchScope {
  String scope;

  SearchScope(this.scope);

  /// 由分组列表构造
  SearchScope.fromGroups(List<String> groups) : scope = groups.join(',');

  /// 由书源构造（单书源，名称中的 `:` 需去掉）
  SearchScope.fromSource(BookSource source)
      : scope = '${source.bookSourceName.replaceAll(':', '')}::${source.bookSourceUrl}';

  @override
  String toString() => scope;

  /// 更新范围；[save] 为 false 时不落库（单书源搜索不缓存）
  void update(String scope, {bool save = true}) {
    this.scope = scope;
    if (save) this.save();
  }

  void updateGroups(List<String> groups) {
    scope = groups.join(',');
    save();
  }

  void updateSource(BookSource source) {
    scope = '${source.bookSourceName}::${source.bookSourceUrl}';
    if (!isSource) save();
  }

  /// 是否单书源
  bool get isSource => scope.contains('::');

  /// 是否全部书源
  bool get isAll => scope.isEmpty;

  /// 范围显示名（单书源显示书名源名，否则为分组名列表，空为「全部书源」）
  String get display {
    if (isSource) return scope.substring(0, scope.indexOf('::'));
    if (scope.isEmpty) return '全部书源';
    return scope;
  }

  List<String> get displayNames {
    if (isSource) return [scope.substring(0, scope.indexOf('::'))];
    return scope
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  /// 从范围中移除某一项（单书源范围直接清空）
  void remove(String item) {
    if (isSource) {
      scope = '';
    } else {
      scope = scope
          .split(',')
          .where((e) => e.trim().isNotEmpty && e.trim() != item)
          .join(',');
    }
  }

  /// 范围对应的书源列表（按 customOrder 排序）
  ///
  /// 对齐 E 的 getBookSourceParts：空范围取全部启用书源；单书源按 url 精确匹配；
  /// 分组范围取各分组启用书源并剔除空分组；最终为空则回退全部启用书源。
  Future<List<BookSource>> getBookSourceParts(
      DatabaseService db) async {
    final all = await db.getAllSources(enabled: true);
    List<BookSource> list;
    if (scope.isEmpty) {
      list = all;
    } else if (isSource) {
      // 单书源：按 url 精确匹配（不要求启用，E 允许显式搜索未启用书源）
      final url = scope.substring(scope.indexOf('::') + 2);
      final one = await db.getSource(url);
      list = one == null ? <BookSource>[] : [one];
    } else {
      final groups = scope
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      list = all.where((s) => groups.contains(s.bookSourceGroup)).toList();
      if (list.isEmpty) {
        // 分组全部失效时回退全部（E 会把无效分组从 scope 中剔除）
        scope = '';
        list = all;
      }
    }
    list.sort((a, b) => a.customOrder.compareTo(b.customOrder));
    return list;
  }

  /// 持久化（E: save，单书源/全部/多分组时不写 searchGroup）
  void save() {
    AppPrefs.searchScope = scope;
    if (isAll || isSource || scope.contains(',')) {
      AppPrefs.searchGroup = '';
    } else {
      AppPrefs.searchGroup = scope;
    }
  }
}
