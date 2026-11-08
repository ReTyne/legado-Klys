/// 弹幕文件缓存索引（对齐 Sigma RuleBigDataHelp.getDanmakuFile 三级 MD5 路径）
class DanmakuCache {
  int? id;
  String bookUrl;
  String chapterUrl;
  String filePath;
  int count;
  int? updateTime;

  DanmakuCache({
    this.id,
    required this.bookUrl,
    required this.chapterUrl,
    required this.filePath,
    this.count = 0,
    int? updateTime,
  }) : updateTime = updateTime ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toMap() => {
        'id': id,
        'bookUrl': bookUrl,
        'chapterUrl': chapterUrl,
        'filePath': filePath,
        'count': count,
        'updateTime': updateTime,
      };

  factory DanmakuCache.fromMap(Map<String, dynamic> m) => DanmakuCache(
        id: m['id'],
        bookUrl: m['bookUrl'] ?? '',
        chapterUrl: m['chapterUrl'] ?? '',
        filePath: m['filePath'] ?? '',
        count: m['count'] ?? 0,
        updateTime: m['updateTime'],
      );
}
