class ReadRecord {
  int? id;
  String bookName;
  String author;
  int duration; // 阅读时长(毫秒)
  int date; // 日期时间戳
  int? chapterIndex;
  int? pagePos;

  ReadRecord({this.id, required this.bookName, required this.author, this.duration = 0, required this.date, this.chapterIndex, this.pagePos});

  Map<String, dynamic> toMap() => {
    'id': id, 'bookName': bookName, 'author': author,
    'duration': duration, 'date': date, 'chapterIndex': chapterIndex, 'pagePos': pagePos,
  };

  factory ReadRecord.fromMap(Map<String, dynamic> map) => ReadRecord(
    id: map['id'], bookName: map['bookName'] ?? '', author: map['author'] ?? '',
    duration: map['duration'] ?? 0, date: map['date'] ?? 0,
    chapterIndex: map['chapterIndex'], pagePos: map['pagePos'],
  );
}
