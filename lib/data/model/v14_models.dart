import 'package:flutter/foundation.dart';

/// 第十轮（v14）新增数据实体，对齐 Luoyacheng/legado-E「阅读Sigma」：
/// SearchBook / BookSourceCheckState / PdfOutline / PageEstimate / KvCache /
/// BookReview(段评) / ReadPreset(多套排版) / DanmakuCache / BgmTrack / AiAgentTool。
/// 全部为纯数据类，toMap/fromMap 与 v14TableSqls 的列集合严格一致。

/// 跨源换源检索缓存（对齐 Sigma SearchBook + SearchBookDao）
class SearchBookTable {
  String bookUrl;
  String name;
  String author;
  String origin;
  String? originName;
  int type;
  String? coverUrl;
  String? intro;
  String? latestChapterTitle;
  String tocUrl;
  int time;
  int originOrder;
  String? chapterWordCountText;
  int chapterWordCount;
  int respondTime;

  SearchBookTable({
    required this.bookUrl,
    this.name = '',
    this.author = '',
    required this.origin,
    this.originName,
    this.type = 8,
    this.coverUrl,
    this.intro,
    this.latestChapterTitle,
    this.tocUrl = '',
    int? time,
    this.originOrder = 0,
    this.chapterWordCountText,
    this.chapterWordCount = -1,
    this.respondTime = -1,
  }) : time = time ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toMap() => {
        'bookUrl': bookUrl,
        'name': name,
        'author': author,
        'origin': origin,
        'originName': originName,
        'type': type,
        'coverUrl': coverUrl,
        'intro': intro,
        'latestChapterTitle': latestChapterTitle,
        'tocUrl': tocUrl,
        'time': time,
        'originOrder': originOrder,
        'chapterWordCountText': chapterWordCountText,
        'chapterWordCount': chapterWordCount,
        'respondTime': respondTime,
      };

  factory SearchBookTable.fromMap(Map<String, dynamic> m) => SearchBookTable(
        bookUrl: m['bookUrl'] ?? '',
        name: m['name'] ?? '',
        author: m['author'] ?? '',
        origin: m['origin'] ?? '',
        originName: m['originName'],
        type: m['type'] ?? 8,
        coverUrl: m['coverUrl'],
        intro: m['intro'],
        latestChapterTitle: m['latestChapterTitle'],
        tocUrl: m['tocUrl'] ?? '',
        time: m['time'],
        originOrder: m['originOrder'] ?? 0,
        chapterWordCountText: m['chapterWordCountText'],
        chapterWordCount: m['chapterWordCount'] ?? -1,
        respondTime: m['respondTime'] ?? -1,
      );
}

/// 书源检测状态落库（对齐 Sigma CheckSource 的持久化结果）
class BookSourceCheckState {
  int? id;
  String origin;
  String name;
  int state; // 0 未检 / 1 可用 / 2 失效 / 3 超时
  int respondTime;
  String? errorMsg;
  int? checkTime;

  BookSourceCheckState({
    this.id,
    required this.origin,
    this.name = '',
    this.state = 0,
    this.respondTime = -1,
    this.errorMsg,
    this.checkTime,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'origin': origin,
        'name': name,
        'state': state,
        'respondTime': respondTime,
        'errorMsg': errorMsg,
        'checkTime': checkTime,
      };

  factory BookSourceCheckState.fromMap(Map<String, dynamic> m) =>
      BookSourceCheckState(
        id: m['id'],
        origin: m['origin'] ?? '',
        name: m['name'] ?? '',
        state: m['state'] ?? 0,
        respondTime: m['respondTime'] ?? -1,
        errorMsg: m['errorMsg'],
        checkTime: m['checkTime'],
      );
}

/// PDF 大纲（对齐 Sigma PdfOutline / pdfx 大纲解析结果）
class PdfOutline {
  int? id;
  String bookName;
  String author;
  String title;
  int level;
  int page; // 0-based
  int order;

  PdfOutline({
    this.id,
    required this.bookName,
    this.author = '',
    required this.title,
    this.level = 0,
    this.page = 0,
    this.order = 0,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'bookName': bookName,
        'author': author,
        'title': title,
        'level': level,
        'page': page,
        'sortOrder': order,
      };

  factory PdfOutline.fromMap(Map<String, dynamic> m) => PdfOutline(
        id: m['id'],
        bookName: m['bookName'] ?? '',
        author: m['author'] ?? '',
        title: m['title'] ?? '',
        level: m['level'] ?? 0,
        page: m['page'] ?? 0,
        order: m['sortOrder'] ?? m['order'] ?? 0,
      );
}

/// 章节页数估算 / 全书索引（对齐 fork PageEstimate 思路）
class PageEstimate {
  int? id;
  String bookName;
  String author;
  int chapterIndex;
  int pageCount; // -1 未估算
  int mode; // 0 启发式 / 1 精确
  int? updateTime;

