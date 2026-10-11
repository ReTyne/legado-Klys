import 'dart:convert';

class Book {
  String name;
  String author;
  String? coverUrl;
  String? intro;
  String? kind;
  String? lastChapter;
  int? lastChapterIndex;
  int durChapterIndex;
  int durChapterPos;
  int durChapterTime;
  String? noteUrl;
  String? bookUrl;
  String? origin;
  String? originName;
  String? tag;
  int? wordCount;
  bool canUpdate;
  bool local;
  int type; // 0: 网络书籍 1: 本地书籍 2: 音频
  String? group;
  int? order;
  int? latestChapterTime;
  int? lastCheckTime;
  String? infoHtml;
  String? tocHtml;
  String? variable;
  int? customOrder;
  bool allowUpdate;
  String? fileName;
  String? customCoverUrl;
  String? bookComment;

  Book({
    required this.name,
    required this.author,
    this.coverUrl,
    this.intro,
    this.kind,
    this.lastChapter,
    this.lastChapterIndex,
    this.durChapterIndex = 0,
    this.durChapterPos = 0,
    this.durChapterTime = 0,
    this.noteUrl,
    this.bookUrl,
    this.origin,
    this.originName,
    this.tag,
    this.wordCount,
    this.canUpdate = true,
    this.local = false,
    this.type = 0,
    this.group,
    this.order,
    this.latestChapterTime,
    this.lastCheckTime,
    this.infoHtml,
    this.tocHtml,
    this.variable,
    this.customOrder,
    this.allowUpdate = true,
    this.fileName,
    this.customCoverUrl,
    this.bookComment,
  });

  String get uniqueKey => '${origin ?? ''}_$name';

  /// 传给书源 JS（ruleBookInfo/ruleToc/ruleContent）的书籍上下文。
  Map<String, dynamic> jsContext() => {
    'bookUrl': bookUrl ?? noteUrl ?? '',
    'name': name,
    'author': author,
    'coverUrl': coverUrl ?? '',
    'intro': intro ?? '',
    'kind': kind ?? '',
    'lastChapter': lastChapter ?? '',
    'tocUrl': noteUrl ?? bookUrl ?? '',
    'durChapterIndex': durChapterIndex,
    'durChapterTitle': '',
    'origin': origin ?? originName ?? '',
    'originName': originName ?? '',
    'variable': variable,
  };

  Map<String, dynamic> toMap() => {
    'name': name,
    'author': author,
    'coverUrl': coverUrl,
    'intro': intro,
    'kind': kind,
    'lastChapter': lastChapter,
    'lastChapterIndex': lastChapterIndex,
    'durChapterIndex': durChapterIndex,
    'durChapterPos': durChapterPos,
    'durChapterTime': durChapterTime,
    'noteUrl': noteUrl,
    'bookUrl': bookUrl,
    'origin': origin,
    'originName': originName,
    'tag': tag,
    'wordCount': wordCount,
    'canUpdate': canUpdate ? 1 : 0,
    'local': local ? 1 : 0,
    'type': type,
    'group_name': group,
    'order_num': order,
    'latestChapterTime': latestChapterTime,
    'lastCheckTime': lastCheckTime,
    'infoHtml': infoHtml,
    'tocHtml': tocHtml,
    'variable': variable,
    'customOrder': customOrder,
    'allowUpdate': allowUpdate ? 1 : 0,
    'fileName': fileName,
    'customCoverUrl': customCoverUrl,
    'bookComment': bookComment,
  };

  factory Book.fromMap(Map<String, dynamic> map) => Book(
    name: map['name'] as String,
    author: map['author'] as String,
    coverUrl: map['coverUrl'] as String?,
    intro: map['intro'] as String?,
    kind: map['kind'] as String?,
    lastChapter: map['lastChapter'] as String?,
    lastChapterIndex: map['lastChapterIndex'] as int?,
    durChapterIndex: map['durChapterIndex'] as int? ?? 0,
    durChapterPos: map['durChapterPos'] as int? ?? 0,
    durChapterTime: map['durChapterTime'] as int? ?? 0,
    noteUrl: map['noteUrl'] as String?,
    bookUrl: map['bookUrl'] as String?,
    origin: map['origin'] as String?,
    originName: map['originName'] as String?,
    tag: map['tag'] as String?,
    wordCount: map['wordCount'] as int?,
    canUpdate: (map['canUpdate'] as int? ?? 1) == 1,
    local: (map['local'] as int? ?? 0) == 1,
    type: map['type'] as int? ?? 0,
    group: map['group_name'] as String?,
    order: map['order_num'] as int?,
    latestChapterTime: map['latestChapterTime'] as int?,
    lastCheckTime: map['lastCheckTime'] as int?,
    infoHtml: map['infoHtml'] as String?,
    tocHtml: map['tocHtml'] as String?,
    variable: map['variable'] as String?,
    customOrder: map['customOrder'] as int?,
    allowUpdate: (map['allowUpdate'] as int? ?? 1) == 1,
    fileName: map['fileName'] as String?,
    customCoverUrl: map['customCoverUrl'] as String?,
    bookComment: map['bookComment'] as String?,
  );

  Map<String, dynamic> toJson() => toMap();

  factory Book.fromJson(Map<String, dynamic> json) => Book.fromMap(json);

  String toJsonString() => jsonEncode(toJson());

  factory Book.fromJsonString(String str) => Book.fromJson(jsonDecode(str));

  @override
  bool operator ==(Object other) => identical(this, other) || other is Book && runtimeType == other.runtimeType && name == other.name && author == other.author;

  @override
  int get hashCode => name.hashCode ^ author.hashCode;
}
