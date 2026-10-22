import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/data/model/replace_rule.dart';
import 'package:legado_md3/data/model/bookmark.dart';
import 'package:legado_md3/data/model/rss_source.dart';
import 'package:legado_md3/data/model/txt_toc_rule.dart';
import 'package:legado_md3/data/model/db_models.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/help/storage/backup_zip.dart';

/// 备份恢复服务（支持 zip + 轻量加密，兼容旧版纯 JSON 备份）
class BackupService {
  final DatabaseService _db = DatabaseService();

  /// 本地备份保留份数的 SharedPreferences key
  static const String _keepCountKey = 'backup_keep_count';
  static const int defaultKeepCount = 5;

  /* ================= 旧版纯 JSON 备份（保留，保证向后兼容） ================= */

  /// 创建完整备份（旧版 JSON 结构，供 WebDAV/旧逻辑使用）
  Future<Map<String, dynamic>> createBackup({
    bool includeBooks = true,
    bool includeSources = true,
    bool includeReplaceRules = true,
    bool includeReadRecords = true,
    bool includeSettings = true,
  }) async {
    final backup = <String, dynamic>{
      'version': '1.0',
      'backupTime': DateTime.now().toIso8601String(),
      'appVersion': '3.30.0',
    };

    if (includeBooks) {
      final books = await _db.getAllBooks();
      backup['books'] = books.map((b) => b.toMap()).toList();
    }

    if (includeSources) {
      final sources = await _db.getAllSources();
      backup['bookSources'] = sources.map((s) => s.toJson()).toList();
    }

    if (includeReplaceRules) {
      final rules = await _db.getReplaceRules();
      backup['replaceRules'] = rules.map((r) => r.toMap()).toList();
    }

    if (includeReadRecords) {
      final records = await _db.getReadRecords();
      // 必须转成 Map，否则 jsonEncode 遇到 ReadRecord 对象会抛异常
      backup['readRecords'] = records.map((r) => r.toMap()).toList();
    }

    backup['rssSources'] = (await _db.getRssSources()).map((s) => s.toMap()).toList();
    backup['bookmarks'] = (await _db.getBookmarks()).map((b) => b.toMap()).toList();
    backup['txtTocRules'] = (await _db.getTxtTocRules()).map((r) => r.toMap()).toList();
    backup['dictRules'] = (await _db.getDictRules()).map((r) => r.toMap()).toList();

    return backup;
  }

  /// 导出备份到文件（旧版 JSON，保持向后兼容）
  Future<String> exportBackupToFile({
    bool includeBooks = true,
    bool includeSources = true,
    bool includeReplaceRules = true,
    bool includeReadRecords = true,
  }) async {
    final backup = await createBackup(
      includeBooks: includeBooks,
      includeSources: includeSources,
      includeReplaceRules: includeReplaceRules,
      includeReadRecords: includeReadRecords,
    );

    final directory = await getApplicationDocumentsDirectory();
    final fileName = 'legado_backup_${DateTime.now().millisecondsSinceEpoch}.json';
    final file = File('${directory.path}/$fileName');
    await file.writeAsString(jsonEncode(backup));
    return file.path;
  }

  /* ================= 新版 zip 备份 ================= */

