// ReadRecord 的唯一定义位于 read_record.dart；此处导出以兼容历史引用，
// 避免出现两个字段不一致的 ReadRecord 类型。
export 'read_record.dart';

int? _asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  return int.tryParse(v.toString());
}

bool _asBool(dynamic v, bool fallback) {
  if (v == null) return fallback;
  if (v is bool) return v;
  if (v is int) return v != 0;
  final s = v.toString().toLowerCase();
  return s == 'true' || s == '1';
}

/// 替换净化规则。字段与 legado-E `data/entities/ReplaceRule.kt` 对齐：
/// name / group / pattern / replacement / scope / scopeTitle / scopeContent /
/// excludeScope / isEnabled / isRegex / timeoutMillisecond / sortOrder。
class ReplaceRule {
  int? id;
  String replaceSummary;
  String replaceRule;
  String replacement;
  bool? enable;
  bool isTitle;
  bool isContent;
  bool isRegex;
  String? scope;
  String? excludeScope;
  String? group;
  int timeoutMillisecond;
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
    this.excludeScope,
    this.group,
    this.timeoutMillisecond = 3000,
    this.order,
  });

  /// 与上游 `getValidTimeoutMillisecond()` 一致：<= 0 回退 3000ms。
  int get validTimeoutMillisecond =>
      timeoutMillisecond <= 0 ? 3000 : timeoutMillisecond;

  /// 与上游 `getDisplayNameGroup()` 一致：有分组时显示 "名称 (分组)"。
  String get displayNameWithGroup =>
      (group == null || group!.trim().isEmpty)
          ? replaceSummary
          : '$replaceSummary ($group)';

  /// 与上游 `isValid()` 一致：空 pattern 无效；正则必须可编译；
  /// 以未转义的 `|` 结尾视为无效（漏删尾部竖线会引发灾难性回溯）。
  bool isValid() {
    if (replaceRule.isEmpty) return false;
    if (isRegex) {
      try {
        RegExp(replaceRule);
      } catch (_) {
        return false;
      }
      if (replaceRule.endsWith('|') && !replaceRule.endsWith(r'\|')) {
        return false;
      }
    }
    return true;
  }

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
    'excludeScope': excludeScope,
    'group_name': group,
    'timeoutMillisecond': timeoutMillisecond,
    'order_num': order,
  };

  /// 导出为 legado-E 兼容的 JSON 字段（跨端备份 / Web 端互通，不丢字段）。
  Map<String, dynamic> toLegadoJson() => {
    'name': replaceSummary,
    'group': group,
    'pattern': replaceRule,
    'replacement': replacement,
    'scope': scope,
    'scopeTitle': isTitle,
    'scopeContent': isContent,
    'excludeScope': excludeScope,
    'isEnabled': enable ?? true,
    'isRegex': isRegex,
    'timeoutMillisecond': timeoutMillisecond,
    'order': order,
  };

  factory ReplaceRule.fromMap(Map<String, dynamic> map) => ReplaceRule(
    id: _asInt(map['id']),
    replaceSummary:
        (map['replaceSummary'] ?? map['summary'] ?? map['name'] ?? '')
            .toString(),
    replaceRule: (map['replaceRule'] ??
            map['regex'] ??
            map['pattern'] ??
            map['rule'] ??
            '')
        .toString(),
    replacement: (map['replacement'] ?? map['to'] ?? '').toString(),
    enable: _asBool(map['enable'] ?? map['isEnabled'] ?? map['enabled'], true),
    isTitle: _asBool(map['isTitle'] ?? map['scopeTitle'], false),
    isContent: _asBool(map['isContent'] ?? map['scopeContent'], true),
    isRegex: _asBool(map['isRegex'], true),
    scope: map['scope']?.toString(),
    excludeScope: map['excludeScope']?.toString(),
    group: (map['group'] ?? map['group_name'])?.toString(),
    timeoutMillisecond: _asInt(map['timeoutMillisecond']) ?? 3000,
    order: _asInt(map['order_num'] ?? map['order'] ?? map['sortOrder']),
  );
}
