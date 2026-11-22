int? _bmInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString().trim());
}

class Bookmark {
  int? id;
  String bookName;
  String bookAuthor;
  int chapterIndex;
  String chapterTitle;
  int pageIndex;
  String? content;

  /// 书签所在位置的原文片段，供跨端备份互通。
  String? bookText;
  int createTime;

  Bookmark({
    this.id,
    required this.bookName,
    required this.bookAuthor,
    required this.chapterIndex,
    required this.chapterTitle,
    this.pageIndex = 0,
    this.content,
    this.bookText,
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
        'bookText': bookText,
        'createTime': createTime,
      };

  factory Bookmark.fromMap(Map<String, dynamic> map) => Bookmark(
        id: _bmInt(map['id']),
        bookName: (map['bookName'] ?? map['book_title'] ?? '').toString(),
        bookAuthor: (map['bookAuthor'] ?? map['author'] ?? '').toString(),
        chapterIndex: _bmInt(map['chapterIndex'] ?? map['chapterPos']) ?? 0,
        chapterTitle: (map['chapterTitle'] ?? map['chapterName'] ?? '').toString(),
        pageIndex: _bmInt(map['pageIndex'] ?? map['pagePos']) ?? 0,
        content: map['content']?.toString(),
        bookText: map['bookText']?.toString(),
        createTime: _bmInt(map['createTime'] ?? map['time']),
      );
}
