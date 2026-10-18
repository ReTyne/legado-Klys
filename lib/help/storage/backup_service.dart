import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/data/model/replace_rule.dart';
import 'package:legado_md3/data/model/bookmark.dart';
import 'package:legado_md3/data/model/rss_source.dart';
import 'package:legado_md3/data/model/txt_toc_rule.dart';
import 'package:legado_md3/data/model/dict_rule.dart';
import 'package:legado_md3/data/local/app_database.dart';

/// 备份恢复服务
class BackupService {
  final DatabaseService _db = DatabaseService();

  /// 创建完整备份
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

  /// 导出备份到文件
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

  /// 从文件恢复备份
  Future<BackupResult> restoreFromFile(String filePath) async {
    final result = BackupResult();
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        result.error = '文件不存在';
        return result;
      }

      final content = await file.readAsString();
      final backup = jsonDecode(content) as Map<String, dynamic>;

      // 恢复书籍
      if (backup.containsKey('books') && backup['books'] is List) {
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
      if (backup.containsKey('bookSources') && backup['bookSources'] is List) {
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
      if (backup.containsKey('readRecords') && backup['readRecords'] is List) {
        for (final m in backup['readRecords']) {
          try {
            final r = ReadRecord.fromMap(Map<String, dynamic>.from(m as Map));
            await _db.addReadRecord(r.bookName, r.author, r.duration, r.date);
          } catch (_) {}
        }
      }

      // 恢复替换规则
      if (backup.containsKey('replaceRules') && backup['replaceRules'] is List) {
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
      if (backup.containsKey('rssSources') && backup['rssSources'] is List) {
        for (final m in backup['rssSources']) {
          try { await _db.insertRssSource(RssSource.fromMap(Map<String, dynamic>.from(m))); } catch (_) {}
        }
      }
      // 恢复书签
      if (backup.containsKey('bookmarks') && backup['bookmarks'] is List) {
        for (final m in backup['bookmarks']) {
          try { await _db.insertBookmark(Bookmark.fromMap(Map<String, dynamic>.from(m))); } catch (_) {}
        }
      }
      // 恢复TXT目录规则
      if (backup.containsKey('txtTocRules') && backup['txtTocRules'] is List) {
        for (final m in backup['txtTocRules']) {
          try { await _db.insertTxtTocRule(TxtTocRule.fromMap(Map<String, dynamic>.from(m))); } catch (_) {}
        }
      }
      // 恢复字典规则
      if (backup.containsKey('dictRules') && backup['dictRules'] is List) {
        for (final m in backup['dictRules']) {
          try { await _db.insertDictRule(DictRule.fromMap(Map<String, dynamic>.from(m))); } catch (_) {}
        }
      }

      result.success = true;
    } catch (e) {
      result.error = '恢复失败: $e';
    }
    return result;
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

  String get summary {
    if (!success) return error ?? '恢复失败';
    return '书籍: $booksRestored成功/${booksFailed}失败, '
        '书源: $sourcesRestored成功/${sourcesFailed}失败, '
        '规则: $rulesRestored成功/${rulesFailed}失败';
  }
}
