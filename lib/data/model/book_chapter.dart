int? _chInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString().trim());
}

bool _chFlag(dynamic v, bool fallback) {
  if (v == null) return fallback;
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = v.toString().trim().toLowerCase();
  if (s == 'true' || s == '1') return true;
  if (s == 'false' || s == '0') return false;
  return fallback;
}

class BookChapter {
  String title;
  String url;
  int index;
  bool isVolume;
  bool isVip;
  bool isPay;
  String? updateTime;
  String? content;
  int? startPos;
  int? endPos;
  String? variable;
  int? wordCount;

  /// 正文分片定位与插图地址，供分页与资源加载使用。
  String? startFragmentId;
  String? endFragmentId;
  String? imgUrl;
  String? titleMD5;

  /// 章节所属目录页地址（书源规则解析出的 baseUrl），落库列 baseUrl。
  String? baseUrl;

  /// 章节标签（如「VIP」「精校」），落库列 tag，供书源 JS `chapter.tag` 读取。
  String? tag;

  /// 章节资源直链（音频/视频/图片书源），落库列 resourceUrl。
  /// JS 桥 __wrapChapter.getResourceUrl() 依赖该字段。
  String? resourceUrl;

  BookChapter({
    required this.title,
    required this.url,
    required this.index,
    this.isVolume = false,
    this.isVip = false,
    this.isPay = false,
    this.updateTime,
    this.content,
    this.startPos,
    this.endPos,
    this.variable,
    this.wordCount,
    this.startFragmentId,
    this.endFragmentId,
    this.imgUrl,
    this.titleMD5,
    this.baseUrl,
    this.tag,
    this.resourceUrl,
  });

  /// 传给书源 JS（ruleContent）的章节上下文。
  /// 键名与 JS 桥 __wrapChapter 的 getter 一一对应。
  Map<String, dynamic> jsContext([String? bookUrl]) => {
    'index': index,
    'title': title,
    'url': url,
    'bookUrl': bookUrl ?? '',
    'baseUrl': baseUrl ?? '',
    'isVolume': isVolume,
    'isVip': isVip,
    'isPay': isPay,
    'updateTime': updateTime,
    'tag': tag ?? '',
    'resourceUrl': resourceUrl ?? '',
    'variable': variable,
  };

  /// 序列化为章节自身字段（Web 调试接口 / 导出用，不含书籍外键）
  Map<String, dynamic> toJson() => {
    'title': title,
    'url': url,
    'index': index,
    'isVolume': isVolume,
    'isVip': isVip,
    'isPay': isPay,
    'updateTime': updateTime,
    'content': content,
    'startPos': startPos,
    'endPos': endPos,
    'variable': variable,
    'wordCount': wordCount,
    'startFragmentId': startFragmentId,
    'endFragmentId': endFragmentId,
    'imgUrl': imgUrl,
    'titleMD5': titleMD5,
    'baseUrl': baseUrl,
    'tag': tag,
    'resourceUrl': resourceUrl,
  };

  // 数据库列名（"index" 为 SQL 保留字，落库统一用 chapter_index）
  Map<String, dynamic> toMap(String bookName, String bookAuthor) => {
    'bookName': bookName,
    'bookAuthor': bookAuthor,
    'title': title,
    'url': url,
    'chapter_index': index,
    'baseUrl': baseUrl,
    'isVolume': isVolume ? 1 : 0,
    'isVip': isVip ? 1 : 0,
    'isPay': isPay ? 1 : 0,
    'update_time': updateTime,
    'tag': tag,
    'resourceUrl': resourceUrl,
    'content': content,
    'start_pos': startPos,
    'end_pos': endPos,
    'variable': variable,
    'wordCount': wordCount,
    'startFragmentId': startFragmentId,
    'endFragmentId': endFragmentId,
    'imgUrl': imgUrl,
    'titleMD5': titleMD5,
  };

  factory BookChapter.fromMap(Map<String, dynamic> map) => BookChapter(
    title: (map['title'] ?? '').toString(),
    url: (map['url'] ?? '').toString(),
    index: _chInt(map['chapter_index'] ?? map['index']) ?? 0,
    isVolume: _chFlag(map['isVolume'], false),
    isVip: _chFlag(map['isVip'], false),
    isPay: _chFlag(map['isPay'], false),
    updateTime: map['update_time']?.toString() ?? map['updateTime']?.toString(),
    content: map['content']?.toString(),
    startPos: _chInt(map['start_pos'] ?? map['start']),
    endPos: _chInt(map['end_pos'] ?? map['end']),
    variable: map['variable']?.toString(),
    wordCount: _chInt(map['wordCount']),
    startFragmentId: map['startFragmentId']?.toString(),
    endFragmentId: map['endFragmentId']?.toString(),
    imgUrl: map['imgUrl']?.toString(),
    titleMD5: map['titleMD5']?.toString(),
    baseUrl: map['baseUrl']?.toString(),
    tag: map['tag']?.toString(),
    resourceUrl: map['resourceUrl']?.toString(),
  );
}
