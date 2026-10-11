import 'package:legado_md3/data/model/replace_rule.dart';

/// 替换净化规则服务
class ReplaceRuleService {
  /// 应用替换规则到文本
  String applyRules(String text, List<ReplaceRule> rules, {String? scope}) {
    String result = text;
    for (final rule in rules) {
      if (rule.enable != true) continue;
      // 检查作用范围
      if (rule.scope != null && rule.scope!.isNotEmpty && scope != null) {
        if (rule.scope != 'all' && !scope.contains(rule.scope!)) {
          continue;
        }
      }
      try {
        final regex = RegExp(rule.replaceRule);
        result = result.replaceAll(regex, rule.replacement);
      } catch (_) {
        // 无效正则，跳过
      }
    }
    return result;
  }

  /// 测试单条规则
  String testRule(String text, ReplaceRule rule) {
    try {
      final regex = RegExp(rule.replaceRule);
      return text.replaceAll(regex, rule.replacement);
    } catch (e) {
      return '正则表达式错误: $e';
    }
  }

  /// 从JSON导入规则
  static List<ReplaceRule> fromJson(List<dynamic> jsonList) {
    return jsonList.map((json) {
      if (json is! Map) return null;
      return ReplaceRule(
        replaceSummary: json['replaceSummary'] ?? json['summary'] ?? '',
        replaceRule: json['replaceRule'] ?? json['rule'] ?? '',
        replacement: json['replacement'] ?? json['to'] ?? '',
        enable: json['enable'] ?? true,
        scope: json['scope'],
        order: json['order'] as int?,
      );
    }).whereType<ReplaceRule>().toList();
  }

  /// 导出规则为JSON
  static List<Map<String, dynamic>> toJson(List<ReplaceRule> rules) {
    return rules.map((r) => {
      'replaceSummary': r.replaceSummary,
      'replaceRule': r.replaceRule,
      'replacement': r.replacement,
      'enable': r.enable,
      'scope': r.scope,
      'order': r.order,
    }).toList();
  }
}
