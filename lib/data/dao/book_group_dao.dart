/// book / group 相关 DAO（由 app_database.dart 拆分，对齐 legado-E data/dao）。
/// 以 part 归属同一库，可直接访问 DatabaseService 的私有 _db。
part of '../local/app_database.dart';

extension DatabaseServiceBookGroupDao on DatabaseService {
  Future<List<BookGroup>> getBookGroups() async {
    final db = await database;
    final maps = await db.query('book_groups', orderBy: '"order" ASC');
    return maps.map((m) => BookGroup.fromMap(m)).toList();
  }

  Future<void> insertBookGroup(BookGroup group) async {
    final db = await database;
    // 带 id 时按主键覆盖，避免显隐/排序保存产生重复行
    await db.insert('book_groups', group.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteBookGroup(int id) async {
    final db = await database;
    await db.delete('book_groups', where: 'id = ?', whereArgs: [id]);
  }

  /// 按名称删除分组元数据
  Future<void> deleteBookGroupByName(String name) async {
    final db = await database;
    await db.delete('book_groups', where: 'name = ?', whereArgs: [name]);
  }

  /// 重命名分组：同步更新元数据与该分组下所有书籍
  Future<void> renameBookGroup(String oldName, String newName) async {
    final db = await database;
    await db.update('book_groups', {'name': newName},
        where: 'name = ?', whereArgs: [oldName]);
    await db.update('books', {'group_name': newName},
        where: 'group_name = ?', whereArgs: [oldName]);
  }

  /// 解散分组：分组下书籍回到未分组，并删除元数据
  Future<void> dissolveBookGroup(String name) async {
    final db = await database;
    await db.update('books', {'group_name': null},
        where: 'group_name = ?', whereArgs: [name]);
    await db.delete('book_groups', where: 'name = ?', whereArgs: [name]);
  }

  // 书签DAO
}
