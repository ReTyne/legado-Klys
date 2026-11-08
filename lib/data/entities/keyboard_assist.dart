class KeyboardAssist {
  int? id;
  String name;
  String rule;
  int enabled;
  int? order;

  KeyboardAssist({this.id, required this.name, required this.rule, this.enabled = 1, this.order});

  Map<String, dynamic> toMap() => {
    'id': id, 'name': name, 'rule': rule, 'enabled': enabled, 'order': order,
  };

  factory KeyboardAssist.fromMap(Map<String, dynamic> map) => KeyboardAssist(
    id: map['id'], name: map['name'] ?? '', rule: map['rule'] ?? '',
    enabled: map['enabled'] ?? 1, order: map['order'],
  );
}
