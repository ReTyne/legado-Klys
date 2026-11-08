import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/v14_models.dart';

/// 一条 B 站弹幕（对齐 legado-E `BiliDanmukuParser.kt` 的 `<d p="...">` 属性）。
///
/// `p` 字段逗号分隔：`time,type,textSize,color,timestamp,pool,userHash,danmakuId`
///   * [timeMs] 出现时间（秒 × 1000，对齐 Kotlin `(values[0] * 1000).toLong()`）
///   * [type] 1 右→左滚动 / 6 左→右 / 5 顶部固定 / 4 底部固定 / 7 高级 / 8 脚本
///   * [textSize] 字号；[color] 不透明 ARGB（0xAARRGGBB，对齐 `0xff000000 or color`）
///   * [text] 已做 XML 实体解码的弹幕正文
class DanmakuItem {
  DanmakuItem({
    required this.timeMs,
    required this.type,
    required this.textSize,
    required this.color,
    required this.text,
    this.timestamp = 0,
    this.pool = 0,
    this.userId = '',
    this.id = '',
  });

  final int timeMs;
  final int type;
  final double textSize;
  final int color;
  final String text;
  final int timestamp;
  final int pool;
  final String userId;
  final String id;

  /// 供视频页直接使用：键名同时兼容 `video_player_screen._tryParseDanmaku`
  /// 的 `t/time` 与 `text/content` 两套写法。
  Map<String, dynamic> toMap() => {
        't': timeMs / 1000.0,
        'time': timeMs / 1000.0,
        'seconds': timeMs / 1000.0,
        'text': text,
        'content': text,
        'm': text,
        'type': type,
        'size': textSize,
        'color': color,
        'timestamp': timestamp,
        'pool': pool,
        'userId': userId,
        'id': id,
      };

  /// 反解回 B 站 `<d>` 节点，便于持久化 / 再编辑。
  String toXml() {
    final rgb = color & 0xFFFFFF;
    final pValue = [
      (timeMs / 1000.0).toStringAsFixed(3),
      type.toString(),
      textSize.toStringAsFixed(0),
      rgb.toString(),
      timestamp.toString(),
      pool.toString(),
      userId,
      id,
    ].join(',');
    return '<d p="$pValue">${_BiliXml.escape(text)}</d>';
  }
}

/// B 站 XML 弹幕解析器（对齐 legado-E `help/gsyVideo/BiliDanmukuParser.kt`）。
///
/// 纯 Dart 实现，不依赖 `xml` 包；供 F 组视频页在拿到弹幕 XML 后直接调用：
/// ```dart
/// final items = BiliDanmakuParser.parse(xmlString);
/// ```
class BiliDanmakuParser {
  BiliDanmakuParser._();

  /// 匹配 `<d p="...">text</d>`：`p` 支持双引号 / 单引号，标签名大小写不敏感。
  /// group(1)=双引号 p，group(2)=单引号 p，group(3)=正文。
  static final RegExp _dTag = RegExp(
      r'''<d\b[^>]*\bp\s*=\s*(?:"([^"]*)"|'([^']*)')[^>]*>([\s\S]*?)</d>''',
      caseSensitive: false);

  /// 解析整份 B 站 XML，按出现时间升序返回全部弹幕。
  static List<DanmakuItem> parse(String xml) {
    final out = <DanmakuItem>[];
    if (xml.isEmpty) return out;
    for (final m in _dTag.allMatches(xml)) {
      final p = m.group(1) ?? m.group(2) ?? '';
      final text = m.group(3) ?? '';
      final item = parseD(p, text);
      if (item != null) out.add(item);
    }
    out.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return out;
  }

