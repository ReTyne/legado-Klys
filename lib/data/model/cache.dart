class Cache {
  int? id;
  String bookName;
  String author;
  int chapterIndex;
  String chapterTitle;
  String? content;
  int size;
  int saveTime;

  Cache({this.id, required this.bookName, required this.author, required this.chapterIndex, required this.chapterTitle, this.content, this.size = 0, required this.saveTime});

  Map<String, dynamic> toMap() => {
    'id': id, 'bookName': bookName, 'author': author,
    'chapterIndex': chapterIndex, 'chapterTitle': chapterTitle,
    'content': content, 'size': size, 'saveTime': saveTime,
  };

  factory Cache.fromMap(Map<String, dynamic> map) => Cache(
    id: map['id'], bookName: map['bookName'] ?? '', author: map['author'] ?? '',
    chapterIndex: map['chapterIndex'] ?? 0, chapterTitle: map['chapterTitle'] ?? '',
    content: map['content'], size: map['size'] ?? 0, saveTime: map['saveTime'] ?? 0,
  );
}
