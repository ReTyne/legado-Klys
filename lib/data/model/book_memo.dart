/// 书籍备忘（对齐 legado 官方原版 BookMemo / BookMemoDialog）。
///
/// 阅读菜单「备忘」按钮写入，按书 + 章聚合，可在目录/详情查看。
class BookMemo {
  BookMemo({
    this.id,
    required this.bookName,
    required this.author,
    this.chapterIndex = 0,
    this.chapterTitle = '',
    this.content = '',
    this.createTime,
    this.updateTime,
  });

  final int? id;
  final String bookName;
  final String author;
  int chapterIndex;
  String chapterTitle;
  String content;
  int? createTime;
  int? updateTime;

  Map<String, dynamic> toMap() => {
        'id': id,
        'bookName': bookName,
        'author': author,
        'chapterIndex': chapterIndex,
        'chapterTitle': chapterTitle,
        'content': content,
        'createTime': createTime,
        'updateTime': updateTime,
      };

  factory BookMemo.fromMap(Map<String, dynamic> m) => BookMemo(
        id: m['id'] as int?,
        bookName: (m['bookName'] ?? '') as String,
        author: (m['author'] ?? '') as String,
        chapterIndex: (m['chapterIndex'] ?? 0) as int,
        chapterTitle: (m['chapterTitle'] ?? '') as String,
        content: (m['content'] ?? '') as String,
        createTime: m['createTime'] as int?,
        updateTime: m['updateTime'] as int?,
      );
}
