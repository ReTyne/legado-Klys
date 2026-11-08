/// RSS 阅读记录（对齐 legado 官方原版 / 阅读Sigma 的 RssReadRecord）。
///
/// 与 rss_articles.isRead 布尔标记不同：这里记录每篇文章的**滚动位置**与
/// 阅读进度，用于「续读」和历史列表。以 link 为唯一键。
class RssReadRecord {
  RssReadRecord({
    this.id,
    required this.link,
    this.title = '',
    this.sourceUrl = '',
    this.durPos = 0,
    this.readTime,
    this.enabled = 1,
  });

  final int? id;
  final String link;
  String title;
  String sourceUrl;

  /// 上次滚动位置（像素或 0..1 进度，视阅读页实现而定）。
  double durPos;
  int? readTime;

  /// 是否开启记录（对齐原版 ReadRecordDialog 的「开启记录」开关）。
  int enabled;

  Map<String, dynamic> toMap() => {
        'id': id,
        'link': link,
        'title': title,
        'sourceUrl': sourceUrl,
        'durPos': durPos,
        'readTime': readTime,
        'enabled': enabled,
      };

  factory RssReadRecord.fromMap(Map<String, dynamic> m) => RssReadRecord(
        id: m['id'] as int?,
        link: (m['link'] ?? '') as String,
        title: (m['title'] ?? '') as String,
        sourceUrl: (m['sourceUrl'] ?? '') as String,
        durPos: (m['durPos'] ?? 0) is int
            ? (m['durPos'] as int).toDouble()
            : (m['durPos'] ?? 0.0) as double,
        readTime: m['readTime'] as int?,
        enabled: (m['enabled'] ?? 1) as int,
      );
}
