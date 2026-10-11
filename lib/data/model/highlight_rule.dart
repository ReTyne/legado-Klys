class HighlightRule {
  int? id;
  String name;
  String pattern;
  int? color;
  int enabled;
  int? order;

  HighlightRule({this.id, required this.name, required this.pattern, this.color, this.enabled = 1, this.order});

  Map<String, dynamic> toMap() => {
    'id': id, 'name': name, 'pattern': pattern, 'color': color,
    'enabled': enabled, 'order': order,
  };

  factory HighlightRule.fromMap(Map<String, dynamic> map) => HighlightRule(
    id: map['id'], name: map['name'] ?? '', pattern: map['pattern'] ?? '',
    color: map['color'], enabled: map['enabled'] ?? 1, order: map['order'],
  );
}
