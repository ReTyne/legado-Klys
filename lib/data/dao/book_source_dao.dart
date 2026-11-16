/// book / source 相关 DAO。
/// 以 part 归属同一库，可直接访问 DatabaseService 的私有 _db。
part of '../local/app_database.dart';

extension DatabaseServiceBookSourceDao on DatabaseService {
  Future<List<BookSource>> getAllSources({bool? enabled}) async {
    final db = await database;
    final maps = enabled != null
        ? await db.query('book_sources',
            where: 'enabled = ?',
            whereArgs: [enabled ? 1 : 0],
            orderBy: 'customOrder ASC')
        : await db.query('book_sources', orderBy: 'customOrder ASC');
    return maps.map((m) => BookSource.fromMap(m)).toList();
  }

  Future<BookSource?> getSource(String url) async {
    final db = await database;
    final maps = await db
        .query('book_sources', where: 'bookSourceUrl = ?', whereArgs: [url]);
    return maps.isNotEmpty ? BookSource.fromMap(maps.first) : null;
  }

  Future<void> insertSource(BookSource source) async {
    final db = await database;
    await db.insert('book_sources', source.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateSource(BookSource source) async {
    final db = await database;
    await db.update('book_sources', source.toMap(),
        where: 'bookSourceUrl = ?', whereArgs: [source.bookSourceUrl]);
  }

  /// 仅更新书源运行时变量 variable（JS setVariable 落库，避免整行覆盖）。
  Future<void> updateSourceVariable(String sourceUrl, String variable) async {
    final db = await database;
    await db.update('book_sources', {'variable': variable},
        where: 'bookSourceUrl = ?', whereArgs: [sourceUrl]);
  }

  /// 仅更新订阅源运行时变量 variable（JS setVariable 落库）。
  Future<void> updateRssSourceVariable(
      String sourceUrl, String variable) async {
    final db = await database;
    await db.update('rss_sources', {'variable': variable},
        where: 'url = ?', whereArgs: [sourceUrl]);
  }

  Future<void> deleteSource(String url) async {
    final db = await database;
    await db
        .delete('book_sources', where: 'bookSourceUrl = ?', whereArgs: [url]);
  }

  Future<List<String>> getSourceGroups() async {
    final db = await database;
    final maps = await db.rawQuery(
        'SELECT DISTINCT bookSourceGroup FROM book_sources WHERE bookSourceGroup IS NOT NULL AND bookSourceGroup != ""');
    return maps.map((m) => m['bookSourceGroup'].toString()).toList();
  }

  // ---- 检索 / 过滤 ----

  /// 对书源名 / 分组 / 地址 / 注释四字段做模糊匹配。
  Future<List<BookSource>> searchSources(String key) async {
    final db = await database;
    final like = '%$key%';
    final maps = await db.query(
      'book_sources',
      where: 'bookSourceName LIKE ? OR bookSourceGroup LIKE ? OR '
          'bookSourceUrl LIKE ? OR bookSourceComment LIKE ?',
      whereArgs: [like, like, like, like],
      orderBy: 'customOrder ASC',
    );
    return maps.map((m) => BookSource.fromMap(m)).toList();
  }

  /// 指定分组下的全部书源（按统一分隔符精确匹配分组名）。
  Future<List<BookSource>> getByGroup(String group) async {
    final db = await database;
    final g = group.trim();
    final maps = await db.query('book_sources', orderBy: 'customOrder ASC');
    return maps
        .map((m) => BookSource.fromMap(m))
        .where((s) => s.hasGroup(g))
        .toList();
  }

  /// 指定分组下的已启用书源。
  Future<List<BookSource>> getEnabledByGroup(String group) async {
    final db = await database;
    final g = group.trim();
    final maps = await db.query(
      'book_sources',
      where: 'enabled = ?',
      whereArgs: [1],
      orderBy: 'customOrder ASC',
    );
    return maps
        .map((m) => BookSource.fromMap(m))
        .where((s) => s.enabled && s.hasGroup(g))
        .toList();
  }

  /// 指定书源类型下已启用的书源。
  Future<List<BookSource>> getEnabledByType(int type) async {
    final db = await database;
    final maps = await db.query(
      'book_sources',
      where: 'enabled = ? AND bookSourceType = ?',
      whereArgs: [1, type],
      orderBy: 'customOrder ASC',
    );
    return maps.map((m) => BookSource.fromMap(m)).toList();
  }

  /// 配置了有效 bookUrlPattern 的已启用书源（排除空值与 'NONE' 占位）。
  /// 传入 url 时，只保留 pattern 正则能匹配该 url 的书源。
  Future<List<BookSource>> getByBookUrlPattern([String? url]) async {
    final db = await database;
    final maps = await db.query(
      'book_sources',
      where: "enabled = ? AND bookUrlPattern IS NOT NULL "
          "AND bookUrlPattern != '' AND bookUrlPattern != 'NONE'",
      whereArgs: [1],
      orderBy: 'customOrder ASC',
    );
    final sources = maps.map((m) => BookSource.fromMap(m)).toList();
    if (url == null) return sources;
    return sources.where((s) {
      final pattern = s.bookUrlPattern ?? '';
      try {
        return RegExp(pattern).hasMatch(url);
      } catch (_) {
        return false;
      }
    }).toList();
  }

  /// 无分组（分组为空）的书源。
  Future<List<BookSource>> noGroup() async {
    final db = await database;
    final maps = await db.query(
      'book_sources',
      where: "bookSourceGroup IS NULL OR TRIM(bookSourceGroup) = ''",
      orderBy: 'customOrder ASC',
    );
    return maps.map((m) => BookSource.fromMap(m)).toList();
  }

  // ---- 统计 ----

  Future<int> allCount() async {
    final db = await database;
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM book_sources');
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<bool> has(String url) async {
    final db = await database;
    final rows = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM book_sources WHERE bookSourceUrl = ?',
        [url]);
    return ((rows.first['c'] as int?) ?? 0) > 0;
  }

  Future<int> minOrder() async {
    final db = await database;
    final rows =
        await db.rawQuery('SELECT MIN(customOrder) AS m FROM book_sources');
    return (rows.first['m'] as int?) ?? 0;
  }

  Future<int> maxOrder() async {
    final db = await database;
    final rows =
        await db.rawQuery('SELECT MAX(customOrder) AS m FROM book_sources');
    return (rows.first['m'] as int?) ?? 0;
  }

  /// 是否存在重复的 customOrder 值。
  Future<bool> hasDuplicateOrder() async {
    final db = await database;
    final rows = await db
        .rawQuery('SELECT customOrder FROM book_sources GROUP BY customOrder '
            'HAVING COUNT(*) > 1 LIMIT 1');
    return rows.isNotEmpty;
  }

  // ---- 单列更新 ----

  Future<void> enable(String url, bool value) async {
    final db = await database;
    await db.update('book_sources', {'enabled': value ? 1 : 0},
        where: 'bookSourceUrl = ?', whereArgs: [url]);
  }

  Future<void> enableExplore(String url, bool value) async {
    final db = await database;
    await db.update('book_sources', {'enabledExplore': value ? 1 : 0},
        where: 'bookSourceUrl = ?', whereArgs: [url]);
  }

  /// 批量更新启用状态（事务内逐条单列更新）。
  Future<void> enableSources(List<String> urls, bool value) async {
    if (urls.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      for (final url in urls) {
        await txn.update('book_sources', {'enabled': value ? 1 : 0},
            where: 'bookSourceUrl = ?', whereArgs: [url]);
      }
    });
  }

  /// 批量更新发现启用状态（事务内逐条单列更新）。
  Future<void> enableExploreSources(List<String> urls, bool value) async {
    if (urls.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      for (final url in urls) {
        await txn.update('book_sources', {'enabledExplore': value ? 1 : 0},
            where: 'bookSourceUrl = ?', whereArgs: [url]);
      }
    });
  }

