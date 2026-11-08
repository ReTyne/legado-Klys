import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/v14_models.dart';

/// 全书页数索引（对齐 fork `WholeBookPageIndex` / `PageEstimateCalibrationStore`）。
///
/// 以 v14 `page_estimates` 表为持久层：每章页数估算后落库，汇总出全书页数，
/// 并把「按章节数均分」的粗略进度校准成「按页数」的真实进度。
class WholeBookPageIndex {
  final String bookName;
  final String author;
  final int chapterCount;
  final DatabaseService _db = DatabaseService();

  /// chapterIndex -> 估算结果
  final Map<int, PageEstimate> _estimates = {};

  /// 未估算章节采用的默认页数（缺省 8 页，随已有估算的均值更新）
  int _fallbackPages = 8;

  WholeBookPageIndex({
    required this.bookName,
    required this.author,
    required this.chapterCount,
  });

  static Future<WholeBookPageIndex> load(
    String bookName,
    String author,
    int chapterCount,
  ) async {
    final index = WholeBookPageIndex(
      bookName: bookName,
      author: author,
      chapterCount: chapterCount,
    );
    final list =
        await DatabaseService().getPageEstimates(bookName, author);
    for (final e in list) {
      if (e.pageCount > 0) index._estimates[e.chapterIndex] = e;
    }
    index._recomputeFallback();
    return index;
  }

  void _recomputeFallback() {
    if (_estimates.isEmpty) return;
    final sum = _estimates.values.fold<int>(0, (s, e) => s + e.pageCount);
    _fallbackPages = (sum / _estimates.length).round().clamp(1, 2000);
  }

  int pagesOf(int chapterIndex) =>
      _estimates[chapterIndex]?.pageCount ?? _fallbackPages;

  int modeOf(int chapterIndex) => _estimates[chapterIndex]?.mode ?? 0;

  /// 全书估算总页数：已估算章用真实值，未估算章用均值补齐。
  int get wholeBookPages {
    if (chapterCount <= 0) return _fallbackPages;
    var total = 0;
    for (var i = 0; i < chapterCount; i++) {
      total += pagesOf(i);
    }
    return total.clamp(1, 1 << 30);
  }

  /// 第 [chapterIndex] 章之前的总页数（用于进度校准）
  int pagesBeforeChapter(int chapterIndex) {
    var total = 0;
    final end = chapterIndex.clamp(0, chapterCount);
    for (var i = 0; i < end; i++) {
      total += pagesOf(i);
    }
    return total;
  }

  /// 按页数校准的全书进度（0~1）。
  /// [pageInChapter] 为章内当前页（0 起始）。
  double calibratedProgress(int chapterIndex, int pageInChapter) {
    final total = wholeBookPages;
    if (total <= 0) return 0;
    final before = pagesBeforeChapter(chapterIndex);
    final within = pageInChapter.clamp(0, pagesOf(chapterIndex));
    return ((before + within) / total).clamp(0.0, 1.0);
  }

  /// 落库一章估算结果并更新内存索引。
  Future<void> updateChapter(int chapterIndex, int pageCount, int mode) async {
    final e = PageEstimate(
      bookName: bookName,
      author: author,
      chapterIndex: chapterIndex,
      pageCount: pageCount,
      mode: mode,
      updateTime: DateTime.now().millisecondsSinceEpoch,
    );
    await _db.upsertPageEstimate(e);
    _estimates[chapterIndex] = e;
    _recomputeFallback();
  }

  /// 清空本书估算（换源 / 重新分页时调用）。
  Future<void> clear() async {
    await _db.clearPageEstimates(bookName, author);
    _estimates.clear();
    _fallbackPages = 8;
  }

  /// 「本章 X 页 / 全书约 Y 页」摘要文本。
  String summary(int chapterIndex) {
    final chapterPages = pagesOf(chapterIndex);
    final bookPages = wholeBookPages;
    final exact = _estimates.containsKey(chapterIndex)
        ? (_estimates[chapterIndex]!.mode == 1 ? '精确' : '估算')
        : '估算';
    return '本章 $chapterPages 页（$exact） / 全书约 $bookPages 页';
  }
}
