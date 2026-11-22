int? _rrInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString().trim());
}

class ReadRecord {
  int? id;
  String bookName;
  String author;
  int duration; // 阅读时长(毫秒)
  int date; // 日期时间戳
  int? chapterIndex;
  int? pagePos;

  /// 跨设备阅读进度字段。
  String? deviceId;
  int? readTime;
  int? lastRead;

  ReadRecord({
    this.id,
    required this.bookName,
    required this.author,
    this.duration = 0,
    required this.date,
    this.chapterIndex,
    this.pagePos,
    this.deviceId,
    this.readTime,
    this.lastRead,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'bookName': bookName,
    'author': author,
    'duration': duration,
    'date': date,
    'chapterIndex': chapterIndex,
    'pagePos': pagePos,
    'deviceId': deviceId,
    'readTime': readTime,
    'lastRead': lastRead,
  };

  factory ReadRecord.fromMap(Map<String, dynamic> map) => ReadRecord(
    id: _rrInt(map['id']),
    bookName: (map['bookName'] ?? '').toString(),
    author: (map['author'] ?? '').toString(),
    duration: _rrInt(map['duration']) ?? 0,
    date: _rrInt(map['date'] ?? map['readTime']) ?? 0,
    chapterIndex: _rrInt(map['chapterIndex']),
    pagePos: _rrInt(map['pagePos'] ?? map['durPos']),
    deviceId: map['deviceId']?.toString(),
    readTime: _rrInt(map['readTime']),
    lastRead: _rrInt(map['lastRead']),
  );
}
