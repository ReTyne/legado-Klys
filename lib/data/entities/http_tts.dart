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