  Future<void> upOrder(String url, int order) async {
    final db = await database;
    await db.update('book_sources', {'customOrder': order},
        where: 'bookSourceUrl = ?', whereArgs: [url]);
  }

  Future<void> upGroup(String url, String? group) async {
    final db = await database;
    await db.update('book_sources', {'bookSourceGroup': group},
        where: 'bookSourceUrl = ?', whereArgs: [url]);
  }

  // ---- 分组整理 ----

  /// 全部去重分组（保持出现顺序）。
  Future<List<String>> allGroups() async {
    final db = await database;
    final maps = await db.query('book_sources', columns: ['bookSourceGroup']);
    final groups = <String>{};
    for (final m in maps) {
      groups.addAll(AppConst.splitGroups(m['bookSourceGroup']?.toString()));
    }
    return groups.toList();
  }

  /// 整理分组：把每行的分组串按统一分隔符拆分、中文排序后规范化写回，
  /// 并返回按中文排序的去重分组列表。
  Future<List<String>> dealGroups() async {
    final db = await database;
    final maps = await db.query(
      'book_sources',
      columns: ['bookSourceUrl', 'bookSourceGroup'],
    );
    final all = <String>{};
    final normalized = <String, String>{};
    for (final m in maps) {
      final groups = AppConst.splitGroups(m['bookSourceGroup']?.toString());
      all.addAll(groups);
      final sorted = groups.toList()..sort(AppConst.compareGroups);
      normalized[m['bookSourceUrl'].toString()] = sorted.join(',');
    }
    await db.transaction((txn) async {
      for (final entry in normalized.entries) {
        await txn.update(
          'book_sources',
          {'bookSourceGroup': entry.value.isEmpty ? null : entry.value},
          where: 'bookSourceUrl = ?',
          whereArgs: [entry.key],
        );
      }
    });
    return all.toList()..sort(AppConst.compareGroups);
  }

  // ---- 投影查询 ----

  /// 只读取列表所需列（含登录 / 发现地址的计算列），避免整行反序列化。
  Future<List<BookSourcePart>> getAllParts() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT bookSourceUrl, bookSourceName, bookSourceGroup, bookSourceType,
             enabled, enabledExplore, customOrder, loginUrl, exploreUrl,
             CASE WHEN loginUrl IS NOT NULL AND loginUrl != '' THEN 1 ELSE 0 END AS hasLoginUrl,
             CASE WHEN exploreUrl IS NOT NULL AND exploreUrl != '' THEN 1 ELSE 0 END AS hasExploreUrl
      FROM book_sources
      ORDER BY customOrder ASC
    ''');
    return rows.map((m) => BookSourcePart.fromMap(m)).toList();
  }

  // 分组DAO
}
