import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/data/model/rss_source.dart';
import 'package:legado_md3/data/model/replace_rule.dart';

/// 导入前的对比预览结果：新增 / 变更 / 删除三类计数与身份列表。
class SubscriptionDiff {
  const SubscriptionDiff({
    required this.added,
    required this.changed,
    required this.deleted,
  });

  final List<String> added;
  final List<String> changed;
  final List<String> deleted;

  int get addedCount => added.length;
  int get changedCount => changed.length;
  int get deletedCount => deleted.length;
  int get total => addedCount + changedCount + deletedCount;
}

/// 订阅导入预览：包含差异、解析出的订阅条目与本地条目。
class SubscriptionPreview {
  const SubscriptionPreview({
    required this.type,
    required this.diff,
    required this.incoming,
    required this.local,
  });

  final int type;
  final SubscriptionDiff diff;
  final List<Map<String, dynamic>> incoming;
  final List<Map<String, dynamic>> local;

  String get summary =>
      '新增 ${diff.addedCount} · 变更 ${diff.changedCount} · 删除 ${diff.deletedCount}';
}

/// 规则订阅的导入与自动更新。
///
/// 项目现有订阅页用 SharedPreferences `rule_subscriptions` 存储（每条含
/// name/url/type/lastUpdate），这里沿用同一份数据，额外识别 `autoUpdate` 与
/// `updateInterval`（小时）字段，UI 只需读写这两个键即可自动接入调度。
/// 导入逻辑 [importByType] 由订阅页与自动更新共用，避免两处解析分叉。
class RuleSubAutoUpdate {
  RuleSubAutoUpdate._();

  static const String prefsKey = 'rule_subscriptions';
  static const String lastRunKey = 'rule_sub_auto_last_run';
  static const String silentUpdateKey = 'rule_sub_silent_update';
  static const String keepLocalKey = 'rule_sub_keep_local_on_conflict';

  /// 更新过程日志（静默更新开启时不写入）。
  static final List<String> updateLog = <String>[];

  static void _log(String message) =>
      updateLog.add('${DateTime.now().toIso8601String()} $message');

