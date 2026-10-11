// ReadRecord 的唯一定义位于 read_record.dart；此处导出以兼容历史引用，
// 避免出现两个字段不一致的 ReadRecord 类型。
export 'read_record.dart';

class ReplaceRule {
  int? id;
  String replaceSummary;
  String replaceRule;
  String replacement;
  bool? enable;
  bool isTitle;
  bool isContent;
  bool isRegex;
  String? scope; // 书源URL或"all"
  int? order;

  ReplaceRule({
    this.id,
    required this.replaceSummary,
    required this.replaceRule,
    required this.replacement,
    this.enable = true,
    this.isTitle = false,
    this.isContent = true,
    this.isRegex = true,
    this.scope,
    this.order,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'replaceSummary': replaceSummary,
    'replaceRule': replaceRule,
    'replacement': replacement,
    'enable': enable == true ? 1 : 0,
    'isTitle': isTitle ? 1 : 0,
    'isContent': isContent ? 1 : 0,
    'isRegex': isRegex ? 1 : 0,
    'scope': scope,
    'order_num': order,
  };

  factory ReplaceRule.fromMap(Map<String, dynamic> map) => ReplaceRule(
    id: map['id'] as int?,
    replaceSummary: (map['replaceSummary'] ?? map['summary'] ?? '') as String,
    replaceRule: (map['replaceRule'] ?? map['regex'] ?? map['pattern'] ?? '') as String,
    replacement: (map['replacement'] ?? '') as String,
    enable: map['enable'] == null ? true : (map['enable'] is bool ? map['enable'] as bool : (map['enable'] as int) == 1),
    isTitle: map['isTitle'] == null ? false : (map['isTitle'] is bool ? map['isTitle'] as bool : (map['isTitle'] as int) == 1),
    isContent: map['isContent'] == null ? true : (map['isContent'] is bool ? map['isContent'] as bool : (map['isContent'] as int) != 0),
    isRegex: map['isRegex'] == null ? true : (map['isRegex'] is bool ? map['isRegex'] as bool : (map['isRegex'] as int) != 0),
    scope: (map['scope'] ?? map['scopeContent']) as String?,
    order: map['order_num'] as int? ?? map['order'] as int?,
  );
}
