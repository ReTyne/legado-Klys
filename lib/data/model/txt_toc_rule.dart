int? _tocInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString().trim());
}

class TxtTocRule {
  int id;
  String name;
  String chapterRule;
  String volumeRule;
  String? example;
  int serialNumber;
  bool enable;

  /// 命中规则后对章节标题做的替换表达式。
  String? replacement;

  TxtTocRule({
    int? id,
    this.name = '',
    this.chapterRule = '',
    this.volumeRule = '',
    this.example,
    this.serialNumber = -1,
    this.enable = true,
    this.replacement,
  }) : id = id ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'chapterRule': chapterRule,
        'volumeRule': volumeRule,
        'example': example,
        'serialNumber': serialNumber,
        'enable': enable ? 1 : 0,
        'replacement': replacement,
      };

  factory TxtTocRule.fromMap(Map<String, dynamic> map) => TxtTocRule(
        id: _tocInt(map['id']),
        name: (map['name'] ?? '').toString(),
        chapterRule: (map['chapterRule'] ?? map['rule'] ?? '').toString(),
        volumeRule: (map['volumeRule'] ?? '').toString(),
        example: map['example']?.toString(),
        serialNumber: _tocInt(map['serialNumber']) ?? -1,
        enable: (map['enable'] == null)
            ? true
            : (map['enable'] == 1 || map['enable'] == true || map['enable'] == '1'),
        replacement: map['replacement']?.toString(),
      );

  Map<String, dynamic> toJson() => toMap();

  factory TxtTocRule.fromJson(Map<String, dynamic> json) => TxtTocRule.fromMap(json);
}
