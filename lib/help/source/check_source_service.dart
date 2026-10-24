import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/help/config/app_config.dart';
import 'package:legado_md3/help/net/network_monitor.dart';
import 'package:legado_md3/help/source/source_engine.dart';

/// 目录为空（对照 legado-E exception/TocEmptyException.kt）
class TocEmptyException implements Exception {
  final String message;
  const TocEmptyException([this.message = '目录为空']);
  @override
  String toString() => 'TocEmptyException: $message';
}

/// 正文为空（对照 legado-E exception/ContentEmptyException.kt）
class ContentEmptyException implements Exception {
  final String message;
  const ContentEmptyException([this.message = '正文为空']);
  @override
  String toString() => 'ContentEmptyException: $message';
}

/// 书源校验配置（对照 legado-E model/CheckSource.kt，持久化走 AppPrefs）
class CheckSourceConfig {
  CheckSourceConfig._();

  /// 校验用关键字（E 默认「我的」）
  static String keyword = '我的';

  /// 单源校验总超时（毫秒）
  static int get timeout => AppPrefs.checkSourceTimeout;

  /// 校验失败时把错误信息写入书源注释
  static bool get wSourceComment => AppPrefs.wSourceComment;

  /// 检测源地址可访问性（Socket 探测）
  static bool get checkDomain => AppPrefs.checkDomain;

  /// 校验搜索（含搜索→详情→目录→正文链路）
  static bool get checkSearch => AppPrefs.checkSearch;

  /// 校验发现（含发现→详情→目录→正文链路）
  static bool get checkDiscovery => AppPrefs.checkDiscovery;

  /// 校验详情
  static bool get checkInfo => AppPrefs.checkInfo;

  /// 校验目录
  static bool get checkCategory => AppPrefs.checkCategory;

  /// 校验正文
  static bool get checkContent => AppPrefs.checkContent;

  /// 配置摘要（设置项副标题）
  static String get summary {
    final items = <String>[];
    if (checkDomain) items.add('源地址');
    if (checkSearch) items.add('搜索');
    if (checkDiscovery) items.add('发现');
    if (checkInfo) items.add('详情');
    if (checkCategory) items.add('目录');
    if (checkContent) items.add('正文');
    return '超时 ${timeout ~/ 1000} 秒，校验项：${items.join(' / ')}';
  }

  /// 取校验关键字：优先书源自带的纯文本关键字（E: BookSource.getCheckKeyword）
  static String checkKeywordOf(BookSource source) {
    String? pick(String? raw) {
      final t = raw?.trim() ?? '';
      if (t.isEmpty) return null;
      // E 的判定：含 http / :: / ++ / -- 视为规则片段而非关键字
      if (t.contains('http') || t.contains('::') ||
          t.contains('++') || t.contains('--')) {
        return null;
      }
      // Klys 顶层 checkKeyWord 兼作「关键字正则」，带正则特征的不当关键字用
      if (RegExp(r'[\\\[\](){}^$*+?|]').hasMatch(t)) return null;
      return t;
    }

    return pick(source.ruleSearch?['checkKeyWord']?.toString()) ??
        pick(source.checkKeyWord) ??
        keyword;
  }
}

/// 书源分组/注释操作（对照 legado-E data/entities/BookSource.kt）
extension BookSourceCheckExt on BookSource {
  static final RegExp _splitRegex = RegExp('[,;，；]');

  Set<String> get _groupSet => (bookSourceGroup ?? '')
      .split(_splitRegex)
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toSet();

  void _writeGroups(Set<String> set) {
    bookSourceGroup = set.isEmpty ? null : set.join(',');
  }

  /// 添加分组（逗号分隔可批量）
  void addGroup(String groups) {
    final set = _groupSet;
    set.addAll(groups.split(_splitRegex).map((e) => e.trim()).where((e) => e.isNotEmpty));
    _writeGroups(set);
  }

  /// 移除分组
  void removeGroup(String groups) {
    final set = _groupSet;
    set.removeAll(groups.split(_splitRegex).map((e) => e.trim()).where((e) => e.isNotEmpty));
    _writeGroups(set);
  }

