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
  });

  /// 转为 JS rssArticle 上下文
  Map<String, dynamic> jsContext() => {
    'title': title,
    'link': link,
    'description': description ?? '',
    'image': image ?? '',
    'content': content ?? '',
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
  };

  factory RssArticle.fromMap(Map<String, dynamic> map) => RssArticle(
    id: map['id'] as int?,
    title: map['title'] as String,
    link: map['link'] as String,
    description: map['description'] as String?,
    content: map['content'] as String?,
    image: map['image'] as String?,
    pubDate: map['pubDate'] as int?,
    author: map['author'] as String?,
    category: map['category'] as String?,
    sourceName: map['sourceName'] as String?,
    sourceUrl: map['sourceUrl'] as String?,
    read: (map['isRead'] as int?) == 1,
    starred: (map['starred'] as int?) == 1,
    readTime: map['readTime'] as int?,
    favorite: (map['star'] ?? map['favorite']) as int?,
  );
}
