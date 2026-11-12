import 'dart:convert';

/// 书籍划线 / 高亮。
///
/// 与书签（bookmarks）分离：记录选中文本范围（start/end）、颜色、批注，
/// 供目录页第 3 个「高亮」Tab 展示与跳转。
class BookHighlight {
  BookHighlight({
    this.id,
    required this.bookName,
    required this.author,
    this.chapterIndex = 0,
    this.chapterTitle = '',
    this.content = '',
    this.start = 0,
    this.end = 0,
    this.color = 0,
    this.note = '',
    this.createTime,
  });

  final int? id;
  final String bookName;
  final String author;
  int chapterIndex;
  String chapterTitle;
  String content;
  int start;
  int end;
  int color;
  String note;
  int? createTime;

  Map<String, dynamic> toMap() => {
        'id': id,
        'bookName': bookName,
        'author': author,
        'chapterIndex': chapterIndex,
        'chapterTitle': chapterTitle,
        'content': content,
        'start': start,
        'end': end,
        'color': color,
        'note': note,
        'createTime': createTime,
      };

  factory BookHighlight.fromMap(Map<String, dynamic> m) => BookHighlight(
        id: m['id'] as int?,
        bookName: (m['bookName'] ?? '') as String,
        author: (m['author'] ?? '') as String,
        chapterIndex: (m['chapterIndex'] ?? 0) as int,
        chapterTitle: (m['chapterTitle'] ?? '') as String,
        content: (m['content'] ?? '') as String,
        start: (m['start'] ?? 0) as int,
        end: (m['end'] ?? 0) as int,
        color: (m['color'] ?? 0) as int,
        note: (m['note'] ?? '') as String,
        createTime: m['createTime'] as int?,
      );

  String toJson() => jsonEncode(toMap());
  factory BookHighlight.fromJson(String s) =>
      BookHighlight.fromMap(jsonDecode(s) as Map<String, dynamic>);
}