  /// 失效分组名列表（含「失效」或「校验超时」）
  String getInvalidGroupNames() {
    return _groupSet.where((g) => g.contains('失效') || g == '校验超时').join(', ');
  }

  /// 清除全部失效分组
  void removeInvalidGroups() {
    final names = getInvalidGroupNames();
    if (names.isNotEmpty) removeGroup(names);
  }

  /// 清除注释中的错误信息行
  void removeErrorComment() {
    final c = bookSourceComment;
    if (c == null || c.isEmpty) return;
    final kept = c
        .split('\n\n')
        .where((block) => !block.startsWith('// Error: '))
        .join('\n');
    bookSourceComment = kept.isEmpty ? null : kept;
  }

  /// 追加错误信息到注释（E: addErrorComment）
  void addErrorComment(String message) {
    final err = '// Error: $message';
    bookSourceComment =
        (bookSourceComment == null || bookSourceComment!.trim().isEmpty)
            ? err
            : '$err\n\n$bookSourceComment';
  }
}

/// 校验进度
class CheckProgress {
  final int done;
  final int total;
  final String currentName;
  final int validCount;
  final int invalidCount;
  final CheckResult? lastResult;
  final bool finished;

  const CheckProgress({
    required this.done,
    required this.total,
    this.currentName = '',
    this.validCount = 0,
    this.invalidCount = 0,
    this.lastResult,
    this.finished = false,
  });
}

/// 单源校验结果
class CheckResult {
  final String sourceUrl;
  final String sourceName;
  final bool success;
  /// 失效分组（E: getInvalidGroupNames），空 = 全部通过
  final String invalidGroups;
  final String? errorMessage;
  final int respondTime;

  const CheckResult({
    required this.sourceUrl,
    required this.sourceName,
    required this.success,
    this.invalidGroups = '',
    this.errorMessage,
    this.respondTime = 0,
  });
}

/// 批量校验汇总
class CheckSummary {
  final int total;
  final int valid;
  final int invalid;
  final bool canceled;
  final int elapsedMs;

  /// 未开始校验即整体失败的原因（如「网络不可用」），为空表示正常完成
  final String errorMessage;

  const CheckSummary({
    required this.total,
    required this.valid,
    required this.invalid,
    this.canceled = false,
    this.elapsedMs = 0,
    this.errorMessage = '',
  });
}

/// 书源校验服务（对照 legado-E service/CheckSourceService.kt）
///
/// 流程（doCheckSource）：
///  1. 清除历史失效分组/错误注释
///  2. checkDomain：源地址 Socket 可达性 → 域名失效
///  3. checkSearch：搜索 → 空则「搜索链接规则为空」；无结果「搜索失效」；
///     有结果则对第一本书走 checkBook(搜索)
///  4. checkDiscovery：第一个发现分类 → 空则「发现规则为空」；无结果「发现失效」；
///     有结果则对第一本书走 checkBook(发现)
///  5. 仍有失效分组则整体判失败
/// checkBook：详情（缺 tocUrl 时补拉）→ 目录（取前 2 章）→ 正文（首章 + 下一页地址），
///  失败分别记「搜索|发现目录失效」「搜索|发现正文失效」。
/// 单源整体超时记「校验超时」，JS 异常记「js失效」，其他异常记「网站失效」。
class CheckSourceService {
  CheckSourceService({DatabaseService? db, BookSourceEngine? engine})
      : _db = db ?? DatabaseService(),
        _engine = engine ?? BookSourceEngine();

  final DatabaseService _db;
  final BookSourceEngine _engine;

  bool _running = false;
  bool get isRunning => _running;
  bool _canceled = false;

  final StreamController<CheckProgress> _progressCtrl =
      StreamController<CheckProgress>.broadcast();
  Stream<CheckProgress> get progressStream => _progressCtrl.stream;

  /// 取消本次批量校验（已发出的单源校验会跑完当前步骤）
  void cancel() => _canceled = true;

  void _emit(CheckProgress p) {
    if (!_progressCtrl.isClosed) _progressCtrl.add(p);
  }

  Future<void> dispose() async {
    await _progressCtrl.close();
  }