  /// 解析单条 `<d>` 的 `p` 属性与正文（供流式解析或 F 组单独使用）。
  /// 字段不足时按 legado 默认值补齐，任何非数字都安全回退，不抛异常。
  static DanmakuItem? parseD(String p, String rawText) {
    if (p.trim().isEmpty) return null;
    final parts = p.split(',');
    double d(int i, double fallback) =>
        i < parts.length ? (double.tryParse(parts[i].trim()) ?? fallback) : fallback;
    int n(int i, int fallback) =>
        i < parts.length ? (int.tryParse(parts[i].trim()) ?? fallback) : fallback;

    final timeSec = d(0, 0);
    final type = n(1, 1);
    final textSize = d(2, 25);
    final colorRaw = n(3, 0xFFFFFF);
    // 对齐 Kotlin：((0x00000000ff000000L or color) and 0xffffffffL).toInt()
    final color = 0xFF000000 | (colorRaw & 0x00FFFFFF);
    return DanmakuItem(
      timeMs: (timeSec * 1000).toInt(),
      type: type,
      textSize: textSize,
      color: color,
      text: _BiliXml.decode(rawText),
      timestamp: n(4, 0),
      pool: n(5, 0),
      userId: parts.length > 6 ? parts[6].trim() : '',
      id: parts.length > 7 ? parts[7].trim() : '',
    );
  }
}

/// XML 实体编/解码（对齐 `BiliDanmukuParser.decodeXmlString`）。
class _BiliXml {
  static String decode(String s) {
    var out = s.trim();
    // CDATA 包裹的正文先脱壳
    if (out.startsWith('<![CDATA[') && out.endsWith(']]>')) {
      out = out.substring(9, out.length - 3);
    }
    // 数字实体：&#39; / &#x27;
    out = out.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
      final v = int.tryParse(m.group(1)!, radix: 16);
      return v == null ? m.group(0)! : String.fromCharCode(v);
    });
    out = out.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      final v = int.tryParse(m.group(1)!);
      return v == null ? m.group(0)! : String.fromCharCode(v);
    });
    // 命名实体：&amp; 必须最后替换，避免二次解码
    return out
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&');
  }

  static String escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

/// 弹幕文件存储（对齐 Sigma `RuleBigDataHelp.getDanmakuFile`）。
///
/// 文件落在 `<文档目录>/ruleData/book/<md5(bookUrl)>/<md5(chapterUrl)>/<md5("danmaku")>.txt`，
/// 并同步写 `danmaku_caches` 索引（`DatabaseService().upsertDanmakuCache`）。
/// 供 F 组视频页调用：
/// ```dart
/// final store = DanmakuStore.instance;
/// await store.save(bookUrl: u, chapterUrl: c, xml: xmlString);
/// final items = await store.load(u, c);          // 已解析的 List<DanmakuItem>
/// final raw = await store.loadRaw(u, c);         // 原始 XML
/// await store.clear(deadline: DateTime.now().millisecondsSinceEpoch - 30*86400000);
/// ```
class DanmakuStore {
  DanmakuStore._();
  static final DanmakuStore instance = DanmakuStore._();

  final DatabaseService _db = DatabaseService();

  static String _md5(String s) => md5.convert(utf8.encode(s)).toString();

