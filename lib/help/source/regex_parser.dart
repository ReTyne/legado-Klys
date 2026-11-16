/// 由 rule_pipeline.dart 拆分还原（历史合并点）。
/// 以 part 形式归属同一库，私有成员互通，外部 import 路径不变。
part of 'rule_pipeline.dart';

/// 正则工具，覆盖书源/净化规则常用的正则操作
class RegexParser {
  /// 取第一个匹配结果
  static String? firstMatch(String input, String pattern, {int group = 0}) {
    final re = RegExp(pattern, multiLine: true, dotAll: true);
    final m = re.firstMatch(input);
    if (m == null) return null;
    if (group < m.groupCount) return m.group(group);
    return m.group(0);
  }

  /// 取所有匹配结果（默认取整个匹配，group 指定捕获组）
  static List<String> allMatches(String input, String pattern,
      {int group = 0}) {
    final re = RegExp(pattern, multiLine: true, dotAll: true);
    final result = <String>[];
    for (final m in re.allMatches(input)) {
      final g = group <= m.groupCount ? m.group(group) : m.group(0);
      if (g != null) result.add(g);
    }
    return result;
  }

  /// 正则替换，支持 $1、${name} 反向引用（Dart 原生 replaceAllMapped）
  static String replace(String input, String pattern, String replacement) {
    final re = RegExp(pattern, multiLine: true, dotAll: true);
    return input.replaceAllMapped(re, (m) {
      var out = replacement;
      for (var i = m.groupCount; i >= 0; i--) {
        out = out.replaceAll('\$$i', m.group(i) ?? '');
      }
      return out;
    });
  }

  /// 删除所有匹配的内容
  static String remove(String input, String pattern) =>
      input.replaceAll(RegExp(pattern, multiLine: true, dotAll: true), '');

  /// 判断是否匹配
  static bool hasMatch(String input, String pattern) =>
      RegExp(pattern, multiLine: true, dotAll: true).hasMatch(input);

  /// 按正则切分
  static List<String> split(String input, String pattern) =>
      input.split(RegExp(pattern, multiLine: true, dotAll: true));

  /// 提取多条规则结果，规则格式：正则##替换模板（可多条用 && 连接）
  static String? applyRule(String input, String rule) {
    if (!rule.contains('##')) return firstMatch(input, rule);
    final idx = rule.indexOf('##');
    final pattern = rule.substring(0, idx);
    final template = rule.substring(idx + 2);
    final re = RegExp(pattern, multiLine: true, dotAll: true);
    final m = re.firstMatch(input);
    if (m == null) return null;
    var out = template;
    for (var i = m.groupCount; i >= 0; i--) {
      out = out.replaceAll('\$$i', m.group(i) ?? '');
    }
    return out;
  }

  /// 链式正则求值。
  ///
  /// [rules] 为顺序执行的若干正则：中间段把每个全匹配文本用换行拼接，
  /// 作为下一段的输入内容；末段对最终内容再次匹配，返回每个匹配的
  /// 分组数组 `[group0, group1, …]`（group0 为全匹配）。
  /// 规则为空或输入为空时返回空结果。
  static List<List<String>> matchChain(List<String> rules, String content) {
    if (rules.isEmpty) return <List<String>>[];
    var current = content;
    for (var i = 0; i < rules.length - 1; i++) {
      if (rules[i].isEmpty) continue;
      final re = RegExp(rules[i], multiLine: true, dotAll: true);
      final hits = re.allMatches(current).map((m) => m.group(0) ?? '').toList();
      current = hits.join('\n');
    }
    final last = rules.last;
    if (last.isEmpty) return <List<String>>[];
    final re = RegExp(last, multiLine: true, dotAll: true);
    final out = <List<String>>[];
    for (final m in re.allMatches(current)) {
      out.add(<String>[
        for (var g = 0; g <= m.groupCount; g++) m.group(g) ?? '',
      ]);
    }
    return out;
  }
}
