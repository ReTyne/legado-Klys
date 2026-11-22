import 'dart:convert';

import 'package:legado_md3/constant/book_type.dart';

int? _bookInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString().trim());
}

bool _bookBool(dynamic v, bool fallback) {
  if (v == null) return fallback;
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = v.toString().trim().toLowerCase();
  if (s == 'true' || s == '1') return true;
  if (s == 'false' || s == '0') return false;
  return fallback;
}

String? _bookStr(dynamic v) => v?.toString();

/// 字数可能是整数数字，也可能是 "12万字" 这类带单位的文本，取其中的整数部分。
int? _bookWordCount(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  final match = RegExp(r'-?\d+').firstMatch(v.toString());
  return match == null ? null : int.tryParse(match.group(0)!);
}

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
  String? durChapterTitle;
  String? noteUrl;
  String? bookUrl;
  String? tocUrl;
  String? origin;
  String? originName;
  String? tag;
  int? wordCount;
  bool canUpdate;
  bool local;
  int type; // 0: 网络/文本 1: 本地 2: 音频 3: 图片/漫画
  String? group;
  int? order;
  int? originOrder;
  int? latestChapterTime;
  int? lastCheckTime;
  int? lastCheckCount;
  String? infoHtml;
  String? tocHtml;
  String? variable;
  int? customOrder;
  bool allowUpdate;
  String? fileName;
  String? customCoverUrl;
  String? bookComment;
  String? customTag;
  String? customIntro;
  String? charset;
  int? durVolumeIndex;
  int? chapterInVolumeIndex;
  int? totalChapterNum;
  int? syncTime;

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
    this.durChapterTitle,
    this.noteUrl,
    this.bookUrl,
    this.tocUrl,
    this.origin,
    this.originName,
    this.tag,
    this.wordCount,
    this.canUpdate = true,
    this.local = false,
    this.type = 0,
    this.group,
    this.order,
    this.originOrder,
    this.latestChapterTime,
    this.lastCheckTime,
    this.lastCheckCount,
    this.infoHtml,
    this.tocHtml,
    this.variable,
    this.customOrder,
    this.allowUpdate = true,
    this.fileName,
    this.customCoverUrl,
    this.bookComment,
    this.customTag,
    this.customIntro,
    this.charset,
    this.durVolumeIndex,
    this.chapterInVolumeIndex,
    this.totalChapterNum,
    this.syncTime,
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
    'tocUrl': tocUrl ?? noteUrl ?? bookUrl ?? '',
    'durChapterIndex': durChapterIndex,
    'durChapterTitle': durChapterTitle ?? '',
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
    'durChapterTitle': durChapterTitle,
    'noteUrl': noteUrl,
    'bookUrl': bookUrl,
    'tocUrl': tocUrl,
    'origin': origin,
    'originName': originName,
    'tag': tag,
    'wordCount': wordCount,
    'canUpdate': canUpdate ? 1 : 0,
    'local': local ? 1 : 0,
    'type': type,
    'group_name': group,
    'order_num': order,
    'originOrder': originOrder,
    'latestChapterTime': latestChapterTime,
    'lastCheckTime': lastCheckTime,
    'lastCheckCount': lastCheckCount,
    'infoHtml': infoHtml,
    'tocHtml': tocHtml,
    'variable': variable,
    'customOrder': customOrder,
    'allowUpdate': allowUpdate ? 1 : 0,
    'fileName': fileName,
    'customCoverUrl': customCoverUrl,
    'bookComment': bookComment,
    'customTag': customTag,
    'customIntro': customIntro,
    'charset': charset,
    'durVolumeIndex': durVolumeIndex,
    'chapterInVolumeIndex': chapterInVolumeIndex,
    'totalChapterNum': totalChapterNum,
    'syncTime': syncTime,
    'splitLongChapter': splitLongChapter ? 1 : 0,
  };

  /// 判断一份数据是否来自跨端备份：这些键由备份写入，本地库不产生。
  static bool _isUpstreamMap(Map<String, dynamic> map) {
    if (map['canUpdate'] is bool) return true;
    if (map['wordCount'] is String) return true;
    const keys = <String>[
      'latestChapterTitle', 'tocUrl', 'originOrder', 'lastCheckCount',
      'durChapterTitle', 'syncTime', 'customTag', 'customIntro', 'charset',
      'totalChapterNum', 'durVolumeIndex', 'chapterInVolumeIndex',
    ];
    return keys.any(map.containsKey);
  }

  factory Book.fromMap(Map<String, dynamic> map) {
    final int rawType = _rawTypeInt(map['type']);
    final String? origin = _bookStr(map['origin']) ?? _bookStr(map['originName']);
    // 跨端备份中的旧顺序类型需先还原成位标志，再与本地枚举互相转换。
    final int effectiveType = (_isUpstreamMap(map) && rawType >= 0 && rawType <= 3)
        ? BookType.remapLegacyType(rawType, origin: origin)
        : rawType;
    final bool isBitmap = BookType.isBitmapType(effectiveType);
    return Book(
      name: _bookStr(map['name']) ?? '',
      author: _bookStr(map['author']) ?? '',
      coverUrl: _bookStr(map['coverUrl']),
      intro: _bookStr(map['intro']),
      kind: _bookStr(map['kind']),
      lastChapter: _bookStr(map['lastChapter'] ?? map['latestChapterTitle']),
      lastChapterIndex: _bookInt(map['lastChapterIndex']),
      durChapterIndex: _bookInt(map['durChapterIndex']) ?? 0,
      durChapterPos: _bookInt(map['durChapterPos']) ?? 0,
      durChapterTime: _bookInt(map['durChapterTime']) ?? 0,
      durChapterTitle: _bookStr(map['durChapterTitle']),
      noteUrl: _bookStr(map['noteUrl']) ?? _bookStr(map['tocUrl']),
      bookUrl: _bookStr(map['bookUrl']),
      tocUrl: _bookStr(map['tocUrl']),
      origin: _bookStr(map['origin']),
      originName: _bookStr(map['originName']),
      tag: _bookStr(map['tag']),
      wordCount: _bookWordCount(map['wordCount']),
      canUpdate: _bookBool(map['canUpdate'], true),
      local: _bookBool(map['local'], false) ||
          (isBitmap && BookType.hasFlag(effectiveType, BookType.local)),
      type: isBitmap ? BookType.toFlutterEnum(effectiveType) : effectiveType,
      group: _bookStr(map['group_name'] ?? map['group']),
      order: _bookInt(map['order_num'] ?? map['order']),
      originOrder: _bookInt(map['originOrder']),
      latestChapterTime: _bookInt(map['latestChapterTime']),
      lastCheckTime: _bookInt(map['lastCheckTime']),
      lastCheckCount: _bookInt(map['lastCheckCount']),
      infoHtml: _bookStr(map['infoHtml']),
      tocHtml: _bookStr(map['tocHtml']),
      variable: _bookStr(map['variable']),
      customOrder: _bookInt(map['customOrder']),
      allowUpdate: _bookBool(map['allowUpdate'], true),
      fileName: _bookStr(map['fileName']),
      customCoverUrl: _bookStr(map['customCoverUrl']),
      bookComment: _bookStr(map['bookComment']),
      customTag: _bookStr(map['customTag']),
      customIntro: _bookStr(map['customIntro']),
      charset: _bookStr(map['charset']),
      durVolumeIndex: _bookInt(map['durVolumeIndex']),
      chapterInVolumeIndex: _bookInt(map['chapterInVolumeIndex']),
      totalChapterNum: _bookInt(map['totalChapterNum']),
      syncTime: _bookInt(map['syncTime']),
      splitLongChapter: _bookBool(map['splitLongChapter'], true),
    );
  }

  /// 兼容备份 JSON 中 type 为数字或字符串数字。
  static int _rawTypeInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  /// 跨端导出：输出位标志 type 与备份字段别名，供其它端直接读取。
  Map<String, dynamic> toUpstreamMap() => <String, dynamic>{
        ...toMap(),
        'type': BookType.fromFlutterEnum(type, origin: origin, isLocal: local),
        'latestChapterTitle': lastChapter,
        'tocUrl': tocUrl ?? noteUrl ?? bookUrl,
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
