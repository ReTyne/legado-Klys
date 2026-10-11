/// 正则工具，对齐 Legado 书源/净化规则常用的正则操作
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
  static List<String> allMatches(String input, String pattern, {int group = 0}) {
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
}
