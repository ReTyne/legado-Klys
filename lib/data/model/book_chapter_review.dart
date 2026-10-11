class BookChapterReview {
  int? id;
  String bookName;
  String author;
  int chapterIndex;
  String chapterTitle;
  String? content;
  String? userName;
  int? likeCount;
  int createTime;

  BookChapterReview({this.id, required this.bookName, required this.author, required this.chapterIndex, required this.chapterTitle, this.content, this.userName, this.likeCount, required this.createTime});

  Map<String, dynamic> toMap() => {
    'id': id, 'bookName': bookName, 'author': author,
    'chapterIndex': chapterIndex, 'chapterTitle': chapterTitle,
    'content': content, 'userName': userName, 'likeCount': likeCount,
    'createTime': createTime,
  };

  factory BookChapterReview.fromMap(Map<String, dynamic> map) => BookChapterReview(
    id: map['id'], bookName: map['bookName'] ?? '', author: map['author'] ?? '',
    chapterIndex: map['chapterIndex'] ?? 0, chapterTitle: map['chapterTitle'] ?? '',
    content: map['content'], userName: map['userName'], likeCount: map['likeCount'],
    createTime: map['createTime'] ?? 0,
  );
}
