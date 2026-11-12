import 'dart:async';
import 'dart:isolate';

import 'package:legado_md3/data/model/replace_rule.dart';

/// 替换净化规则服务。
///
/// 作用域语义 `data/dao/ReplaceRuleDao.kt:65-78`：
/// - `scope` 为空 / `all` → 全部生效；否则规则的 scope 需包含书名或书源 origin
///   （上游 SQL 是 `scope LIKE '%' || :name || '%' or ...`，方向是「规则含书名」，
///   本项目历史实现写成「书名含规则」，方向相反，此处两个方向都兼容）；
/// - `excludeScope` 命中书名或 origin 时排除该规则；
/// - `scopeTitle` / `scopeContent` 分别控制作用于标题 / 正文；
/// - 按 `sortOrder` 排序后依次应用。
class ReplaceRuleService {
  String applyRules(
    String text,
    List<ReplaceRule> rules, {
    String? scope,
    String? name,
    bool isTitle = false,
  }) {
    if (rules.isEmpty) return text;
    final list = [...rules]
      ..sort((a, b) => (a.order ?? 0).compareTo(b.order ?? 0));
    var result = text;
    for (final rule in list) {
      if (rule.enable != true) continue;
      if (isTitle ? !rule.isTitle : !rule.isContent) continue;
      if (!rule.isValid()) continue;
      if (_matches(rule.excludeScope, scope, name)) continue;
      if (!_scopeMatched(rule.scope, scope, name)) continue;
      result = _applyOne(result, rule);
    }
    return result;
  }

  /// 两个方向都接受：规则串含书源/书名（上游语义），或书源/书名含规则串
  /// （本项目历史写法，避免升级后既有规则突然失效）。
  static bool _matches(String? haystack, String? origin, String? name) {
    if (haystack == null || haystack.isEmpty) return false;
    if (origin != null && origin.isNotEmpty) {
      if (haystack.contains(origin) || origin.contains(haystack)) return true;
    }
    if (name != null && name.isNotEmpty) {
      if (haystack.contains(name) || name.contains(haystack)) return true;
    }
    return false;
  }

  static bool _scopeMatched(String? ruleScope, String? origin, String? name) {
    if (ruleScope == null || ruleScope.trim().isEmpty) return true;
    if (ruleScope.trim() == 'all') return true;
    return _matches(ruleScope, origin, name);
  }

  static String _applyOne(String text, ReplaceRule rule) {
    try {
      if (rule.isRegex) {
        return text.replaceAll(RegExp(rule.replaceRule), rule.replacement);
      }
      // 非正则必须按字面量替换；此前一律当 RegExp 处理，是真实逻辑缺陷。
      return text.replaceAll(rule.replaceRule, rule.replacement);
    } catch (_) {
      return text;
    }
  }

  /// 测试单条规则（同步，不做超时）。
  String testRule(String text, ReplaceRule rule) {
    if (!rule.isValid()) {
      return '规则无效：匹配内容为空、正则语法错误或以未转义的 | 结尾';
    }
    return _applyOne(text, rule);
  }

  /// 把替换放进独立
  /// isolate，按 `getValidTimeoutMillisecond()` 超时，防止劣质正则卡死主 isolate。
  Future<String> testRuleWithTimeout(String text, ReplaceRule rule) async {
    if (!rule.isValid()) return testRule(text, rule);
    final ms = rule.validTimeoutMillisecond;
    final pattern = rule.replaceRule;
    final replacement = rule.replacement;
    final isRegex = rule.isRegex;
    try {
      return await Isolate.run(() {
        if (isRegex) return text.replaceAll(RegExp(pattern), replacement);
        return text.replaceAll(pattern, replacement);
      }).timeout(Duration(milliseconds: ms));
    } on TimeoutException {
      return '替换超时（${ms}ms），请检查正则表达式';
    } catch (e) {
      return '替换失败: $e';
    }
  }

  /// 从 JSON 导入规则，兼容  字段名与本项目历史字段名，不丢字段。
  static List<ReplaceRule> fromJson(List<dynamic> jsonList) => jsonList
      .map((json) => json is Map
          ? ReplaceRule.fromMap(Map<String, dynamic>.from(json))
          : null)
      .whereType<ReplaceRule>()
      .toList();

  /// 导出为  兼容 JSON（保留 group / excludeScope / timeoutMillisecond）。
  static List<Map<String, dynamic>> toJson(List<ReplaceRule> rules) =>
      rules.map((r) => r.toLegadoJson()).toList();
}
