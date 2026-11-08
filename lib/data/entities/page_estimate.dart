/// 章节页数估算 / 全书索引（对齐 fork PageEstimate 思路）
class PageEstimate {
  int? id;
  String bookName;
  String author;
  int chapterIndex;
  int pageCount; // -1 未估算
  int mode; // 0 启发式 / 1 精确
  int? updateTime;

  PageEstimate({
    this.id,
    required this.bookName,
    this.author = '',
    required this.chapterIndex,
    this.pageCount = -1,
    this.mode = 0,
    this.updateTime,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'bookName': bookName,
        'author': author,
        'chapterIndex': chapterIndex,
        'pageCount': pageCount,
        'mode': mode,
        'updateTime': updateTime,
      };

  factory PageEstimate.fromMap(Map<String, dynamic> m) => PageEstimate(
        id: m['id'],
        bookName: m['bookName'] ?? '',
        author: m['author'] ?? '',
        chapterIndex: m['chapterIndex'] ?? 0,
        pageCount: m['pageCount'] ?? -1,
        mode: m['mode'] ?? 0,
        updateTime: m['updateTime'],
      );
}
