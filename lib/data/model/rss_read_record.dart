class RssReadRecord {
  int? id;
  String sourceUrl;
  String title;
  String? link;
  int readTime;

  RssReadRecord({this.id, required this.sourceUrl, required this.title, this.link, required this.readTime});

  Map<String, dynamic> toMap() => {
    'id': id, 'sourceUrl': sourceUrl, 'title': title, 'link': link, 'readTime': readTime,
  };

  factory RssReadRecord.fromMap(Map<String, dynamic> map) => RssReadRecord(
    id: map['id'], sourceUrl: map['sourceUrl'] ?? '', title: map['title'] ?? '',
    link: map['link'], readTime: map['readTime'] ?? 0,
  );
}