  /// 生成设备名（用于备份元信息）
  static Future<String> getDeviceName() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.appName} ${info.version}(${info.buildNumber}) on ${Platform.operatingSystem}';
    } catch (_) {
      return 'Legado on ${Platform.operatingSystem}';
    }
  }

  /// 读取本地备份保留份数配置（默认 5 份）
  Future<int> getKeepCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keepCountKey) ?? defaultKeepCount;
  }

  /// 保存本地备份保留份数配置
  Future<void> setKeepCount(int count) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keepCountKey, count.clamp(1, 100));
  }

  /// 收集各勾选类型的明文 JSON 数据
  Future<Map<BackupType, String>> _collectPayloads(BackupSelection selection) async {
    final payloads = <BackupType, String>{};
    final prefs = await SharedPreferences.getInstance();

    if (selection.contains(BackupType.books)) {
      final books = await _db.getAllBooks();
      payloads[BackupType.books] = jsonEncode(books.map((b) => b.toMap()).toList());
    }
    if (selection.contains(BackupType.bookSources)) {
      final sources = await _db.getAllSources();
      payloads[BackupType.bookSources] = jsonEncode(sources.map((s) => s.toJson()).toList());
    }
    if (selection.contains(BackupType.replaceRules)) {
      final rules = await _db.getReplaceRules();
      payloads[BackupType.replaceRules] = jsonEncode(rules.map((r) => r.toMap()).toList());
    }
    if (selection.contains(BackupType.rssSources)) {
      final list = await _db.getRssSources();
      payloads[BackupType.rssSources] = jsonEncode(list.map((s) => s.toMap()).toList());
    }
    if (selection.contains(BackupType.rssStars)) {
      final list = await _db.getRssStars();
      payloads[BackupType.rssStars] = jsonEncode(list.map((s) => s.toMap()).toList());
    }
    if (selection.contains(BackupType.bookmarks)) {
      final list = await _db.getBookmarks();
      payloads[BackupType.bookmarks] = jsonEncode(list.map((b) => b.toMap()).toList());
    }
    if (selection.contains(BackupType.groups)) {
      final list = await _db.getBookGroups();
      payloads[BackupType.groups] = jsonEncode(list.map((g) => g.toMap()).toList());
    }
    if (selection.contains(BackupType.readRecords)) {
      final list = await _db.getReadRecords();
      payloads[BackupType.readRecords] = jsonEncode(list.map((r) => r.toMap()).toList());
    }
    if (selection.contains(BackupType.txtTocRules)) {
      final list = await _db.getTxtTocRules();
      payloads[BackupType.txtTocRules] = jsonEncode(list.map((r) => r.toMap()).toList());
    }
    if (selection.contains(BackupType.dictRules)) {
      final list = await _db.getDictRules();
      payloads[BackupType.dictRules] = jsonEncode(list.map((r) => r.toMap()).toList());
    }
    if (selection.contains(BackupType.httpTts)) {
      final list = await _db.getHttpTTS();
      payloads[BackupType.httpTts] = jsonEncode(list.map((t) => t.toMap()).toList());
    }
    if (selection.contains(BackupType.ruleSubs)) {
      final list = await _db.getRuleSubs();
      payloads[BackupType.ruleSubs] = jsonEncode(list.map((s) => s.toMap()).toList());
    }
    if (selection.contains(BackupType.searchHistory)) {
      final list = await _db.getSearchHistory(limit: 500);
      payloads[BackupType.searchHistory] = jsonEncode(list);
    }
    if (selection.contains(BackupType.servers)) {
      final list = await _db.getServers();
      payloads[BackupType.servers] = jsonEncode(list.map((s) => s.toMap()).toList());
    }
    if (selection.contains(BackupType.readConfig)) {
      // 阅读配置持久化在 SharedPreferences 的 read_config_json
      final json = prefs.getString('read_config_json');
      payloads[BackupType.readConfig] = json ?? '{}';
    }
    if (selection.contains(BackupType.theme)) {
      // 主题配置（AppTheme 使用的 prefs key）
      payloads[BackupType.theme] = jsonEncode({
        'themeMode': prefs.getInt('theme_mode') ?? 0,
        'seedColor': prefs.getInt('seed_color') ?? 0xFF6750A4,
        'dynamicColor': prefs.getBool('dynamic_color') ?? true,
        'fontFamily': prefs.getString('font_family') ?? '',
      });
    }
    if (selection.contains(BackupType.settings)) {
      // 全部配置：SharedPreferences 全量导出，排除登录/密码等敏感 key
      final map = <String, dynamic>{};
      prefs.getKeys().forEach((k) {
        if (_isSensitivePrefKey(k)) return;
        final v = prefs.get(k);
        if (v is String || v is bool || v is int || v is double || v is List<String>) {
          map[k] = v;
        }
      });
      payloads[BackupType.settings] = jsonEncode(map);
    }
    return payloads;
  }

  /// 判断是否为敏感 prefs key（不导出到 settings.json，防止密码泄露）
  static bool _isSensitivePrefKey(String key) {
    final k = key.toLowerCase();
    return k.contains('pass') ||
        k.contains('login') ||
        k.contains('cookie') ||
        k.contains('token') ||
        k.contains('secret') ||
        k.startsWith('jskv_');
  }

  /// 创建 zip 备份（返回 zip 字节）
  Future<Uint8List> createZipBackup({
    required BackupSelection selection,
    String? password,
  }) async {
    final payloads = await _collectPayloads(selection);
    final index = ZipBackupIndex(
      version: '2.0',
      time: DateTime.now().toIso8601String(),
      deviceName: await getDeviceName(),
      appVersion: '3.30.0',
      // 有密码且存在敏感类型时为加密备份
      encrypted: password != null &&
          password.isNotEmpty &&
          selection.types.any((t) => t.sensitive),
      selection: selection,
    );
    return ZipBackupBuilder.build(
      index: index,
      payloads: payloads,
      password: password,
    );
  }

  /// 导出 zip 备份到本地文件（.zip），并执行「只保留最近 N 份」清理
  Future<String> exportZipBackupToFile({
    required BackupSelection selection,
    String? password,
    bool autoBackup = false,
  }) async {
    final bytes = await createZipBackup(selection: selection, password: password);
    final directory = await getApplicationDocumentsDirectory();
    final prefix = autoBackup ? 'legado_backup_auto' : 'legado_backup';
    final fileName = '${prefix}_${DateTime.now().millisecondsSinceEpoch}.zip';
    final file = File('${directory.path}/$fileName');
    await file.writeAsBytes(bytes);
    // 只保留最近 N 份
    await cleanOldBackups();
    return file.path;
  }

  /// 恢复前自动备份当前数据（防止恢复后数据丢失）
  /// 返回自动备份文件路径；失败返回 null
  Future<String?> autoBackupBeforeRestore() async {
    try {
      return await exportZipBackupToFile(
        selection: BackupSelection.all(),
        autoBackup: true,
      );
    } catch (_) {
      return null;
    }
  }

  /// 清理旧备份：只保留最近 [keep] 份（默认读配置，5 份）
  /// 返回删除的文件数
  Future<int> cleanOldBackups({int? keep}) async {
    final n = keep ?? await getKeepCount();
    final directory = await getApplicationDocumentsDirectory();
    final files = directory
        .listSync()
        .whereType<File>()
        .where((f) {
          final name = f.path.split('/').last;
          return name.startsWith('legado_backup_') &&
              (name.endsWith('.zip') || name.endsWith('.json') || name.endsWith('.bak'));
        })
        .toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    var deleted = 0;
    for (var i = n; i < files.length; i++) {
      try {
        await files[i].delete();
        deleted++;
      } catch (_) {}
    }
    return deleted;
  }

  /// 备份文件概要信息（供恢复界面展示可选项）
  Future<BackupFileInfo> inspectBackupFile(String filePath, {String? password}) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return BackupFileInfo(
        fileName: filePath.split('/').last,
        isZip: false,
        encrypted: false,
        selection: const BackupSelection({}),
        error: '文件不存在',
      );
    }
    final bytes = await file.readAsBytes();
    // zip 文件头标识：PK\x03\x04
    final isZip = bytes.length >= 4 &&
        bytes[0] == 0x50 && bytes[1] == 0x4B &&
        bytes[2] == 0x03 && bytes[3] == 0x04;
    if (isZip) {
      try {
        final data = ZipBackupBuilder.parse(bytes, password: password);
        return BackupFileInfo(
          fileName: file.path.split('/').last,
          isZip: true,
          encrypted: data.index.encrypted,
          deviceName: data.index.deviceName,
          backupTime: data.index.time,
          selection: data.index.selection,
        );
      } catch (e) {
        return BackupFileInfo(
          fileName: file.path.split('/').last,
          isZip: true,
          encrypted: true,
          selection: const BackupSelection({}),
          error: e.toString(),
        );
      }
    }
    // 旧版纯 JSON 备份：按存在的顶层键推断内容类型
    try {
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final types = <BackupType>{};
      for (final t in BackupType.values) {
        if (json.containsKey(t.key)) types.add(t);
      }
      return BackupFileInfo(
        fileName: file.path.split('/').last,
        isZip: false,
        encrypted: false,
        deviceName: '未知设备',
        backupTime: json['backupTime']?.toString(),
        selection: BackupSelection(types),
      );
    } catch (e) {
      return BackupFileInfo(
        fileName: file.path.split('/').last,
        isZip: false,
        encrypted: false,
        selection: const BackupSelection({}),
        error: '无法解析备份文件',
      );
    }
  }

  /// 从文件恢复备份（统一入口）
  /// 自动识别 zip（PK 头）/ 旧版纯 JSON；[password] 用于解密 zip 内敏感文件；
  /// [only] 为 null 时恢复备份内全部内容，否则只恢复勾选类型。
  Future<BackupResult> restoreFromFile(
    String filePath, {
    String? password,
    BackupSelection? only,
  }) async {
    final result = BackupResult();
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        result.error = '文件不存在';
        return result;
      }
      final bytes = await file.readAsBytes();
      final isZip = bytes.length >= 4 &&
          bytes[0] == 0x50 && bytes[1] == 0x4B &&
          bytes[2] == 0x03 && bytes[3] == 0x04;

      final Map<String, dynamic> backup;
      if (isZip) {
        backup = await _readZipAsMap(bytes, password);
      } else {
        // 旧版纯 JSON 备份，直接解析（向后兼容）
        backup = Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)));
      }

      // 统一恢复逻辑（zip 与旧 JSON 走同一套代码）
      await _restoreData(backup, result, only: only);
      result.success = true;
    } catch (e) {
      result.error = '恢复失败: $e';
    }
    return result;
  }

  /// 把 zip 备份还原成与旧版 JSON 相同的 key->数据 Map（敏感文件先解密）
  Future<Map<String, dynamic>> _readZipAsMap(List<int> bytes, String? password) async {
    final data = ZipBackupBuilder.parse(Uint8List.fromList(bytes), password: password);
    final map = <String, dynamic>{};
    data.files.forEach((fileName, content) {
      for (final t in BackupType.values) {
        if (t.file == fileName) {
          final decoded = jsonDecode(content);
          map[t.key] = decoded;
        }
      }
    });
    return map;
  }

  /// 统一恢复逻辑：按类型写入数据库 / SharedPreferences
  /// [only] 非空时只恢复勾选的类型（选择性恢复）
  Future<void> _restoreData(
    Map<String, dynamic> backup,
    BackupResult result, {
    BackupSelection? only,
  }) async {
    bool want(BackupType t) => only == null || only.contains(t);

    // 恢复书籍
    if (want(BackupType.books) &&
        backup.containsKey('books') && backup['books'] is List) {
      for (final bookMap in backup['books']) {
        try {
          final book = Book.fromMap(Map<String, dynamic>.from(bookMap));
          await _db.insertBook(book);
          result.booksRestored++;
        } catch (_) {
          result.booksFailed++;
        }
      }
    }

    // 恢复书源
    if (want(BackupType.bookSources) &&
        backup.containsKey('bookSources') && backup['bookSources'] is List) {
      for (final sourceMap in backup['bookSources']) {
        try {
          final source = BookSource.fromJson(Map<String, dynamic>.from(sourceMap));
          await _db.insertSource(source);
          result.sourcesRestored++;
        } catch (_) {
          result.sourcesFailed++;
        }
      }
    }

    // 恢复阅读记录
    if (want(BackupType.readRecords) &&
        backup.containsKey('readRecords') && backup['readRecords'] is List) {
      for (final m in backup['readRecords']) {
        try {
          final r = ReadRecord.fromMap(Map<String, dynamic>.from(m as Map));
          await _db.addReadRecord(r.bookName, r.author, r.duration, r.date);
          result.count('readRecords');
        } catch (_) {}
      }
    }

    // 恢复替换规则
    if (want(BackupType.replaceRules) &&
        backup.containsKey('replaceRules') && backup['replaceRules'] is List) {
      for (final ruleMap in backup['replaceRules']) {
        try {
          final rule = ReplaceRule.fromMap(Map<String, dynamic>.from(ruleMap));
          await _db.insertReplaceRule(rule);
          result.rulesRestored++;
        } catch (_) {
          result.rulesFailed++;
        }
      }
    }

    // 恢复RSS源
    if (want(BackupType.rssSources) &&
        backup.containsKey('rssSources') && backup['rssSources'] is List) {
      for (final m in backup['rssSources']) {
        try {
          await _db.insertRssSource(RssSource.fromMap(Map<String, dynamic>.from(m)));
          result.count('rssSources');
        } catch (_) {}
      }
    }
    // 恢复RSS收藏
    if (want(BackupType.rssStars) &&
        backup.containsKey('rssStars') && backup['rssStars'] is List) {
      for (final m in backup['rssStars']) {
        try {
          await _db.insertRssStar(RssStar.fromMap(Map<String, dynamic>.from(m)));
          result.count('rssStars');
        } catch (_) {}
      }
    }
    // 恢复书签
    if (want(BackupType.bookmarks) &&
        backup.containsKey('bookmarks') && backup['bookmarks'] is List) {
      for (final m in backup['bookmarks']) {
        try {
          await _db.insertBookmark(Bookmark.fromMap(Map<String, dynamic>.from(m)));
          result.count('bookmarks');
        } catch (_) {}
      }
    }
    // 恢复分组
    if (want(BackupType.groups) &&
        backup.containsKey('groups') && backup['groups'] is List) {
      for (final m in backup['groups']) {
        try {
          await _db.insertBookGroup(BookGroup.fromMap(Map<String, dynamic>.from(m)));
          result.count('groups');
        } catch (_) {}
      }
    }
    // 恢复TXT目录规则
    if (want(BackupType.txtTocRules) &&
        backup.containsKey('txtTocRules') && backup['txtTocRules'] is List) {
      for (final m in backup['txtTocRules']) {
        try {
          await _db.insertTxtTocRule(TxtTocRule.fromMap(Map<String, dynamic>.from(m)));
          result.count('txtTocRules');
        } catch (_) {}
      }
    }
    // 恢复字典规则
    if (want(BackupType.dictRules) &&
        backup.containsKey('dictRules') && backup['dictRules'] is List) {
      for (final m in backup['dictRules']) {
        try {
          await _db.insertDictRule(DictRule.fromMap(Map<String, dynamic>.from(m)));
          result.count('dictRules');
        } catch (_) {}
      }
    }
    // 恢复HTTP TTS
    if (want(BackupType.httpTts) &&
        backup.containsKey('httpTts') && backup['httpTts'] is List) {
      for (final m in backup['httpTts']) {
        try {
          await _db.insertHttpTTS(HttpTTS.fromMap(Map<String, dynamic>.from(m)));
          result.count('httpTts');
        } catch (_) {}
      }
    }
    // 恢复规则订阅
    if (want(BackupType.ruleSubs) &&
        backup.containsKey('ruleSubs') && backup['ruleSubs'] is List) {
      for (final m in backup['ruleSubs']) {
        try {
          await _db.insertRuleSub(RuleSub.fromMap(Map<String, dynamic>.from(m)));
          result.count('ruleSubs');
        } catch (_) {}
      }
    }
    // 恢复搜索历史
    if (want(BackupType.searchHistory) &&
        backup.containsKey('searchHistory') && backup['searchHistory'] is List) {
      for (final m in backup['searchHistory']) {
        try {
          await _db.saveSearchHistory(m.toString());
          result.count('searchHistory');
        } catch (_) {}
      }
    }
    // 恢复服务器
    if (want(BackupType.servers) &&
        backup.containsKey('servers') && backup['servers'] is List) {
      for (final m in backup['servers']) {
        try {
          await _db.insertServer(Server.fromMap(Map<String, dynamic>.from(m)));
          result.count('servers');
        } catch (_) {}
      }
    }
    // 恢复阅读排版配置（写回 SharedPreferences）
    if (want(BackupType.readConfig) && backup['readConfig'] is Map) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('read_config_json', jsonEncode(backup['readConfig']));
      result.count('readConfig');
    }
    // 恢复主题配置（写回 SharedPreferences，需重启/重载 AppTheme 生效）
    if (want(BackupType.theme) && backup['theme'] is Map) {
      final m = Map<String, dynamic>.from(backup['theme'] as Map);
      final prefs = await SharedPreferences.getInstance();
      if (m['themeMode'] != null) await prefs.setInt('theme_mode', (m['themeMode'] as num).toInt());
      if (m['seedColor'] != null) await prefs.setInt('seed_color', (m['seedColor'] as num).toInt());
      if (m['dynamicColor'] != null) await prefs.setBool('dynamic_color', m['dynamicColor'] == true);
      if (m['fontFamily'] != null) await prefs.setString('font_family', m['fontFamily'].toString());
      result.count('theme');
    }
    // 恢复全部配置（SharedPreferences，按存储类型写回）
    if (want(BackupType.settings) && backup['settings'] is Map) {
      final prefs = await SharedPreferences.getInstance();
      final m = Map<String, dynamic>.from(backup['settings'] as Map);
      m.forEach((k, v) {
        if (v is bool) {
          prefs.setBool(k, v);
        } else if (v is int) {
          prefs.setInt(k, v);
        } else if (v is double) {
          prefs.setDouble(k, v);
        } else if (v is String) {
          prefs.setString(k, v);
        } else if (v is List) {
          prefs.setStringList(k, v.cast<String>());
        }
      });
      result.count('settings');
    }
  }

  /// 导入书源（JSON格式，支持 gzip 压缩）
  Future<int> importSources(String content) async {
    int count = 0;
    try {
      // 检测 gzip 压缩（前两个字节为 0x1f 0x8b）
      var jsonStr = content;
      final bytes = utf8.encode(content);
      if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
        try {
          final decoded = gzip.decode(bytes);
          jsonStr = utf8.decode(decoded);
        } catch (_) {}
      }
      final data = jsonDecode(jsonStr);
      List<dynamic> sources;
      if (data is List) {
        sources = data;
      } else if (data is Map && data.containsKey('bookSources')) {
        sources = data['bookSources'] as List;
      } else {
        sources = [data];
      }

      for (final sourceMap in sources) {
        try {
          final source = BookSource.fromJson(Map<String, dynamic>.from(sourceMap));
          await _db.insertSource(source);
          count++;
        } catch (_) {}
      }
    } catch (_) {}
    return count;
  }

  /// 导出书源
  Future<String> exportSources() async {
    final sources = await _db.getAllSources();
    return jsonEncode(sources.map((s) => s.toJson()).toList());
  }

  /// 导入替换规则
  Future<int> importReplaceRules(String content) async {
    int count = 0;
    try {
      final data = jsonDecode(content);
      final rules = data is List ? data : [data];
      for (final ruleMap in rules) {
        try {
          final rule = ReplaceRule.fromMap(Map<String, dynamic>.from(ruleMap));
          await _db.insertReplaceRule(rule);
          count++;
        } catch (_) {}
      }
    } catch (_) {}
    return count;
  }

  /// 获取备份文件列表
  Future<List<File>> getBackupFiles() async {
    final directory = await getApplicationDocumentsDirectory();
    final files = directory.listSync()
        .whereType<File>()
        .where((f) => f.path.contains('legado_backup_'))
        .toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files;
  }

  /// 删除备份文件
  Future<void> deleteBackup(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) await file.delete();
  }
}

