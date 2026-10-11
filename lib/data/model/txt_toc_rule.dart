class TxtTocRule {
  int id;
  String name;
  String chapterRule;
  String volumeRule;
  String? example;
  int serialNumber;
  bool enable;

  TxtTocRule({
    int? id,
    this.name = '',
    this.chapterRule = '',
    this.volumeRule = '',
    this.example,
    this.serialNumber = -1,
    this.enable = true,
  }) : id = id ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'chapterRule': chapterRule,
        'volumeRule': volumeRule,
        'example': example,
        'serialNumber': serialNumber,
        'enable': enable ? 1 : 0,
      };

  factory TxtTocRule.fromMap(Map<String, dynamic> map) => TxtTocRule(
        id: map['id'] as int,
        name: map['name'] as String? ?? '',
        chapterRule: map['chapterRule'] as String? ?? '',
        volumeRule: map['volumeRule'] as String? ?? '',
        example: map['example'] as String?,
        serialNumber: map['serialNumber'] as int? ?? -1,
        enable: (map['enable'] as int? ?? 1) == 1,
      );

  Map<String, dynamic> toJson() => toMap();

  factory TxtTocRule.fromJson(Map<String, dynamic> json) => TxtTocRule.fromMap(json);
}
