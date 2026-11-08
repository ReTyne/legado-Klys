class HighlightTagRule {
  int? id;
  String name;
  String pattern;
  int? color;
  int enabled;
  int? order;
  String? scope; // all, bookSourceUrl

  HighlightTagRule({this.id, required this.name, required this.pattern, this.color, this.enabled = 1, this.order, this.scope});

  Map<String, dynamic> toMap() => {
    'id': id, 'name': name, 'pattern': pattern, 'color': color,
    'enabled': enabled, 'order': order, 'scope': scope,
  };

  factory HighlightTagRule.fromMap(Map<String, dynamic> map) => HighlightTagRule(
    id: map['id'], name: map['name'] ?? '', pattern: map['pattern'] ?? '',
    color: map['color'], enabled: map['enabled'] ?? 1, order: map['order'],
    scope: map['scope'],
  );
}
