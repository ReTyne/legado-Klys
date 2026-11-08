/// 段评（对齐 Sigma ReviewColumn / BookChapterReview）
class BookReview {
  int? id;
  String bookName;
  String author;
  int chapterIndex;
  int paragraphIndex;
  String content;
  String? userName;
  int likes;
  int? createTime;

  BookReview({
    this.id,
    required this.bookName,
    this.author = '',
    required this.chapterIndex,
    required this.paragraphIndex,
    this.content = '',
    this.userName,
    this.likes = 0,
    int? createTime,
  }) : createTime = createTime ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toMap() => {
        'id': id,
        'bookName': bookName,
        'author': author,
        'chapterIndex': chapterIndex,
        'paragraphIndex': paragraphIndex,
        'content': content,
        'userName': userName,
        'likes': likes,
        'createTime': createTime,
      };

  factory BookReview.fromMap(Map<String, dynamic> m) => BookReview(
        id: m['id'],
        bookName: m['bookName'] ?? '',
        author: m['author'] ?? '',
        chapterIndex: m['chapterIndex'] ?? 0,
        paragraphIndex: m['paragraphIndex'] ?? 0,
        content: m['content'] ?? '',
        userName: m['userName'],
        likes: m['likes'] ?? 0,
        createTime: m['createTime'],
      );
}
