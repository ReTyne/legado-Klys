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
