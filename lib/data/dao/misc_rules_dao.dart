/// misc / rules 相关 DAO。
/// 以 part 归属同一库，可直接访问 DatabaseService 的私有 _db。
part of '../local/app_database.dart';

extension DatabaseServiceMiscRulesDao on DatabaseService {
  Future<String?> getTranslation(String source, String target, String original) async {
    final db = await database;
    final maps = await db.query('translation_caches', where: 'source = ? AND target = ? AND original = ?', whereArgs: [source, target, original]);
    return maps.isNotEmpty ? maps.first['translated'].toString() : null;
  }

  Future<void> saveTranslation(String source, String target, String original, String translated) async {
    final db = await database;
    await db.insert('translation_caches', {'source': source, 'target': target, 'original': original, 'translated': translated, 'saveTime': DateTime.now().millisecondsSinceEpoch});
  }

  // 键盘辅助DAO
  Future<List<KeyboardAssist>> getKeyboardAssists() async {
    final db = await database;
    final maps = await db.query('keyboard_assists', orderBy: '"order" ASC');
    return maps.map((m) => KeyboardAssist.fromMap(m)).toList();
  }

  Future<void> insertKeyboardAssist(KeyboardAssist assist) async {
    final db = await database;
    await db.insert('keyboard_assists', assist.toMap());
  }

  // HTTP TTS DAO
  Future<List<HttpTTS>> getHttpTTS() async {
    final db = await database;
    final maps = await db.query('http_tts');
    return maps.map((m) => HttpTTS.fromMap(m)).toList();
  }

  Future<void> insertHttpTTS(HttpTTS tts) async {
    final db = await database;
    await db.insert('http_tts', tts.toMap());
  }

  /// 更新自定义 HTTP TTS 引擎（编辑页与「自定义 HTTP TTS」分区共用）。
  Future<void> updateHttpTTS(HttpTTS tts) async {
    if (tts.id == null) return;
    final db = await database;
    final values = tts.toMap()..remove('id');
    await db.update('http_tts', values, where: 'id = ?', whereArgs: [tts.id]);
  }

  /// 删除自定义 HTTP TTS 引擎。
  Future<void> deleteHttpTTS(int id) async {
    final db = await database;
    await db.delete('http_tts', where: 'id = ?', whereArgs: [id]);
  }

  // RSS收藏DAO
  Future<List<RssStar>> getRssStars() async {
    final db = await database;
    final maps = await db.query('rss_stars', orderBy: 'starTime DESC');
    return maps.map((m) => RssStar.fromMap(m)).toList();
  }

  Future<void> insertRssStar(RssStar star) async {
    final db = await database;
    await db.insert('rss_stars', star.toMap());
  }

  Future<void> deleteRssStar(int id) async {
    final db = await database;
    await db.delete('rss_stars', where: 'id = ?', whereArgs: [id]);
  }

  // 服务器DAO
  Future<List<Server>> getServers() async {
    final db = await database;
    final maps = await db.query('servers');
    return maps.map((m) => Server.fromMap(m)).toList();
  }

  Future<void> insertServer(Server server) async {
    final db = await database;
    await db.insert('servers', server.toMap());
  }

  // 标签分组规则DAO
  Future<List<TagGroupRule>> getTagGroupRules() async {
    final db = await database;
    final maps = await db.query('tag_group_rules', orderBy: '"order" ASC');
    return maps.map((m) => TagGroupRule.fromMap(m)).toList();
  }

  Future<void> insertTagGroupRule(TagGroupRule rule) async {
    final db = await database;
    await db.insert('tag_group_rules', rule.toMap());
  }

  Future<void> updateTagGroupRule(TagGroupRule rule) async {
    final db = await database;
    if (rule.id != null) await db.update('tag_group_rules', rule.toMap(), where: 'id = ?', whereArgs: [rule.id]);
  }

  Future<void> deleteTagGroupRule(int id) async {
    final db = await database;
    await db.delete('tag_group_rules', where: 'id = ?', whereArgs: [id]);
  }

  // 阅读进度DAO
}
