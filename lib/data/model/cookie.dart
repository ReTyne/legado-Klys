class Cookie {
  int? id;
  String url;
  String cookie;
  int lastUpdateTime;

  Cookie({this.id, required this.url, required this.cookie, required this.lastUpdateTime});

  Map<String, dynamic> toMap() => {
    'id': id, 'url': url, 'cookie': cookie, 'lastUpdateTime': lastUpdateTime,
  };

  factory Cookie.fromMap(Map<String, dynamic> map) => Cookie(
    id: map['id'], url: map['url'] ?? '', cookie: map['cookie'] ?? '',
    lastUpdateTime: map['lastUpdateTime'] ?? 0,
  );
}
