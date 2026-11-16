/// 由 change_source_screen.dart 按「一类一文件」拆出的 _SourceResult。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../change_source_screen.dart';

class _SourceResult {
  BookSource source;
  SearchBook? match;
  bool searching = true;
  String? error;

  /// 匹配质量评分：同名同作者 100 / 同名 80 / 首条兜底 50 / 未命中 0。
  int score = 0;

  /// 搜索耗时（毫秒），按响应时间排序时使用。
  int? responseMs;

  /// 目录预览与目录字数统计的缓存。
  List<BookChapter>? toc;
  int? chapterCount;
  int? tocWordCount;

  /// 置顶 / 置底：-1 置顶，0 默认，1 置底。
  int pin = 0;

  _SourceResult(this.source);
}
