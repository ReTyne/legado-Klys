import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:legado_md3/common/app_navigator.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/help/http/rss_service.dart';
import 'package:legado_md3/help/source/source_engine.dart';

/// 简易并发信号量（自实现，不引第三方并发库）。
/// 槽位在任务结束时直接转交给等待者，不会超发。
class _Semaphore {
  _Semaphore(int limit) : _limit = limit < 1 ? 1 : limit;

  final int _limit;
  int _running = 0;
  final List<Completer<void>> _queue = <Completer<void>>[];

  Future<T> run<T>(Future<T> Function() task) {
    if (_running < _limit) {
      _running++;
      return _execute(task);
    }
    final waiter = Completer<void>();
    _queue.add(waiter);
    // 槽位已在上一任务结束时转交，这里不再 _running++
    return waiter.future.then((_) => _execute(task));
  }

  Future<T> _execute<T>(Future<T> Function() task) async {
    try {
      return await task();
    } finally {
      if (_queue.isNotEmpty) {
        _queue.removeAt(0).complete();
      } else {
        _running--;
      }
    }
  }
}

/// 前台定时自动更新书架章节与 RSS 订阅（应用运行期间生效）
class AutoUpdateService {
  AutoUpdateService._();
  static final AutoUpdateService instance = AutoUpdateService._();

  // ===== 设置项 key（settings_screen / other_config_screen 写入）=====
  /// 只更新当前正在阅读/最近打开的书籍
  static const String keyOnlyUpdateRead = 'only_update_read';
  /// 全局禁用书籍更新（legado-E Book.canUpdate 语义）
  static const String keyBookUpdateDisable = 'bk_bookUpdateDisable';
  /// 更新并发线程数（legado-E 默认 32）
  static const String keyUpdateThreads = 'bk_updateThreads';
  /// 打开应用时自动检查应用更新
  static const String keyAutoCheckUpdate = 'oc_autoCheckUpdate';
  /// 更新通道（default_version / beta_version / none）
  static const String keyUpdateVariant = 'updateToVariant';

  static const _releasesApi = 'https://api.github.com/repos/ReTyne/legado-Klys/releases';
  static const _releasesPage = 'https://github.com/ReTyne/legado-Klys/releases';

  final DatabaseService _db = DatabaseService();
  final BookSourceEngine _engine = BookSourceEngine();
  Timer? _timer;
  DateTime? _lastRun;

