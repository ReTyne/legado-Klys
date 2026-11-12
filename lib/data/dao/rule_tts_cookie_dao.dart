/// rule / tts / cookie 相关 DAO。
/// 以 part 归属同一库，可直接访问 DatabaseService 的私有 _db。
part of '../local/app_database.dart';

extension DatabaseServiceRuleTtsCookieDao on DatabaseService {
  Future<List<DictRule>> getDictRules() async {
    final db = await database;
    final maps = await db.query('dict_rules', orderBy: '"order" ASC');
    return maps.map((m) => DictRule.fromMap(m)).toList();
  }

  Future<void> insertDictRule(DictRule rule) async {
    final db = await database;
    await db.insert('dict_rules', rule.toMap());
  }

  /// 更新词典规则（编辑名称/地址/规则/启停/排序后保存）
  Future<void> updateDictRule(DictRule rule) async {
    if (rule.id == null) return insertDictRule(rule);
    final db = await database;
    await db.update(
      'dict_rules',
      rule.toMap(),
      where: 'id = ?',
      whereArgs: [rule.id],
    );
  }

  Future<void> deleteDictRule(int id) async {
    final db = await database;
    await db.delete('dict_rules', where: 'id = ?', whereArgs: [id]);
  }

  // 高亮规则DAO
  Future<List<HighlightRule>> getHighlightRules() async {
    final db = await database;
    final maps = await db.query('highlight_rules', orderBy: '"order" ASC');
    return maps.map((m) => HighlightRule.fromMap(m)).toList();
  }

  Future<void> insertHighlightRule(HighlightRule rule) async {
    final db = await database;
    await db.insert('highlight_rules', rule.toMap());
  }

  Future<void> deleteHighlightRule(int id) async {
    final db = await database;
    await db.delete('highlight_rules', where: 'id = ?', whereArgs: [id]);
  }

  // 高亮标签规则DAO
  Future<List<HighlightTagRule>> getHighlightTagRules() async {
    final db = await database;
    final maps = await db.query('highlight_tag_rules', orderBy: '"order" ASC');
    return maps.map((m) => HighlightTagRule.fromMap(m)).toList();
  }

  Future<void> insertHighlightTagRule(HighlightTagRule rule) async {
    final db = await database;
    await db.insert('highlight_tag_rules', rule.toMap());
  }

  Future<void> deleteHighlightTagRule(int id) async {
    final db = await database;
    await db.delete('highlight_tag_rules', where: 'id = ?', whereArgs: [id]);
  }

  // 云TTS DAO
  Future<List<CloudTtsEngine>> getCloudTtsEngines() async {
    final db = await database;
    final maps = await db.query('cloud_tts_engines');
    return maps.map((m) => CloudTtsEngine.fromMap(m)).toList();
  }

  Future<void> insertCloudTtsEngine(CloudTtsEngine engine) async {
    final db = await database;
    await db.insert('cloud_tts_engines', engine.toMap());
  }

  Future<void> updateCloudTtsEngine(CloudTtsEngine engine) async {
    final db = await database;
    if (engine.id != null) await db.update('cloud_tts_engines', engine.toMap(), where: 'id = ?', whereArgs: [engine.id]);
  }

  Future<void> deleteCloudTtsEngine(int id) async {
    final db = await database;
    await db.delete('cloud_tts_engines', where: 'id = ?', whereArgs: [id]);
  }

  // Cookie DAO
  Future<String?> getCookie(String url) async {
    final db = await database;
    final maps = await db.query('cookies', where: 'url = ?', whereArgs: [url]);
    return maps.isNotEmpty ? maps.first['cookie'].toString() : null;
  }

  Future<void> saveCookie(String url, String cookie) async {
    final db = await database;
    await db.insert('cookies', {'url': url, 'cookie': cookie, 'lastUpdateTime': DateTime.now().millisecondsSinceEpoch}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 删除指定 URL（精确）与同域的持久化 Cookie
  Future<void> deleteCookie(String url) async {
    final db = await database;
    String? host;
    try { host = Uri.parse(url).host; } catch (_) {}
    if (host != null && host.isNotEmpty) {
      await db.delete('cookies', where: 'url = ?', whereArgs: [url]);
      // 同域 cookie 一并清理（url 可能以域名/完整地址两种形式保存）
      final all = await db.query('cookies', columns: ['url']);
      for (final row in all) {
        final u = row['url']?.toString() ?? '';
        try {
          final h = Uri.parse(u).host;
          if (h == host || h.endsWith('.$host') || host.endsWith(h)) {
            await db.delete('cookies', where: 'url = ?', whereArgs: [u]);
          }
        } catch (_) {}
      }
    } else {
      await db.delete('cookies', where: 'url = ?', whereArgs: [url]);
    }
  }

  // 书籍知识DAO
}
