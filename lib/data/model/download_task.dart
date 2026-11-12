/// 离线缓存下载任务。
///
/// 活跃下载队列的实体：一本任务包含若干章节，按 chapterIndex 逐章缓存。
/// status: 0=等待 1=进行中 2=完成 3=失败 4=已暂停。
class DownloadTask {
  DownloadTask({
    this.id,
    required this.bookName,
    required this.author,
    this.startIndex = 0,
    this.endIndex = -1,
    this.currentIndex = 0,
    this.total = 0,
    this.done = 0,
    this.status = 0,
    this.error = '',
    this.createTime,
  });

  int? id;
  final String bookName;
  final String author;
  int startIndex;
  int endIndex;
  int currentIndex;
  int total;
  int done;
  int status;
  String error;
  int? createTime;

  double get progress => total <= 0 ? 0 : (done / total).clamp(0.0, 1.0);
  bool get active => status == 0 || status == 1;
  bool get finished => status == 2;

  static String statusName(int s) => switch (s) {
        1 => '下载中',
        2 => '已完成',
        3 => '失败',
        4 => '已暂停',
        _ => '等待中',
      };

  Map<String, dynamic> toMap() => {
        'id': id,
        'bookName': bookName,
        'author': author,
        'startIndex': startIndex,
        'endIndex': endIndex,
        'currentIndex': currentIndex,
        'total': total,
        'done': done,
        'status': status,
        'error': error,
        'createTime': createTime,
      };

  factory DownloadTask.fromMap(Map<String, dynamic> m) => DownloadTask(
        id: m['id'] as int?,
        bookName: (m['bookName'] ?? '') as String,
        author: (m['author'] ?? '') as String,
        startIndex: (m['startIndex'] ?? 0) as int,
        endIndex: (m['endIndex'] ?? -1) as int,
        currentIndex: (m['currentIndex'] ?? 0) as int,
        total: (m['total'] ?? 0) as int,
        done: (m['done'] ?? 0) as int,
        status: (m['status'] ?? 0) as int,
        error: (m['error'] ?? '') as String,
        createTime: m['createTime'] as int?,
      );
}
