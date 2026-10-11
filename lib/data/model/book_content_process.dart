class BookContentProcess {
  int? id;
  String bookName;
  String author;
  int chapterIndex;
  String? content;
  int processTime;

  BookContentProcess({this.id, required this.bookName, required this.author, required this.chapterIndex, this.content, required this.processTime});

  Map<String, dynamic> toMap() => {
    'id': id, 'bookName': bookName, 'author': author,
    'chapterIndex': chapterIndex, 'content': content, 'processTime': processTime,
  };

  factory BookContentProcess.fromMap(Map<String, dynamic> map) => BookContentProcess(
    id: map['id'], bookName: map['bookName'] ?? '', author: map['author'] ?? '',
    chapterIndex: map['chapterIndex'] ?? 0, content: map['content'],
    processTime: map['processTime'] ?? 0,
  );
}
