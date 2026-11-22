int? _raInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString().trim());
}

double? _raDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().trim());
}

/// RSS文章模型
class RssArticle {
  int? id;
  String title;
  String link;
  String? description;
  String? content;
  String? image;
  int? pubDate;
  String? author;
  String? category;
  String? sourceName;
  String? sourceUrl;
  bool? read;
  bool? starred;
  int? readTime;
  int? favorite;

  /// 跨端互通的扩展字段。
  String? origin;
  String? sort;
  int? order;
  String? group;
  String? variable;
  int? type;
  double? durPos;

  RssArticle({
    this.id,
    required this.title,
    required this.link,
    this.description,
    this.content,
    this.image,
    this.pubDate,
    this.author,
    this.category,
    this.sourceName,
    this.sourceUrl,
    this.read = false,
    this.starred = false,
    this.readTime,
    this.favorite,
    this.origin,
    this.sort,
    this.order,
    this.group,
    this.variable,
    this.type,
    this.durPos,
  });

  /// 转为 JS rssArticle 上下文
  Map<String, dynamic> jsContext() => {
    'title': title,
    'link': link,
    'description': description ?? '',
    'image': image ?? '',
    'content': content ?? '',
    'origin': origin ?? '',
    'variable': variable,
  };

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'link': link,
    'description': description,
    'content': content,
    'image': image,
    'pubDate': pubDate,
    'author': author,
    'category': category,
    'sourceName': sourceName,
    'sourceUrl': sourceUrl,
    'isRead': read == true ? 1 : 0,
    'starred': starred == true ? 1 : 0,
    'readTime': readTime,
    'star': favorite,
    'origin': origin,
    'sort': sort,
    'order': order,
    'group': group,
    'variable': variable,
    'type': type,
    'durPos': durPos,
  };

  factory RssArticle.fromMap(Map<String, dynamic> map) => RssArticle(
    id: _raInt(map['id']),
    title: (map['title'] ?? '').toString(),
    link: (map['link'] ?? '').toString(),
    description: map['description']?.toString(),
    content: map['content']?.toString(),
    image: map['image']?.toString(),
    pubDate: _raInt(map['pubDate']),
    author: map['author']?.toString(),
    category: map['category']?.toString(),
    sourceName: map['sourceName']?.toString(),
    sourceUrl: map['sourceUrl']?.toString(),
    read: (map['isRead'] ?? map['read']) == 1 || (map['isRead'] ?? map['read']) == true,
    starred: map['starred'] == 1 || map['starred'] == true,
    readTime: _raInt(map['readTime']),
    favorite: _raInt(map['star'] ?? map['favorite']),
    origin: map['origin']?.toString(),
    sort: map['sort']?.toString(),
    order: _raInt(map['order']),
    group: map['group']?.toString(),
    variable: map['variable']?.toString(),
    type: _raInt(map['type']),
    durPos: _raDouble(map['durPos']),
  );
}
