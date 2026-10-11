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