  /// 静默更新开关（不弹提示、不写更新日志）。
  static Future<bool> isSilentUpdate() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(silentUpdateKey) ?? false;
  }

  static Future<void> setSilentUpdate(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(silentUpdateKey, value);
  }

  /// 冲突时是否保留本地修改（默认策略，供订阅页开关持久化）。
  static Future<bool> keepLocalOnConflict() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(keepLocalKey) ?? true;
  }

  static Future<void> setKeepLocalOnConflict(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(keepLocalKey, value);
  }

  // ============================ 解析 ============================

  /// 解析订阅正文为实体 Map 列表，兼容纯 JSON 数组、单对象、JSONL、外层包装。
  static List<Map<String, dynamic>> parseRuleBody(String body) {
    final text = body.trim();
    if (text.isEmpty) return const <Map<String, dynamic>>[];
    dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      final lines = text
          .split(RegExp(r'[\r\n]+'))
          .where((l) => l.trim().startsWith('{'))
          .toList();
      if (lines.isEmpty) return const <Map<String, dynamic>>[];
      final arr = <dynamic>[];
      for (final l in lines) {
        try {
          arr.add(jsonDecode(l));
        } catch (_) {}
      }
      decoded = arr;
    }
    dynamic data = decoded;
    if (data is Map &&
        !(data.containsKey('bookSourceUrl') ||
            data.containsKey('sourceUrl') ||
            data.containsKey('regex'))) {
      for (final k in [
        'data',
        'bookSources',
        'rssSources',
        'replaceRules',
        'sources',
        'result',
        'list'
      ]) {
        if (data[k] is List) {
          data = data[k];
          break;
        }
      }
    }
    final list = data is List ? data : <dynamic>[data];
    return list
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  /// 实体身份键（用于新增/变更/删除判定）。
  static String identityOf(int type, Map<String, dynamic> m) {
    switch (type) {
      case 0:
        return (m['bookSourceUrl'] ?? m['url'] ?? '').toString().trim();
      case 1:
        return (m['sourceUrl'] ?? m['url'] ?? '').toString().trim();
      case 2:
        return (m['pattern'] ?? m['regex'] ?? m['replaceRule'] ?? '')
            .toString()
            .trim();
      default:
        return (m['bookSourceUrl'] ??
                m['sourceUrl'] ??
                m['url'] ??
                m['pattern'] ??
                m['regex'] ??
                '')
            .toString()
            .trim();
    }
  }

  /// 不参与内容比对的易变字段（时间戳 / 排序 / 运行态）。
  static const Set<String> _volatileKeys = <String>{
    'id',
    'lastUpdateTime',
    'customOrder',
    'respondTime',
    'weight',
    'variable',
    'unreadCount',
    'order_num',
  };

  /// 规范化为可比较的 JSON（键排序、剔除易变字段）。
  static String canonicalOf(Map<String, dynamic> m) {
    final keys = m.keys
        .where((k) => !_volatileKeys.contains(k.toString()))
        .map((k) => k.toString())
        .toList()
      ..sort();
    final buf = <String, dynamic>{};
    for (final k in keys) {
      final v = m[k];
      if (v is Map) {
        buf[k] = canonicalOf(Map<String, dynamic>.from(v));
      } else if (v is List) {
        buf[k] = v.toString();
      } else {
        buf[k] = v?.toString();
      }
    }
    return jsonEncode(buf);
  }

  /// 纯对比：按身份键计算新增 / 变更 / 删除三类。
  static SubscriptionDiff computeDiff({
    required int type,
    required List<Map<String, dynamic>> incoming,
    required List<Map<String, dynamic>> local,
  }) {
    final inMap = <String, String>{};
    for (final m in incoming) {
      final id = identityOf(type, m);
      if (id.isNotEmpty) inMap[id] = canonicalOf(m);
    }
    final localMap = <String, String>{};
    for (final m in local) {
      final id = identityOf(type, m);
      if (id.isNotEmpty) localMap[id] = canonicalOf(m);
    }
    final added = <String>[];
    final changed = <String>[];
    final deleted = <String>[];
    for (final e in inMap.entries) {
      if (!localMap.containsKey(e.key)) {
        added.add(e.key);
      } else if (localMap[e.key] != e.value) {
        changed.add(e.key);
      }
    }
    for (final k in localMap.keys) {
      if (!inMap.containsKey(k)) deleted.add(k);
    }
    return SubscriptionDiff(added: added, changed: changed, deleted: deleted);
  }

  // ============================ 预览 ============================

  /// 导入前对比预览。
  /// [localOverride] 便于无数据库环境（测试 / 预览注入）直接计算。
  static Future<SubscriptionPreview> previewImport(
    int type,
    String body, {
    List<Map<String, dynamic>>? localOverride,
  }) async {
    final incoming = parseRuleBody(body);
    final local =
        localOverride ?? await _loadLocalMaps(DatabaseService(), type);
    final diff = computeDiff(type: type, incoming: incoming, local: local);
    return SubscriptionPreview(
        type: type, diff: diff, incoming: incoming, local: local);
  }

  /// 从数据库读取本地实体，统一转成与订阅正文一致的可比较 Map。
  static Future<List<Map<String, dynamic>>> _loadLocalMaps(
      DatabaseService db, int type) async {
    final out = <Map<String, dynamic>>[];
    try {
      if (type == 0) {
        for (final s in await db.getAllSources()) {
          out.add(s.toJson());
        }
      } else if (type == 1) {
        for (final s in await db.getRssSources()) {
          out.add(s.toJson());
        }
      } else {
        for (final r in await db.getReplaceRules()) {
          out.add(r.toLegadoJson());
        }
      }
    } catch (_) {}
    return out;
  }

  /// 本地规范快照（身份 → 规范化内容），用于冲突判定。
  static Future<Map<String, String>> _localCanonical(
      DatabaseService db, int type) async {
    final out = <String, String>{};
    for (final m in await _loadLocalMaps(db, type)) {
      out[identityOf(type, m)] = canonicalOf(m);
    }
    return out;
  }

  static bool _conflictWithLocal(Map<String, String> localCanonical, int type,
          Map<String, dynamic> m) =>
      localCanonical.containsKey(identityOf(type, m)) &&
      localCanonical[identityOf(type, m)] != canonicalOf(m);

  // ============================ 导入 ============================

  /// 按类型解析并入库，返回导入条数；type=3 自动检测。
  ///
  /// [keepLocalOnConflict] 为真时，内容相对本地有差异的已存在条目不覆盖
  /// （保留本地修改）；[silent] 为真时不写更新日志。
  static Future<int> importByType(
    int type,
    String body, {
    bool keepLocalOnConflict = false,
    bool silent = false,
  }) async {
    final list = parseRuleBody(body);
    if (list.isEmpty) return 0;
    final db = DatabaseService();
    var count = 0;
    var realType = type;
    if (realType == 3 && list.isNotEmpty) {
      final m = list.first;
      if (m.containsKey('bookSourceUrl')) {
        realType = 0;
      } else if (m.containsKey('sourceUrl') ||
          (m.containsKey('sourceName') && m.containsKey('articleStyle'))) {
        realType = 1;
      } else if (m.containsKey('regex') || m.containsKey('replacement')) {
        realType = 2;
      }
    }
    final localCanonical = keepLocalOnConflict
        ? await _localCanonical(db, realType)
        : <String, String>{};
    for (final m in list) {
      try {
        if (realType == 0 && (m['bookSourceUrl'] ?? '').toString().isNotEmpty) {
          if (keepLocalOnConflict &&
              _conflictWithLocal(localCanonical, realType, m)) continue;
          await db.insertSource(BookSource.fromJson(m));
          count++;
        } else if (realType == 1 &&
            (m['sourceUrl'] ?? '').toString().isNotEmpty) {
          if (keepLocalOnConflict &&
              _conflictWithLocal(localCanonical, realType, m)) continue;
          await db.insertRssSource(RssSource.fromJson(m));
          count++;
        } else if (realType == 2 &&
            (m['regex'] ?? m['pattern'] ?? '').toString().isNotEmpty) {
          if (keepLocalOnConflict &&
              _conflictWithLocal(localCanonical, realType, m)) continue;
          await db.insertReplaceRule(ReplaceRule.fromMap(m));
          count++;
        }
      } catch (_) {}
    }
    if (!silent) _log('订阅导入完成：$count 条');
    return count;
  }

  /// 拉取单条订阅并导入，返回导入条数。
  static Future<int> updateOne(
    String url,
    int type, {
    bool keepLocalOnConflict = false,
    bool? silent,
  }) async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Mobile'
      },
    ));
    final resp = await dio.get<String>(url);
    final s = silent ?? await isSilentUpdate();
    return importByType(type, resp.data ?? '',
        keepLocalOnConflict: keepLocalOnConflict, silent: s);
  }

  /// 启动期触发：遍历 autoUpdate=1 且已到间隔的订阅，返回实际更新的条数。
  static Future<int> runDue() async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(prefsKey) ?? <String>[];
    if (list.isEmpty) return 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final silent = await isSilentUpdate();
    final keepLocal = await keepLocalOnConflict();
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
      final hours =
          (j['updateInterval'] ?? 0) is int ? (j['updateInterval'] as int) : 0;
      final last = (j['lastUpdate'] ?? 0) is int ? (j['lastUpdate'] as int) : 0;
      final due =
          !auto || hours <= 0 || last == 0 || now - last >= hours * 3600 * 1000;
      if (auto && due) {
        try {
          final type = (j['type'] ?? 3) is int ? (j['type'] as int) : 3;
          await updateOne((j['url'] ?? '').toString(), type,
              keepLocalOnConflict: keepLocal, silent: silent);
          j['lastUpdate'] = now;
          updated++;
          if (!silent) {
            _log('自动更新订阅：${j['name'] ?? j['url']}');
          }
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