  /// 批量校验（并发 = min(threadCount, 9)，对齐 E 的 MAX_THREAD 上限）
  /// 离线时快速失败（E: NetworkUtils.isAvailable 守卫），避免逐源干等超时。
  Future<CheckSummary> start(List<BookSource> sources, {int? threadCount}) async {
    if (sources.isEmpty) {
      return const CheckSummary(total: 0, valid: 0, invalid: 0);
    }
    if (_running) {
      return CheckSummary(total: sources.length, valid: 0, invalid: 0, canceled: true);
    }
    if (!await NetworkMonitor.instance.isOnline) {
      return CheckSummary(
        total: sources.length,
        valid: 0,
        invalid: sources.length,
        canceled: false,
        errorMessage: '网络不可用，请检查网络后重试',
      );
    }
    _running = true;
    _canceled = false;
    final sw = Stopwatch()..start();
    var done = 0, valid = 0, invalid = 0;
    final concurrency =
        min(max(threadCount ?? AppPrefs.threadCount, 1), 9).clamp(1, sources.length);
    var cursor = 0;

    Future<void> worker() async {
      while (cursor < sources.length) {
        if (_canceled) return;
        final source = sources[cursor++];
        final result = await checkOne(source);
        // 每完成一本立即落库（对齐 E 的 onEach { update }）
        try {
          await _db.updateSource(source);
        } catch (_) {}
        done++;
        if (result.success) {
          valid++;
        } else {
          invalid++;
        }
        _emit(CheckProgress(
          done: done,
          total: sources.length,
          currentName: source.bookSourceName,
          validCount: valid,
          invalidCount: invalid,
          lastResult: result,
        ));
      }
    }

    await Future.wait(List.generate(concurrency, (_) => worker()));
    sw.stop();
    _running = false;
    _emit(CheckProgress(
      done: done,
      total: sources.length,
      validCount: valid,
      invalidCount: invalid,
      finished: true,
    ));
    return CheckSummary(
      total: sources.length,
      valid: valid,
      invalid: invalid,
      canceled: _canceled,
      elapsedMs: sw.elapsedMilliseconds,
    );
  }

  /// 校验单个书源（写失效分组 / 错误注释 / respondTime，不落库）
  Future<CheckResult> checkOne(BookSource source) async {
    final sw = Stopwatch()..start();
    String? errorMessage;
    var success = false;
    try {
      await _doCheckSource(source)
          .timeout(Duration(milliseconds: CheckSourceConfig.timeout));
      success = true;
    } on TimeoutException {
      source.addGroup('校验超时');
      errorMessage = '校验超时';
    } catch (e) {
      if (_looksJsError(e)) {
        source.addGroup('js失效');
        errorMessage = 'js失效: $e';
      } else {
        source.addGroup('网站失效');
        errorMessage = e.toString();
      }
      if (CheckSourceConfig.wSourceComment) {
        source.addErrorComment(errorMessage);
      }
    }
    sw.stop();
    source.respondTime = sw.elapsedMilliseconds;
    return CheckResult(
      sourceUrl: source.bookSourceUrl,
      sourceName: source.bookSourceName,
      success: success,
      invalidGroups: source.getInvalidGroupNames(),
      errorMessage: errorMessage,
      respondTime: sw.elapsedMilliseconds,
    );
  }

  /// JS 运行时类错误（Klys 的迷你求值器/无头 WebView 求值失败）
  bool _looksJsError(Object e) {
    final s = e.toString();
    return s.contains('JS') ||
        s.contains('js') && s.contains('脚本') ||
        s.contains('Script') ||
        s.contains('求值') ||
        s.contains('evaluateJavascript');
  }

