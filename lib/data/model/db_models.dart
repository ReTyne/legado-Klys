/// 数据库小模型聚合文件（合并自 15 个独立模型文件，减少文件数量）。




/* ===== 由 book_group.dart 合并 ===== */
class BookGroup {
  int? id;
  String name;
  int order;
  int show;
  String? cover;

  BookGroup({this.id, required this.name, this.order = 0, this.show = 1, this.cover});

  Map<String, dynamic> toMap() => {
    'id': id, 'name': name, 'order': order, 'show': show, 'cover': cover,
  };

  factory BookGroup.fromMap(Map<String, dynamic> map) => BookGroup(
    id: map['id'], name: map['name'] ?? '', order: map['order'] ?? 0,
    show: map['show'] ?? 1, cover: map['cover'],
  );
}

/* ===== 由 book_knowledge.dart 合并 ===== */
class BookKnowledge {
  int? id;
  String bookName;
  String author;
  String type; // character, event, location, item
  String name;
  String? content;
  String? cover;
  int? order;

  BookKnowledge({this.id, required this.bookName, required this.author, required this.type, required this.name, this.content, this.cover, this.order});

  Map<String, dynamic> toMap() => {
    'id': id, 'bookName': bookName, 'author': author, 'type': type,
    'name': name, 'content': content, 'cover': cover, 'order': order,
  };

  factory BookKnowledge.fromMap(Map<String, dynamic> map) => BookKnowledge(
    id: map['id'], bookName: map['bookName'] ?? '', author: map['author'] ?? '',
    type: map['type'] ?? 'character', name: map['name'] ?? '',
    content: map['content'], cover: map['cover'], order: map['order'],
  );
}

/* ===== 由 book_marking.dart 合并 ===== */
class BookMarking {
  int? id;
  String bookName;
  String author;
  int chapterIndex;
  String chapterTitle;
  int pagePos;
  String content;
  String? note;
  int? color;
  int createTime;

  BookMarking({this.id, required this.bookName, required this.author, required this.chapterIndex, required this.chapterTitle, this.pagePos = 0, required this.content, this.note, this.color, required this.createTime});

  Map<String, dynamic> toMap() => {
    'id': id, 'bookName': bookName, 'author': author,
    'chapterIndex': chapterIndex, 'chapterTitle': chapterTitle,
    'pagePos': pagePos, 'content': content, 'note': note,
    'color': color, 'createTime': createTime,
  };

  factory BookMarking.fromMap(Map<String, dynamic> map) => BookMarking(
    id: map['id'], bookName: map['bookName'] ?? '', author: map['author'] ?? '',
    chapterIndex: map['chapterIndex'] ?? 0, chapterTitle: map['chapterTitle'] ?? '',
    pagePos: map['pagePos'] ?? 0, content: map['content'] ?? '',
    note: map['note'], color: map['color'], createTime: map['createTime'] ?? 0,
  );
}

/* ===== 由 book_progress.dart 合并 ===== */
class BookProgress {
  int? id;
  String bookName;
  String author;
  int chapterIndex;
  int pagePos;
  int duration; // 阅读时长(毫秒)
  int lastReadTime;

  BookProgress({this.id, required this.bookName, required this.author, this.chapterIndex = 0, this.pagePos = 0, this.duration = 0, required this.lastReadTime});

  Map<String, dynamic> toMap() => {
    'id': id, 'bookName': bookName, 'author': author,
    'chapterIndex': chapterIndex, 'pagePos': pagePos,
    'duration': duration, 'lastReadTime': lastReadTime,
  };

  factory BookProgress.fromMap(Map<String, dynamic> map) => BookProgress(
    id: map['id'], bookName: map['bookName'] ?? '', author: map['author'] ?? '',
    chapterIndex: map['chapterIndex'] ?? 0, pagePos: map['pagePos'] ?? 0,
    duration: map['duration'] ?? 0, lastReadTime: map['lastReadTime'] ?? 0,
  );
}

/* ===== 由 cache.dart 合并 ===== */
class Cache {
  int? id;
  String bookName;
  String author;
  int chapterIndex;
  String chapterTitle;
  String? content;
  int size;
  int saveTime;

  Cache({this.id, required this.bookName, required this.author, required this.chapterIndex, required this.chapterTitle, this.content, this.size = 0, required this.saveTime});

  Map<String, dynamic> toMap() => {
    'id': id, 'bookName': bookName, 'author': author,
    'chapterIndex': chapterIndex, 'chapterTitle': chapterTitle,
    'content': content, 'size': size, 'saveTime': saveTime,
  };

