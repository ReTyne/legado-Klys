import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book_chapter.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/data/model/db_models.dart';
import 'package:legado_md3/data/model/download_task.dart';
import 'package:legado_md3/help/source/source_engine.dart';

/// 离线缓存下载队列。
///
/// 一条 [DownloadTask] 对应一本书的一段章节区间，执行器按队列顺序逐章
/// 调用 [BookSourceEngine.getContent] 并把正文写入 book_chapters.content
/// （复用阅读页同一张缓存表，下载完即可离线阅读）。
///
/// 通过 [ChangeNotifier] 广播进度，UI 只需 `ValueListenableBuilder` 或
/// `AnimatedBuilder(animation: DownloadService.instance, ...)`。
class DownloadService extends ChangeNotifier {
  DownloadService._();
  static final DownloadService instance = DownloadService._();

  final DatabaseService _db = DatabaseService();
  final BookSourceEngine _engine = BookSourceEngine();

  /// 缓存保留章节数上限（对齐 Sigma imageRetainNum，0 表示不限条目）。
  /// 由设置页写入；未配置时仅按体积上限清理。
  static const String keyImageRetainNum = 'imageRetainNum';
  /// 正文缓存体积上限 MB（与设置页 / cache_manage_screen 同一个 key）。
  static const String keyCacheContentMaxMB = 'cache_contentMaxMB';

  List<DownloadTask> _tasks = <DownloadTask>[];
  List<DownloadTask> get tasks => List.unmodifiable(_tasks);

  bool _pumping = false;
  bool _cancelled = false;
  int? _activeId;
  String _lastError = '';
  String get lastError => _lastError;
  int? get activeId => _activeId;

  Future<void> load() async {
    _tasks = await _db.getDownloadTasks();
    notifyListeners();
  }

  /// 加入一个缓存任务；区间 [startIndex, endIndex]，endIndex<0 表示到目录末尾。
  Future<DownloadTask> enqueue(
    String bookName,
    String author, {
    int startIndex = 0,
    int endIndex = -1,
  }) async {
    final chapters = await _db.getChapters(bookName, author);
    final end = endIndex < 0 || endIndex >= chapters.length
        ? chapters.length - 1
        : endIndex;
    final total = end >= startIndex ? end - startIndex + 1 : 0;
    final t = DownloadTask(
      bookName: bookName,
      author: author,
      startIndex: startIndex,
      endIndex: end,
      currentIndex: startIndex,
      total: total,
      done: 0,
      status: 0,
      createTime: DateTime.now().millisecondsSinceEpoch,
    );
    t.id = await _db.upsertDownloadTask(t);
    _tasks.insert(0, t);
    notifyListeners();
    unawaited(_pump());
    return t;
  }

  /// 「缓存最新章节」：为所有可更新的网络书加入末尾 5 章任务（定时任务动作）。
  Future<int> enqueueLatestChapters({int tail = 5}) async {
    final books = await _db.getAllBooks();
    var count = 0;
    for (final b in books) {
      if (b.local || b.origin == null || b.origin!.isEmpty) continue;
      final chapters = await _db.getChapters(b.name, b.author);
      if (chapters.isEmpty) continue;
      final start = chapters.length > tail ? chapters.length - tail : 0;
      await enqueue(b.name, b.author, startIndex: start, endIndex: chapters.length - 1);
      count++;
    }
    return count;
  }

  Future<void> pause(int id) async => _setStatus(id, 4);
  Future<void> resume(int id) async {
    await _setStatus(id, 0);
    unawaited(_pump());
  }

  Future<void> _setStatus(int id, int status) async {
    final i = _tasks.indexWhere((t) => t.id == id);
    if (i < 0) return;
    _tasks[i].status = status;
    await _db.upsertDownloadTask(_tasks[i]);
    notifyListeners();
  }

  Future<void> cancel(int id) async {
    if (_activeId == id) _cancelled = true;
    final i = _tasks.indexWhere((t) => t.id == id);
    if (i >= 0) {
      await _db.deleteDownloadTask(id);
      _tasks.removeAt(i);
      notifyListeners();
    }
  }

  Future<void> retry(int id) async {
    final i = _tasks.indexWhere((t) => t.id == id);
    if (i < 0) return;
    final t = _tasks[i];
    t.done = 0;
    t.currentIndex = t.startIndex;
    t.status = 0;
    t.error = '';
    await _db.upsertDownloadTask(t);
    notifyListeners();
    unawaited(_pump());
  }

  Future<void> clearFinished() async {
    await _db.clearFinishedDownloadTasks();
    _tasks.removeWhere((t) => t.status == 2);
    notifyListeners();
  }

