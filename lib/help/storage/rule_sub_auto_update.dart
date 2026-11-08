import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/data/model/rss_source.dart';
import 'package:legado_md3/data/model/replace_rule.dart';

/// 规则订阅的导入与自动更新（对齐 legado-E 的 ruleSubsUp() 启动期触发）。
///
/// 项目现有订阅页用 SharedPreferences `rule_subscriptions` 存储（每条含
/// name/url/type/lastUpdate），这里沿用同一份数据，额外识别 `autoUpdate` 与
/// `updateInterval`（小时）字段，UI 只需读写这两个键即可自动接入调度。
/// 导入逻辑 [importByType] 由订阅页与自动更新共用，避免两处解析分叉。
class RuleSubAutoUpdate {
  RuleSubAutoUpdate._();

  static const String prefsKey = 'rule_subscriptions';
  static const String lastRunKey = 'rule_sub_auto_last_run';

  /// 按类型解析并入库，返回导入条数；type=3 自动检测。
  /// 兼容纯 JSON 数组、单对象、JSONL、以及常见的外层包装。
  static Future<int> importByType(int type, String body) async {
    final text = body.trim();
    if (text.isEmpty) return 0;
    dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      final lines = text
          .split(RegExp(r'[\r\n]+'))
          .where((l) => l.trim().startsWith('{'))
          .toList();
      if (lines.isEmpty) return 0;
      decoded = [for (final l in lines) jsonDecode(l)];
    }
    dynamic data = decoded;
    if (data is Map &&
        !(data.containsKey('bookSourceUrl') ||
            data.containsKey('sourceUrl') ||
            data.containsKey('regex'))) {
      for (final k in [
        'data', 'bookSources', 'rssSources', 'replaceRules', 'sources', 'result', 'list'
      ]) {
        if (data[k] is List) {
          data = data[k];
          break;
        }
      }
    }
    final list = data is List ? data : [data];
    final db = DatabaseService();
    var count = 0;
    var realType = type;
    if (realType == 3 && list.isNotEmpty && list.first is Map) {
      final m = Map<String, dynamic>.from(list.first as Map);
      if (m.containsKey('bookSourceUrl')) {
        realType = 0;
      } else if (m.containsKey('sourceUrl') ||
          (m.containsKey('sourceName') && m.containsKey('articleStyle'))) {
        realType = 1;
      } else if (m.containsKey('regex') || m.containsKey('replacement')) {
        realType = 2;
      }
    }
    for (final item in list) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      try {
        if (realType == 0 && (m['bookSourceUrl'] ?? '').toString().isNotEmpty) {
          await db.insertSource(BookSource.fromJson(m));
          count++;
        } else if (realType == 1 && (m['sourceUrl'] ?? '').toString().isNotEmpty) {
          await db.insertRssSource(RssSource.fromJson(m));
          count++;
        } else if (realType == 2 &&
            (m['regex'] ?? m['pattern'] ?? '').toString().isNotEmpty) {
          await db.insertReplaceRule(ReplaceRule.fromMap(m));
          count++;
        }
      } catch (_) {}
    }
    return count;
  }

  /// 拉取单条订阅并导入，返回导入条数。
  static Future<int> updateOne(String url, int type) async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Mobile'
      },
    ));
    final resp = await dio.get<String>(url);
    return importByType(type, resp.data ?? '');
  }

  /// 启动期触发：遍历 autoUpdate=1 且已到间隔的订阅，返回实际更新的条数。
  static Future<int> runDue() async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(prefsKey) ?? <String>[];
    if (list.isEmpty) return 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    var updated = 0;
    final newList = <String>[];
    for (final raw in list) {
      Map<String, dynamic> j;
      try {
        j = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        newList.add(raw);
        continue;
      }
      final auto = (j['autoUpdate'] ?? 0) == 1 || j['autoUpdate'] == true;
      final hours = (j['updateInterval'] ?? 0) is int
          ? (j['updateInterval'] as int)
          : 0;
      final last = (j['lastUpdate'] ?? 0) is int ? (j['lastUpdate'] as int) : 0;
      final due = !auto ||
          hours <= 0 ||
          last == 0 ||
          now - last >= hours * 3600 * 1000;
      if (auto && due) {
        try {
          final type = (j['type'] ?? 3) is int ? (j['type'] as int) : 3;
          await updateOne((j['url'] ?? '').toString(), type);
          j['lastUpdate'] = now;
          updated++;
        } catch (_) {}
      }
      newList.add(jsonEncode(j));
    }
    if (updated > 0) {
      await p.setStringList(prefsKey, newList);
      await p.setInt(lastRunKey, now);
    }
    return updated;
  }
}
