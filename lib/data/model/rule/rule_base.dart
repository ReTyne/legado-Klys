import 'dart:convert';

/// 强类型规则视图的公共基类。
///
/// 规则字段统一为字符串规则表达式：输入里缺失的键取空串作为默认值。
/// [raw] 保留解析出的全部键值（含未建模的扩展键），保证 [toJson] 不丢数据。
abstract class RuleBase {
  /// 输入解析后的原始键值表。
  final Map<String, dynamic> raw;

  const RuleBase(this.raw);

  /// 已建模字段的「字段名 → 取值」映射，供 [get] 类型化访问与 [toJson] 输出。
  Map<String, String> get fieldValues;

  /// 按字段名取规则值（类型化为 [String]）；未知键回退到 [raw] 的字符串形式。
  String get(String key) {
    final modeled = fieldValues[key];
    if (modeled != null) return modeled;
    return raw[key]?.toString() ?? '';
  }

  /// 输出全部已建模字段，并保留 [raw] 中的扩展键。
  Map<String, dynamic> toJson() {
    final out = <String, dynamic>{...raw};
    out.addAll(fieldValues);
    return out;
  }

  /// 把 Map 或 JSON 字符串统一解析为 `Map<String, dynamic>`；非法输入返回空表。
  static Map<String, dynamic> asMap(dynamic source) {
    if (source is Map) return Map<String, dynamic>.from(source);
    if (source is String) {
      try {
        final decoded = jsonDecode(source);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return <String, dynamic>{};
  }

  /// 从键值表安全取字符串：数字 / 布尔等转为字符串，缺失或 null 取空串。
  static String str(Map<String, dynamic> map, String key) =>
      map[key]?.toString() ?? '';
}