  /// 启动周期任务。[onUpdated] 在有更新后回调（用于刷新书架）。
  Future<void> start({void Function(int updatedBooks)? onUpdated}) async {
    final prefs = await SharedPreferences.getInstance();

    // oc_autoCheckUpdate：打开应用时检查应用更新（独立于书籍自动更新开关）
    unawaited(checkAppUpdate());

    if (!(prefs.getBool('auto_update') ?? true)) return;

    // bk_bookUpdateDisable：全局禁用书籍更新，直接不跑
    if (prefs.getBool(keyBookUpdateDisable) ?? false) {
      _tip('更新已被禁用');
      return;
    }

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

  /// 启动时检查应用更新（oc_autoCheckUpdate + updateToVariant）。
  /// 版本对比使用 package_info_plus 的真实版本号，不再写死。
  static Future<void> checkAppUpdate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool(keyAutoCheckUpdate) ?? true)) return;
      final variant = prefs.getString(keyUpdateVariant) ?? 'default_version';
      if (variant == 'none') return;

      final info = await PackageInfo.fromPlatform();
      final current = _parseVersion(info.version);

      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 12),
      ));
      final resp = variant == 'beta_version'
          // 测试版通道：取最新一个 release（含预发布）
          ? await dio.get(_releasesApi)
          : await dio.get('$_releasesApi/latest');
      final data = resp.data;
      String tag = '';
      String htmlUrl = _releasesPage;
      if (data is Map) {
        tag = (data['tag_name'] ?? '').toString();
        htmlUrl = (data['html_url'] ?? _releasesPage).toString();
      } else if (data is List && data.isNotEmpty && data.first is Map) {
        final first = data.first as Map;
        tag = (first['tag_name'] ?? '').toString();
        htmlUrl = (first['html_url'] ?? _releasesPage).toString();
      }
      if (tag.isEmpty || !_hasNew(current, _parseVersion(tag))) return;
      _tip('发现新版本 $tag', actionLabel: '前往', onAction: () async {
        try {
          await launchUrl(Uri.parse(htmlUrl), mode: LaunchMode.externalApplication);
        } catch (_) {}
      });
    } catch (_) {}
  }

  static List<int> _parseVersion(String v) => v
      .replaceAll(RegExp(r'[^0-9.]'), '')
      .split('.')
      .map((e) => int.tryParse(e) ?? 0)
      .toList();

  static bool _hasNew(List<int> current, List<int> latest) {
    for (var i = 0; i < 3; i++) {
      final c = i < current.length ? current[i] : 0;
      final l = i < latest.length ? latest[i] : 0;
      if (l > c) return true;
      if (l < c) return false;
    }
    return false;
  }

  /// 无 BuildContext 的全局提示（启动/后台服务场景）。
  static void _tip(String message, {String? actionLabel, VoidCallback? onAction}) {
    final ctx = appNavigatorKey.currentContext;
    if (ctx == null) return;
    try {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text(message),
        action: actionLabel != null && onAction != null
            ? SnackBarAction(label: actionLabel, onPressed: onAction)
            : null,
      ));
    } catch (_) {}
  }

  Future<int> _run(void Function(int updatedBooks)? onUpdated) async {
    // 距上次不足 5 分钟则跳过，避免重复
    if (_lastRun != null && DateTime.now().difference(_lastRun!).inMinutes < 5) return 0;
    _lastRun = DateTime.now();

    final prefs = await SharedPreferences.getInstance();
    // bk_bookUpdateDisable：定时器启动后才打开开关时同样直接不跑
    if (prefs.getBool(keyBookUpdateDisable) ?? false) return 0;

    // bk_updateThreads：更新并发上限（legado-E 默认 32，上限 64 防异常值）
    final semaphore = _Semaphore((prefs.getInt(keyUpdateThreads) ?? 32).clamp(1, 64));
    // only_update_read：只更新当前正在阅读/最近打开的书
    final onlyUpdateRead = prefs.getBool(keyOnlyUpdateRead) ?? false;

    int updatedBooks = 0;
    try {
      final books = await _db.getAllBooks();
      final sources = await _db.getAllSources(enabled: true);
      final map = {for (final s in sources) s.bookSourceUrl: s};

      var targets = books
          .where((b) => !b.local && b.origin != null && b.noteUrl != null)
          .toList();
      if (onlyUpdateRead) {
        // 与书架「最近阅读」同口径（durChapterTime > 0 即打开过），优先更新最近阅读的
        targets = targets.where((b) => b.durChapterTime > 0).toList()
          ..sort((a, b) => b.durChapterTime.compareTo(a.durChapterTime));
      }

      final futures = <Future<bool>>[];
      for (final book in targets) {
        final source = map[book.origin];
        if (source == null) continue;
        futures.add(semaphore.run(() => _updateBook(book, source)));
      }
      updatedBooks = (await Future.wait(futures)).where((ok) => ok).length;

      // RSS 订阅刷新（与书籍更新共享同一并发上限）
      try {
        final rssSources = await _db.getRssSources();
        final rss = RssService();
        await Future.wait(rssSources
            .where((e) => e.enabled == true)
            .map((s) => semaphore.run(() async {
                  try {
                    final articles = await rss.fetchRss(s);
                    if (articles.isNotEmpty) await _db.saveRssArticles(articles);
                  } catch (_) {}
                })));
      } catch (_) {}
    } catch (_) {}
    if (updatedBooks > 0) onUpdated?.call(updatedBooks);
    return updatedBooks;
  }

  /// 更新单本书的目录；有新章节则落库并回写书籍信息。返回是否有更新。
  Future<bool> _updateBook(Book book, BookSource source) async {
    try {
      final newChapters = await _engine.getToc(source, book.noteUrl!);
      final old = await _db.getChapters(book.name, book.author);
      if (newChapters.length > old.length) {
        await _db.saveChapters(book.name, book.author, newChapters);
        book.lastChapter = newChapters.last.title;
        book.lastChapterIndex = newChapters.length - 1;
        book.latestChapterTime = DateTime.now().millisecondsSinceEpoch;
        await _db.updateBook(book);
        return true;
      }
    } catch (_) {}
    return false;
  }
}
