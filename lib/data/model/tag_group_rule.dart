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
