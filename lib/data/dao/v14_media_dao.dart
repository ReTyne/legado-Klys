/// v14 / media 相关 DAO（由 app_database.dart 拆分，对齐 legado-E data/dao）。
/// 以 part 归属同一库，可直接访问 DatabaseService 的私有 _db。
part of '../local/app_database.dart';

extension DatabaseServiceV14MediaDao on DatabaseService {
  Future<DanmakuCache?> getDanmakuCache(String bookUrl, String chapterUrl) async {
    final db = await database;
    final maps = await db.query('danmaku_caches',
        where: 'bookUrl = ? AND chapterUrl = ?', whereArgs: [bookUrl, chapterUrl], limit: 1);
    return maps.isEmpty ? null : DanmakuCache.fromMap(maps.first);
  }

  Future<void> upsertDanmakuCache(DanmakuCache c) async {
    final db = await database;
    await db.insert('danmaku_caches', c.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearDanmakuCaches({String? bookUrl}) async {
    final db = await database;
    await db.delete('danmaku_caches',
        where: bookUrl == null ? null : 'bookUrl = ?',
        whereArgs: bookUrl == null ? null : [bookUrl]);
  }

  // --- BGM 曲目 ---
  Future<List<BgmTrack>> getBgmTracks() async {
    final db = await database;
    final maps = await db.query('bgm_tracks', orderBy: 'customOrder ASC, id ASC');
    return maps.map(BgmTrack.fromMap).toList();
  }

  Future<int> insertBgmTrack(BgmTrack t) async {
    final db = await database;
    return db.insert('bgm_tracks', t.toMap());
  }

  Future<void> deleteBgmTrack(int id) async {
    final db = await database;
    await db.delete('bgm_tracks', where: 'id = ?', whereArgs: [id]);
  }

  // --- AI Agent 工具 ---
  Future<List<AiAgentTool>> getAiAgentTools({bool onlyEnabled = false}) async {
    final db = await database;
    final maps = await db.query('ai_agent_tools',
        where: onlyEnabled ? 'enabled = 1' : null, orderBy: 'id ASC');
    return maps.map(AiAgentTool.fromMap).toList();
  }

  Future<void> upsertAiAgentTool(AiAgentTool t) async {
    final db = await database;
    await db.insert('ai_agent_tools', t.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteAiAgentTool(int id) async {
    final db = await database;
    await db.delete('ai_agent_tools', where: 'id = ?', whereArgs: [id]);
  }

  // --- 每书级阅读配置（books.readConfig 列，存 JSON） ---
}
