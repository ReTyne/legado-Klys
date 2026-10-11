import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/help/source/source_engine.dart';
import 'package:legado_md3/help/http/rss_service.dart';

/// 前台定时自动更新书架章节与 RSS 订阅（应用运行期间生效）
class AutoUpdateService {
  AutoUpdateService._();
  static final AutoUpdateService instance = AutoUpdateService._();

  final DatabaseService _db = DatabaseService();
  final BookSourceEngine _engine = BookSourceEngine();
  Timer? _timer;
  DateTime? _lastRun;

  /// 启动周期任务。[onUpdated] 在有更新后回调（用于刷新书架）。
  Future<void> start({void Function(int updatedBooks)? onUpdated}) async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('auto_update') ?? true;
    if (!enabled) return;
    final hours = prefs.getInt('auto_update_hours') ?? 6;
    final interval = Duration(minutes: hours < 1 ? 30 : hours * 60);

    stop();
    // 启动 30 秒后做一次（避免与进页加载抢占），之后按周期
    Timer(const Duration(seconds: 30), () => _run(onUpdated));
    _timer = Timer.periodic(interval, (_) => _run(onUpdated));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<int> _run(void Function(int updatedBooks)? onUpdated) async {
    // 距上次不足 5 分钟则跳过，避免重复
    if (_lastRun != null && DateTime.now().difference(_lastRun!).inMinutes < 5) return 0;
    _lastRun = DateTime.now();
    int updatedBooks = 0;
    try {
      final books = await _db.getAllBooks();
      final sources = await _db.getAllSources(enabled: true);
      final map = {for (final s in sources) s.bookSourceUrl: s};
      for (final book in books) {
        if (book.local || book.origin == null || book.noteUrl == null) continue;
        final source = map[book.origin];
        if (source == null) continue;
        try {
          final newChapters = await _engine.getToc(source, book.noteUrl!);
          final old = await _db.getChapters(book.name, book.author);
          if (newChapters.length > old.length) {
            await _db.saveChapters(book.name, book.author, newChapters);
            book.lastChapter = newChapters.last.title;
            book.lastChapterIndex = newChapters.length - 1;
            book.latestChapterTime = DateTime.now().millisecondsSinceEpoch;
            await _db.updateBook(book);
            updatedBooks++;
          }
        } catch (_) {}
      }
      // RSS 订阅刷新
      try {
        final rssSources = await _db.getRssSources();
        final rss = RssService();
        for (final s in rssSources.where((e) => e.enabled == true)) {
          try {
            final articles = await rss.fetchRss(s);
            if (articles.isNotEmpty) await _db.saveRssArticles(articles);
          } catch (_) {}
        }
      } catch (_) {}
    } catch (_) {}
    if (updatedBooks > 0) onUpdated?.call(updatedBooks);
    return updatedBooks;
  }
}