  /// 根目录 `ruleData/book`（对齐 Sigma `externalFiles/ruleData/book`）。
  Future<Directory> _root() async {
    final dir = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(dir.path, 'ruleData', 'book'));
    if (!await root.exists()) await root.create(recursive: true);
    return root;
  }

  /// 三级 MD5 路径（对齐 `RuleBigDataHelp.getDanmakuFile`）。
  Future<File> fileFor(String bookUrl, String chapterUrl) async {
    final root = await _root();
    final bookDir = Directory(p.join(root.path, _md5(bookUrl)));
    final chapterDir = Directory(p.join(bookDir.path, _md5(chapterUrl)));
    if (!await chapterDir.exists()) await chapterDir.create(recursive: true);
    return File(p.join(chapterDir.path, '${_md5('danmaku')}.txt'));
  }

  /// 保存弹幕 XML 到文件，并写入 / 更新 `danmaku_caches` 索引。
  /// 返回落库的 [DanmakuCache]（含条数、路径、更新时间）。
  Future<DanmakuCache> save({
    required String bookUrl,
    required String chapterUrl,
    required String xml,
  }) async {
    final f = await fileFor(bookUrl, chapterUrl);
    await f.writeAsString(xml);
    // 对齐 Sigma putChapterVariable：记录原始 bookUrl，便于 clearInvalid 反查
    final bookUrlFile = File(p.join(f.parent.parent.path, 'bookUrl.txt'));
    if (!await bookUrlFile.exists()) {
      await bookUrlFile.writeAsString(bookUrl);
    }
    final count = BiliDanmakuParser.parse(xml).length;
    final cache = DanmakuCache(
      bookUrl: bookUrl,
      chapterUrl: chapterUrl,
      filePath: f.path,
      count: count,
      updateTime: DateTime.now().millisecondsSinceEpoch,
    );
    await _db.upsertDanmakuCache(cache);
    return cache;
  }

  /// 读取并解析弹幕（优先用索引里的 filePath，再回退按路径规则查找）。
  Future<List<DanmakuItem>> load(String bookUrl, String chapterUrl) async {
    final raw = await loadRaw(bookUrl, chapterUrl);
    if (raw == null || raw.isEmpty) return const <DanmakuItem>[];
    return BiliDanmakuParser.parse(raw);
  }

  /// 读取原始弹幕 XML；不存在返回 null。
  Future<String?> loadRaw(String bookUrl, String chapterUrl) async {
    try {
      final cache = await _db.getDanmakuCache(bookUrl, chapterUrl);
      if (cache != null && cache.filePath.isNotEmpty) {
        final f = File(cache.filePath);
        if (await f.exists()) return await f.readAsString();
      }
    } catch (_) {}
    final f = await fileFor(bookUrl, chapterUrl);
    if (await f.exists()) return await f.readAsString();
    return null;
  }

  /// 按 `deadline` 清理过期弹幕缓存，返回删除的索引条目数。
  ///
  /// [deadline] 为绝对毫秒时间戳：删除 `updateTime` 早于该值的缓存（文件 + 索引）；
  /// 为 null 时不过滤时间（配合 [bookUrl] 走共享 DAO 全清 / 按书清）。
  /// 索引缺失但文件仍在的孤儿文件，按文件修改时间与同一 deadline 一并清理。
  Future<int> clear({String? bookUrl, int? deadline}) async {
    final db = await _db.database;
    final clauses = <String>[];
    final args = <Object?>[];
    if (bookUrl != null) {
      clauses.add('bookUrl = ?');
      args.add(bookUrl);
    }
    if (deadline != null) {
      clauses.add('(updateTime IS NULL OR updateTime < ?)');
      args.add(deadline);
    }
    final where = clauses.isEmpty ? null : clauses.join(' AND ');
    final whereArgs = args.isEmpty ? null : args;
    final rows = await db.query('danmaku_caches', where: where, whereArgs: whereArgs);
    for (final r in rows) {
      final fp = r['filePath']?.toString() ?? '';
      if (fp.isEmpty) continue;
      try {
        final f = File(fp);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    if (deadline == null) {
      // 无时间条件：复用共享底座 DAO（全清或按 bookUrl 清）
      await _db.clearDanmakuCaches(bookUrl: bookUrl);
    } else if (rows.isNotEmpty) {
      await db.delete('danmaku_caches', where: where, whereArgs: whereArgs);
    }
    await _clearOrphanFiles(bookUrl: bookUrl, deadline: deadline);
    return rows.length;
  }

  /// 按保留时长清理：`deadline = now - ttl`（对齐 `KvCache.deadline` 语义）。
  Future<int> clearExpired({
    String? bookUrl,
    Duration ttl = const Duration(days: 30),
  }) =>
      clear(
        bookUrl: bookUrl,
        deadline: DateTime.now().millisecondsSinceEpoch - ttl.inMilliseconds,
      );

  /// 清理孤儿弹幕文件：文件名固定为 `md5("danmaku").txt`，不误删 bookUrl.txt。
  Future<void> _clearOrphanFiles({String? bookUrl, int? deadline}) async {
    final root = await _root();
    if (!await root.exists()) return;
    final fileName = '${_md5('danmaku')}.txt';
    final bookDir = bookUrl == null ? null : _md5(bookUrl);
    await for (final bookEntity in root.list(followLinks: false)) {
      if (bookEntity is! Directory) continue;
      if (bookDir != null && p.basename(bookEntity.path) != bookDir) continue;
      await for (final chapterEntity in bookEntity.list(followLinks: false)) {
        if (chapterEntity is! Directory) continue;
        final f = File(p.join(chapterEntity.path, fileName));
        if (!await f.exists()) continue;
        // 全清（deadline==null）时无条件删；否则按文件 mtime 判定
        if (deadline != null) {
          final stat = await f.stat();
          if (stat.modified.millisecondsSinceEpoch >= deadline) continue;
        }
        try {
          await f.delete();
        } catch (_) {}
      }
    }
  }
}
