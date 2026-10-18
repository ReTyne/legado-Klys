class DictRule {
  int? id;
  String name;
  String summary;
  String url;
  String? rule;
  int enabled;
  int? order;

  DictRule({this.id, required this.name, this.summary = '', this.url = '', this.rule, this.enabled = 1, this.order});

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
