import 'dart:convert';

import 'package:legado_md3/constant/book_type.dart';

class Book {
  /// 书籍类型常量（与 BookSource.bookSourceType 对应）
  static const int typeText = 0; // 网络/文本
  static const int typeLocal = 1; // 本地书籍
  static const int typeAudio = 2; // 音频书源
  static const int typeImage = 3; // 图片/漫画书源
  static const int typeVideo = 4; // 视频书源

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
  int type; // 0: 网络/文本 1: 本地 2: 音频 3: 图片/漫画
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

  /// 长章节拆分开关：
  /// 仅对本地 TXT 生效——正文超过 100KB 的章节自动按 ~10KB 在换行处拆成子章节，
  /// 原章节转为卷标。导入时与目录页/详情页切换时按此标志重新解析目录。
  bool splitLongChapter;

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
    this.splitLongChapter = true,
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
    'splitLongChapter': splitLongChapter ? 1 : 0,
  };

  factory Book.fromMap(Map<String, dynamic> map) {
    // 备份导入边界（BackupService 恢复书籍时调用本方法，是「旧备份 type 重映射」
    // 的真实消费点）：上游/Android 备份的 type 是位标志（>=8），需转成
    // 本项目顺序枚举落库；Flutter 自身备份的 type 为 0..4 顺序枚举，原样保留。
    // 位标志中的 local 位叠加到 Book.local 布尔，避免类型信息丢失。
    final int rawType = _rawTypeInt(map['type']);
    final bool isBitmap = BookType.isBitmapType(rawType);
    return Book(
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
      local: (map['local'] as int? ?? 0) == 1 ||
          (isBitmap && BookType.hasFlag(rawType, BookType.local)),
      type: isBitmap ? BookType.toFlutterEnum(rawType) : rawType,
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
      // 旧库/旧备份无此列时默认开启
      splitLongChapter: (map['splitLongChapter'] as int? ?? 1) == 1,
    );
  }

  /// 兼容备份 JSON 中 type 为数字或字符串数字（旧版导出可能写成 "8"）。
  static int _rawTypeInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  /// 跨端导出（Android 备份互通）：输出与上游 BookType 位标志一致的 Map。
  /// `type` 由本项目顺序枚举转成位标志（[BookType.fromFlutterEnum]），
  /// 并按 origin 前缀/`local` 补本地位。本项目自身备份仍用 [toMap]（顺序枚举），
  /// 以免改变 reader_router / book_provider 依赖的 switch 语义。
  Map<String, dynamic> toUpstreamMap() => <String, dynamic>{
        ...toMap(),
        'type': BookType.fromFlutterEnum(type, origin: origin, isLocal: local),
      };

  Map<String, dynamic> toJson() => toMap();

  factory Book.fromJson(Map<String, dynamic> json) => Book.fromMap(json);

  String toJsonString() => jsonEncode(toJson());

  factory Book.fromJsonString(String str) => Book.fromJson(jsonDecode(str));

  @override
  bool operator ==(Object other) => identical(this, other) || other is Book && runtimeType == other.runtimeType && name == other.name && author == other.author;

  @override
  int get hashCode => name.hashCode ^ author.hashCode;
}
