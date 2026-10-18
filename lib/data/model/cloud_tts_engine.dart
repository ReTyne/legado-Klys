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