  PageEstimate({
    this.id,
    required this.bookName,
    this.author = '',
    required this.chapterIndex,
    this.pageCount = -1,
    this.mode = 0,
    this.updateTime,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'bookName': bookName,
        'author': author,
        'chapterIndex': chapterIndex,
        'pageCount': pageCount,
        'mode': mode,
        'updateTime': updateTime,
      };

  factory PageEstimate.fromMap(Map<String, dynamic> m) => PageEstimate(
        id: m['id'],
        bookName: m['bookName'] ?? '',
        author: m['author'] ?? '',
        chapterIndex: m['chapterIndex'] ?? 0,
        pageCount: m['pageCount'] ?? -1,
        mode: m['mode'] ?? 0,
        updateTime: m['updateTime'],
      );
}

/// 通用带过期的 KV 缓存（对齐 Sigma CacheDao / deadline 语义）
class KvCache {
  String key;
  String? value;
  int deadline; // 0 表示永不过期

  KvCache({required this.key, this.value, this.deadline = 0});

  bool get expired =>
      deadline > 0 && DateTime.now().millisecondsSinceEpoch > deadline;

  Map<String, dynamic> toMap() => {
        'key': key,
        'value': value,
        'deadline': deadline,
      };

  factory KvCache.fromMap(Map<String, dynamic> m) => KvCache(
        key: m['key'] ?? '',
        value: m['value'],
        deadline: m['deadline'] ?? 0,
      );
}

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

/// 多套排版预设（对齐 Sigma ReadBookConfig.configList / shareLayout）
class ReadPreset {
  int? id;
  String name;
  String config; // ReadConfig 序列化 JSON
  int isDefault;
  int? createTime;

  ReadPreset({
    this.id,
    required this.name,
    required this.config,
    this.isDefault = 0,
    int? createTime,
  }) : createTime = createTime ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'config': config,
        'isDefault': isDefault,
        'createTime': createTime,
      };

  factory ReadPreset.fromMap(Map<String, dynamic> m) => ReadPreset(
        id: m['id'],
        name: m['name'] ?? '',
        config: m['config'] ?? '{}',
        isDefault: m['isDefault'] ?? 0,
        createTime: m['createTime'],
      );
}

/// 弹幕文件缓存索引（对齐 Sigma RuleBigDataHelp.getDanmakuFile 三级 MD5 路径）
class DanmakuCache {
  int? id;
  String bookUrl;
  String chapterUrl;
  String filePath;
  int count;
  int? updateTime;

  DanmakuCache({
    this.id,
    required this.bookUrl,
    required this.chapterUrl,
    required this.filePath,
    this.count = 0,
    int? updateTime,
  }) : updateTime = updateTime ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toMap() => {
        'id': id,
        'bookUrl': bookUrl,
        'chapterUrl': chapterUrl,
        'filePath': filePath,
        'count': count,
        'updateTime': updateTime,
      };

  factory DanmakuCache.fromMap(Map<String, dynamic> m) => DanmakuCache(
        id: m['id'],
        bookUrl: m['bookUrl'] ?? '',
        chapterUrl: m['chapterUrl'] ?? '',
        filePath: m['filePath'] ?? '',
        count: m['count'] ?? 0,
        updateTime: m['updateTime'],
      );
}

/// BGM 背景音乐曲目（对齐 fork BGM 在线音乐库）
class BgmTrack {
  int? id;
  String title;
  String artist;
  String url;
  String? coverUrl;
  String source;
  int duration;
  int customOrder;

  BgmTrack({
    this.id,
    required this.title,
    this.artist = '',
    required this.url,
    this.coverUrl,
    this.source = 'local',
    this.duration = 0,
    this.customOrder = 0,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'artist': artist,
        'url': url,
        'coverUrl': coverUrl,
        'source': source,
        'duration': duration,
        'customOrder': customOrder,
      };

  factory BgmTrack.fromMap(Map<String, dynamic> m) => BgmTrack(
        id: m['id'],
        title: m['title'] ?? '',
        artist: m['artist'] ?? '',
        url: m['url'] ?? '',
        coverUrl: m['coverUrl'],
        source: m['source'] ?? 'local',
        duration: m['duration'] ?? 0,
        customOrder: m['customOrder'] ?? 0,
      );
}

/// AI Agent 工具注册（对齐 fork AI Agent 工具链）
@immutable
class AiAgentTool {
  final int? id;
  final String name;
  final String description;
  final String schema; // JSON Schema
  final String handler; // 处理器标识（Dart 侧分发键）
  final int enabled;

  const AiAgentTool({
    this.id,
    required this.name,
    this.description = '',
    this.schema = '{}',
    required this.handler,
    this.enabled = 1,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'description': description,
        'schema': schema,
        'handler': handler,
        'enabled': enabled,
      };

  factory AiAgentTool.fromMap(Map<String, dynamic> m) => AiAgentTool(
        id: m['id'],
        name: m['name'] ?? '',
        description: m['description'] ?? '',
        schema: m['schema'] ?? '{}',
        handler: m['handler'] ?? '',
        enabled: m['enabled'] ?? 1,
      );
}
