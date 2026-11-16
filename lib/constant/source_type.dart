/// 源类型常量。
///
/// 用于「先书源后订阅源」的统一入口与删除/启用分发：0 表示书源，1 表示 RSS 订阅源。
class SourceType {
  SourceType._();

  /// 书源（book_sources）。
  static const int book = 0;

  /// RSS 订阅源（rss_sources）。
  static const int rss = 1;
}