  /// 源地址可访问性（E: isDomainReachable，Socket 连接 1600ms 超时）
  Future<bool> isDomainReachable(String domain) async {
    try {
      final uri = Uri.parse(domain.split('#').first);
      if (uri.host.isEmpty) return false;
      final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
      final socket = await Socket.connect(uri.host, port,
          timeout: const Duration(milliseconds: 1600));
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 七项校验主流程（E: doCheckSource）
  Future<void> _doCheckSource(BookSource source) async {
    source.removeInvalidGroups();
    if (CheckSourceConfig.wSourceComment) {
      source.removeErrorComment();
    }
    // 1. 源地址可访问性
    if (CheckSourceConfig.checkDomain) {
      final domain = source.bookSourceUrl;
      if (!domain.toLowerCase().startsWith('http')) {
        throw Exception('源地址不是http链接');
      }
      if (await isDomainReachable(domain)) {
        source.removeGroup('域名失效');
      } else {
        source.addGroup('域名失效');
        throw Exception('源地址不可访问');
      }
    }
    // 2. 校验搜索
    if (CheckSourceConfig.checkSearch) {
      final searchWord = CheckSourceConfig.checkKeywordOf(source);
      final searchUrl = source.searchUrl?.trim() ?? '';
      if (searchUrl.isEmpty) {
        source.addGroup('搜索链接规则为空');
      } else {
        source.removeGroup('搜索链接规则为空');
        final books = await _engine.search(source, searchWord);
        if (books.isEmpty) {
          source.addGroup('搜索失效');
        } else {
          source.removeGroup('搜索失效');
          await _checkBook(source, books.first.toBook(), isSearchBook: true);
        }
      }
    }
    // 3. 校验发现
    if (CheckSourceConfig.checkDiscovery &&
        (source.exploreUrl?.trim() ?? '').isNotEmpty) {
      final kinds = await _engine.getExploreKindsAsync(source);
      final url = kinds
          .map((k) => k['url'] ?? '')
          .firstWhere((u) => u.trim().isNotEmpty, orElse: () => '');
      if (url.trim().isEmpty) {
        source.addGroup('发现规则为空');
      } else {
        source.removeGroup('发现规则为空');
        final books = await _engine.exploreByUrl(source, url);
        if (books.isEmpty) {
          source.addGroup('发现失效');
        } else {
          source.removeGroup('发现失效');
          await _checkBook(source, books.first.toBook(), isSearchBook: false);
        }
      }
    }
    final finalCheckMessage = source.getInvalidGroupNames();
    if (finalCheckMessage.isNotEmpty) {
      throw Exception(finalCheckMessage);
    }
  }

  /// 校验详情→目录→正文（E: checkBook）
  Future<void> _checkBook(BookSource source, Book book,
      {required bool isSearchBook}) async {
    final bookType = isSearchBook ? '搜索' : '发现';
    try {
      if (!CheckSourceConfig.checkInfo) return;
      // 详情：缺目录地址时补拉
      if ((book.noteUrl ?? '').trim().isEmpty) {
        final info = await _engine.getBookInfo(source, book.bookUrl ?? '');
        if (info == null) {
          throw Exception('详情获取失败');
        }
        book = info;
      }
      if (!CheckSourceConfig.checkCategory || source.bookSourceType == 3) {
        return; // 文件源不校验目录/正文
      }
      // 目录：过滤卷标，取前 2 章（E 取第 2 章作为 nextChapterUrl 传入正文上下文，
      // Klys 逐章独立获取正文，无需该参数）
      final toc = await _engine.getToc(source, book.noteUrl!,
          bookInfo: book.jsContext());
      final chapters = toc
          .where((c) => !(c.isVolume && c.url.startsWith(c.title)))
          .take(2)
          .toList();
      if (chapters.isEmpty) {
        throw const TocEmptyException();
      }
      if (!CheckSourceConfig.checkContent) return;
      // 正文：首章 + 下一页地址
      final content = await _engine.getContent(
        source,
        chapters[0].url,
        bookInfo: book.jsContext(),
        chapter: {
          'index': chapters[0].index,
          'title': chapters[0].title,
          'url': chapters[0].url,
          'bookUrl': book.bookUrl ?? '',
        },
      );
      if (content == null || content.trim().isEmpty) {
        throw const ContentEmptyException();
      }
    } catch (e) {
      if (e is ContentEmptyException) {
        source.addGroup('${bookType}正文失效');
      } else if (e is TocEmptyException) {
        source.addGroup('${bookType}目录失效');
      } else {
        rethrow;
      }
      return;
    }
    source.removeGroup('${bookType}目录失效');
    source.removeGroup('${bookType}正文失效');
  }
}