/// 备份恢复结果
class BackupResult {
  bool success = false;
  String? error;
  int booksRestored = 0;
  int booksFailed = 0;
  int sourcesRestored = 0;
  int sourcesFailed = 0;
  int rulesRestored = 0;
  int rulesFailed = 0;

  /// 其他类型的恢复计数（key -> 条数）
  final Map<String, int> otherCounts = {};

  /// 记录某类型恢复条数
  void count(String key, [int n = 1]) => otherCounts[key] = (otherCounts[key] ?? 0) + n;

  String get summary {
    if (!success) return error ?? '恢复失败';
    final parts = <String>[
      '书籍: $booksRestored成功/$booksFailed失败',
      '书源: $sourcesRestored成功/$sourcesFailed失败',
      '规则: $rulesRestored成功/$rulesFailed失败',
    ];
    otherCounts.forEach((k, v) => parts.add('$k: $v'));
    return parts.join(', ');
  }
}

/// 备份文件概要信息（恢复界面展示用）
class BackupFileInfo {
  final String fileName;
  final bool isZip;
  final bool encrypted;
  final String? deviceName;
  final String? backupTime;
  final BackupSelection selection;
  final String? error;
  BackupFileInfo({
    required this.fileName,
    required this.isZip,
    required this.encrypted,
    required this.selection,
    this.deviceName,
    this.backupTime,
    this.error,
  });
}
