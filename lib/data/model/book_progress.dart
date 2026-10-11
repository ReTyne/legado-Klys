class BookProgress {
  int? id;
  String bookName;
  String author;
  int chapterIndex;
  int pagePos;
  int duration; // 阅读时长(毫秒)
  int lastReadTime;

  BookProgress({this.id, required this.bookName, required this.author, this.chapterIndex = 0, this.pagePos = 0, this.duration = 0, required this.lastReadTime});

  Map<String, dynamic> toMap() => {
    'id': id, 'bookName': bookName, 'author': author,
    'chapterIndex': chapterIndex, 'pagePos': pagePos,
    'duration': duration, 'lastReadTime': lastReadTime,
  };

  factory BookProgress.fromMap(Map<String, dynamic> map) => BookProgress(
    id: map['id'], bookName: map['bookName'] ?? '', author: map['author'] ?? '',
    chapterIndex: map['chapterIndex'] ?? 0, pagePos: map['pagePos'] ?? 0,
    duration: map['duration'] ?? 0, lastReadTime: map['lastReadTime'] ?? 0,
  );
}