  factory Cache.fromMap(Map<String, dynamic> map) => Cache(
    id: map['id'], bookName: map['bookName'] ?? '', author: map['author'] ?? '',
    chapterIndex: map['chapterIndex'] ?? 0, chapterTitle: map['chapterTitle'] ?? '',
    content: map['content'], size: map['size'] ?? 0, saveTime: map['saveTime'] ?? 0,
  );
}

/* ===== 由 cloud_tts_engine.dart 合并 ===== */
class CloudTtsEngine {
  int? id;
  String name;
  String type; // system, local, http, cloud
  String? url;
  String? apiKey;
  String? region;
  String? voice;
  int? rate;
  int? pitch;
  int enabled;
  int? concurrentRate;

  CloudTtsEngine({this.id, required this.name, required this.type, this.url, this.apiKey, this.region, this.voice, this.rate, this.pitch, this.enabled = 1, this.concurrentRate});

  Map<String, dynamic> toMap() => {
    'id': id, 'name': name, 'type': type, 'url': url, 'apiKey': apiKey,
    'region': region, 'voice': voice, 'rate': rate, 'pitch': pitch,
    'enabled': enabled, 'concurrentRate': concurrentRate,
  };

  factory CloudTtsEngine.fromMap(Map<String, dynamic> map) => CloudTtsEngine(
    id: map['id'], name: map['name'] ?? '', type: map['type'] ?? 'system',
    url: map['url'], apiKey: map['apiKey'], region: map['region'], voice: map['voice'],
    rate: map['rate'], pitch: map['pitch'], enabled: map['enabled'] ?? 1,
    concurrentRate: map['concurrentRate'],
  );
}

/* ===== 由 dict_rule.dart 合并 ===== */
class DictRule {
  int? id;
  String name;
  String summary;
  String url;
  String? rule;
  int enabled;
  int? order;

  DictRule({this.id, required this.name, this.summary = '', this.url = '', this.rule, this.enabled = 1, this.order});

  DictRule copyWith({int? id, String? name, String? summary, String? url, String? rule, int? enabled, int? order}) => DictRule(
    id: id ?? this.id,
    name: name ?? this.name,
    summary: summary ?? this.summary,
    url: url ?? this.url,
    rule: rule ?? this.rule,
    enabled: enabled ?? this.enabled,
    order: order ?? this.order,
  );

  Map<String, dynamic> toMap() => {
    'id': id, 'name': name, 'summary': summary, 'url': url,
    'rule': rule, 'enabled': enabled, 'order': order,
  };

  factory DictRule.fromMap(Map<String, dynamic> map) => DictRule(
    id: map['id'], name: map['name'] ?? '', summary: map['summary'] ?? '',
    url: map['url'] ?? '', rule: map['rule'], enabled: map['enabled'] ?? 1,
    order: map['order'],
  );
}

/* ===== 由 highlight_rule.dart 合并 ===== */
class HighlightRule {
  int? id;
  String name;
  String pattern;
  int? color;
  int enabled;
  int? order;

  HighlightRule({this.id, required this.name, required this.pattern, this.color, this.enabled = 1, this.order});

  Map<String, dynamic> toMap() => {
    'id': id, 'name': name, 'pattern': pattern, 'color': color,
    'enabled': enabled, 'order': order,
  };

  factory HighlightRule.fromMap(Map<String, dynamic> map) => HighlightRule(
    id: map['id'], name: map['name'] ?? '', pattern: map['pattern'] ?? '',
    color: map['color'], enabled: map['enabled'] ?? 1, order: map['order'],
  );
}

/* ===== 由 highlight_tag_rule.dart 合并 ===== */
class HighlightTagRule {
  int? id;
  String name;
  String pattern;
  int? color;
  int enabled;
  int? order;
  String? scope; // all, bookSourceUrl

  HighlightTagRule({this.id, required this.name, required this.pattern, this.color, this.enabled = 1, this.order, this.scope});

  Map<String, dynamic> toMap() => {
    'id': id, 'name': name, 'pattern': pattern, 'color': color,
    'enabled': enabled, 'order': order, 'scope': scope,
  };

  factory HighlightTagRule.fromMap(Map<String, dynamic> map) => HighlightTagRule(
    id: map['id'], name: map['name'] ?? '', pattern: map['pattern'] ?? '',
    color: map['color'], enabled: map['enabled'] ?? 1, order: map['order'],
    scope: map['scope'],
  );
}

/* ===== 由 http_tts.dart 合并 ===== */
class HttpTTS {
  int? id;
  String name;
  String url;
  String? method; // GET, POST
  String? headers;
  String? body;
  int enabled;
  int? concurrentRate;

  HttpTTS({this.id, required this.name, required this.url, this.method = 'GET', this.headers, this.body, this.enabled = 1, this.concurrentRate});

