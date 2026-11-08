class BookMarking {
  int? id;
  String bookName;
  String author;
  int chapterIndex;
  String chapterTitle;
  int pagePos;
  String content;
  String? note;
  int? color;
  int createTime;

  BookMarking({this.id, required this.bookName, required this.author, required this.chapterIndex, required this.chapterTitle, this.pagePos = 0, required this.content, this.note, this.color, required this.createTime});

  Map<String, dynamic> toMap() => {
    'id': id, 'bookName': bookName, 'author': author,
    'chapterIndex': chapterIndex, 'chapterTitle': chapterTitle,
    'pagePos': pagePos, 'content': content, 'note': note,
    'color': color, 'createTime': createTime,
  };

  factory BookMarking.fromMap(Map<String, dynamic> map) => BookMarking(
    id: map['id'], bookName: map['bookName'] ?? '', author: map['author'] ?? '',
    chapterIndex: map['chapterIndex'] ?? 0, chapterTitle: map['chapterTitle'] ?? '',
    pagePos: map['pagePos'] ?? 0, content: map['content'] ?? '',
    note: map['note'], color: map['color'], createTime: map['createTime'] ?? 0,
  );
}