  /// 串行泵：一次只跑一条任务，任务内逐章下载。
  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      while (true) {
        final next = _tasks.where((t) => t.status == 0).toList()
          ..sort((a, b) => (a.createTime ?? 0).compareTo(b.createTime ?? 0));
        if (next.isEmpty) break;
        await _runTask(next.first);
      }
    } finally {
      _pumping = false;
      _activeId = null;
      notifyListeners();
    }
  }

  Future<void> _runTask(DownloadTask t) async {
    _activeId = t.id;
    _cancelled = false;
    t.status = 1;
    await _db.upsertDownloadTask(t);
    notifyListeners();

    BookSource? source;
    try {
      final book = await _db.getBook(t.bookName, t.author);
      source = book?.origin == null
          ? null
          : await _db.getSource(book!.origin!);
      if (source == null) throw Exception('未找到书源，无法缓存');

      final chapters = await _db.getChapters(t.bookName, t.author);
      for (var i = t.startIndex; i <= t.endIndex && i < chapters.length; i++) {
        if (_cancelled || t.status == 4) {
          t.status = 4;
          await _db.upsertDownloadTask(t);
          notifyListeners();
          return;
        }
        t.currentIndex = i;
        final ch = chapters[i];
        // 已有正文则跳过（幂等，避免重复请求）
        if (ch.content != null && ch.content!.isNotEmpty) {
          t.done++;
        } else {
          final content = await _engine.getContent(source, ch.url, chapter: {
            'index': ch.index,
            'title': ch.title,
            'url': ch.url,
            'bookUrl': book!.bookUrl ?? book.noteUrl ?? '',
          });
          if (content != null && content.isNotEmpty) {
            await _db.updateChapterContent(t.bookName, t.author, ch.index, content);
            // 写 caches 行并自动 LRU（超 imageRetainNum / 体积上限清最旧行）
            await _cacheChapterContent(t, ch, content);
            t.done++;
          } else {
            t.error = '第 ${i + 1} 章正文为空';
          }
        }
        await _db.upsertDownloadTask(t);
        notifyListeners();
      }
      t.status = t.error.isEmpty ? 2 : 3;
    } catch (e) {
      t.status = 3;
      t.error = '$e';
      _lastError = '$e';
    }
    await _db.upsertDownloadTask(t);
    notifyListeners();
  }

  /// 把章节正文写入 caches 表（供离线缓存统计 / LRU 清理），并触发自动 LRU。
  /// 与 book_chapters.content 并存：后者供阅读页离线读，前者供缓存管理统计。
  Future<void> _cacheChapterContent(
      DownloadTask t, BookChapter ch, String content) async {
    final db = await _db.database;
    // 同章覆盖：先删旧行，避免重复缓存让 LRU 计数虚高
    await db.delete(
      'caches',
      where: 'bookName = ? AND author = ? AND chapterIndex = ?',
      whereArgs: [t.bookName, t.author, ch.index],
    );
    await _db.insertCache(Cache(
      bookName: t.bookName,
      author: t.author,
      chapterIndex: ch.index,
      chapterTitle: ch.title,
      content: content,
      size: utf8.encode(content).length,
      saveTime: DateTime.now().millisecondsSinceEpoch,
    ));
    await _enforceCacheLru();
  }

  /// 写缓存后自动 LRU：超 [keyImageRetainNum]（条目数）或
  /// [keyCacheContentMaxMB]（体积上限）时，按 saveTime 从最旧开始删 caches 行。
  Future<void> _enforceCacheLru() async {
    final prefs = await SharedPreferences.getInstance();
    final retainNum = prefs.getInt(keyImageRetainNum) ?? 0;
    final maxMB = prefs.getInt(keyCacheContentMaxMB) ?? 500;
    final limitBytes = maxMB > 0 ? maxMB * 1024 * 1024 : 0;
    final caches = await _db.getCaches(); // saveTime DESC（最新在前）
    var totalBytes = 0;
    for (final c in caches) {
      totalBytes += c.size;
    }
    final overCount = retainNum > 0 && caches.length > retainNum;
    final overSize = limitBytes > 0 && totalBytes > limitBytes;
    if (!overCount && !overSize) return;

    // 反转为最旧在前，逐个删除直到两个阈值都满足
    final oldest = List<Cache>.from(caches)
      ..sort((a, b) => a.saveTime.compareTo(b.saveTime));
    final db = await _db.database;
    var bytes = totalBytes;
    var count = caches.length;
    for (final c in oldest) {
      final stillOverCount = overCount && count > retainNum;
      final stillOverSize = overSize && bytes > limitBytes;
      if (!stillOverCount && !stillOverSize) break;
      if (c.id != null) {
        await db.delete('caches', where: 'id = ?', whereArgs: [c.id]);
      }
      bytes -= c.size;
      count--;
    }
  }
}