  Map<String, dynamic> toMap() => {
    'id': id, 'name': name, 'url': url, 'method': method,
    'headers': headers, 'body': body, 'enabled': enabled, 'concurrentRate': concurrentRate,
  };

  factory HttpTTS.fromMap(Map<String, dynamic> map) => HttpTTS(
    id: map['id'], name: map['name'] ?? '', url: map['url'] ?? '',
    method: map['method'] ?? 'GET', headers: map['headers'], body: map['body'],
    enabled: map['enabled'] ?? 1, concurrentRate: map['concurrentRate'],
  );
}

/* ===== 由 keyboard_assist.dart 合并 ===== */
class KeyboardAssist {
  int? id;
  String name;
  String rule;
  int enabled;
  int? order;

  KeyboardAssist({this.id, required this.name, required this.rule, this.enabled = 1, this.order});

  Map<String, dynamic> toMap() => {
    'id': id, 'name': name, 'rule': rule, 'enabled': enabled, 'order': order,
  };

  factory KeyboardAssist.fromMap(Map<String, dynamic> map) => KeyboardAssist(
    id: map['id'], name: map['name'] ?? '', rule: map['rule'] ?? '',
    enabled: map['enabled'] ?? 1, order: map['order'],
  );
}

/* ===== 由 rss_star.dart 合并 ===== */
class RssStar {
  int? id;
  String sourceUrl;
  String title;
  String? link;
  String? desc;
  String? content;
  int starTime;

  RssStar({this.id, required this.sourceUrl, required this.title, this.link, this.desc, this.content, required this.starTime});

  Map<String, dynamic> toMap() => {
    'id': id, 'sourceUrl': sourceUrl, 'title': title, 'link': link,
    'desc': desc, 'content': content, 'starTime': starTime,
  };

  factory RssStar.fromMap(Map<String, dynamic> map) => RssStar(
    id: map['id'], sourceUrl: map['sourceUrl'] ?? '', title: map['title'] ?? '',
    link: map['link'], desc: map['desc'], content: map['content'],
    starTime: map['starTime'] ?? 0,
  );
}

/* ===== 由 rule_sub.dart 合并 ===== */
class RuleSub {
  int? id;
  String name;
  String url;
  String type; // bookSource, rssSource, replaceRule, dictRule, txtTocRule, highlightRule
  int enabled;
  int? lastUpdateTime;
  int? customOrder;

  RuleSub({this.id, required this.name, required this.url, required this.type, this.enabled = 1, this.lastUpdateTime, this.customOrder});

  Map<String, dynamic> toMap() => {
    'id': id, 'name': name, 'url': url, 'type': type,
    'enabled': enabled, 'lastUpdateTime': lastUpdateTime, 'customOrder': customOrder,
  };

  factory RuleSub.fromMap(Map<String, dynamic> map) => RuleSub(
    id: map['id'], name: map['name'] ?? '', url: map['url'] ?? '',
    type: map['type'] ?? 'bookSource', enabled: map['enabled'] ?? 1,
    lastUpdateTime: map['lastUpdateTime'], customOrder: map['customOrder'],
  );
}

/* ===== 由 server.dart 合并 ===== */
class Server {
  int? id;
  String name;
  String host;
  int port;
  String? path;
  String? username;
  String? password;
  int enabled;

  Server({this.id, required this.name, required this.host, this.port = 22, this.path, this.username, this.password, this.enabled = 1});

  Map<String, dynamic> toMap() => {
    'id': id, 'name': name, 'host': host, 'port': port,
    'path': path, 'username': username, 'password': password, 'enabled': enabled,
  };

  factory Server.fromMap(Map<String, dynamic> map) => Server(
    id: map['id'], name: map['name'] ?? '', host: map['host'] ?? '',
    port: map['port'] ?? 22, path: map['path'], username: map['username'],
    password: map['password'], enabled: map['enabled'] ?? 1,
  );
}

/* ===== 由 tag_group_rule.dart 合并 ===== */
class TagGroupRule {
  int? id;
  String name;
  String pattern;
  String? group;
  int enabled;
  int? order;

  TagGroupRule({this.id, required this.name, required this.pattern, this.group, this.enabled = 1, this.order});

  Map<String, dynamic> toMap() => {
    'id': id, 'name': name, 'pattern': pattern, 'group': group,
    'enabled': enabled, 'order': order,
  };

  factory TagGroupRule.fromMap(Map<String, dynamic> map) => TagGroupRule(
    id: map['id'], name: map['name'] ?? '', pattern: map['pattern'] ?? '',
    group: map['group'], enabled: map['enabled'] ?? 1, order: map['order'],
  );
}

