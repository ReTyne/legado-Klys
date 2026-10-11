class BookChapter {
  String title;
  String url;
  int index;
  bool isVolume;
  String? content;
  int? startPos;
  int? endPos;
  String? variable;

  BookChapter({
    required this.title,
    required this.url,
    required this.index,
    this.isVolume = false,
    this.content,
    this.startPos,
    this.endPos,
    this.variable,
  });

  /// 传给书源 JS（ruleContent）的章节上下文。
  Map<String, dynamic> jsContext([String? bookUrl]) => {
    'index': index,
    'title': title,
    'url': url,
    'bookUrl': bookUrl ?? '',
    'isVolume': isVolume,
    'variable': variable,
  };

  /// 序列化为章节自身字段（Web 调试接口 / 导出用，不含书籍外键）
  Map<String, dynamic> toJson() => {
    'title': title,
    'url': url,
    'index': index,
    'isVolume': isVolume,
    'content': content,
    'startPos': startPos,
    'endPos': endPos,
    'variable': variable,
  };

  // 数据库列名（"index" 为 SQL 保留字，落库统一用 chapter_index）
  Map<String, dynamic> toMap(String bookName, String bookAuthor) => {
    'bookName': bookName,
    'bookAuthor': bookAuthor,
    'title': title,
    'url': url,
    'chapter_index': index,
    'isVolume': isVolume ? 1 : 0,
    'tag': null,
    'resourceUrl': null,
    'content': content,
    'start_pos': startPos,
    'end_pos': endPos,
    'variable': variable,
  };

  factory BookChapter.fromMap(Map<String, dynamic> map) => BookChapter(
    title: map['title'] as String,
    url: map['url'] as String,
    index: map['chapter_index'] as int? ?? map['index'] as int? ?? 0,
    isVolume: (map['isVolume'] as int? ?? 0) == 1,
    content: map['content'] as String?,
    startPos: map['start_pos'] as int? ?? map['start'] as int?,
    endPos: map['end_pos'] as int? ?? map['end'] as int?,
    variable: map['variable'] as String?,
  );
}
