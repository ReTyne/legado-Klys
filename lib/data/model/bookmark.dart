class Bookmark {
  int? id;
  String bookName;
  String bookAuthor;
  int chapterIndex;
  String chapterTitle;
  int pageIndex;
  String? content;
  int createTime;

  Bookmark({
    this.id,
    required this.bookName,
    required this.bookAuthor,
    required this.chapterIndex,
    required this.chapterTitle,
    this.pageIndex = 0,
    this.content,
    int? createTime,
  }) : createTime = createTime ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toMap() => {
        'id': id,
        'bookName': bookName,
        'bookAuthor': bookAuthor,
        'chapterIndex': chapterIndex,
        'chapterTitle': chapterTitle,
        'pageIndex': pageIndex,
        'content': content,
        'createTime': createTime,
      };

  factory Bookmark.fromMap(Map<String, dynamic> map) => Bookmark(
        id: map['id'] as int?,
        bookName: map['bookName'] as String,
        bookAuthor: map['bookAuthor'] as String,
        chapterIndex: map['chapterIndex'] as int,
        chapterTitle: map['chapterTitle'] as String,
        pageIndex: map['pageIndex'] as int? ?? 0,
        content: map['content'] as String?,
        createTime: map['createTime'] as int,
      );
}
