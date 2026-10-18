import 'package:shared_preferences/shared_preferences.dart';

/// 字典规则（内容替换词典）：用户在「字典规则」页维护的 正则->替换 列表，
/// 以 `rule|||replacement` 的形式存于 SharedPreferences 的 `dict_rules`，
/// 总开关为 `dict_rule_enabled`。本服务负责读取并把规则应用到正文。
class ContentDictService {
  ContentDictService._();

  static bool? _enabledCache;
  static List<RegExp>? _patternCache;
  static List<String>? _replaceCache;

  /// 重新从偏好加载（规则变更后调用）
  static Future<void> reload() async {
    final p = await SharedPreferences.getInstance();
    _enabledCache = p.getBool('dict_rule_enabled') ?? true;
    _patternCache = [];
    _replaceCache = [];
    for (final raw in p.getStringList('dict_rules') ?? const <String>[]) {
      final idx = raw.indexOf('|||');
      final rule = idx >= 0 ? raw.substring(0, idx) : raw;
      final repl = idx >= 0 ? raw.substring(idx + 3) : '';
      if (rule.isEmpty) continue;
      try {
        _patternCache!.add(RegExp(rule));
        _replaceCache!.add(repl);
      } catch (_) {
        // 非法正则跳过，不影响其它规则与阅读
      }
    }
  }

  /// 确保已加载
  static Future<void> _ensureLoaded() async {
    if (_patternCache == null) await reload();
  }

  /// 把字典规则应用到正文；关闭或无规则时原样返回
  static Future<String> apply(String text) async {
    await _ensureLoaded();
    if (_enabledCache != true || _patternCache == null || _patternCache!.isEmpty) {
      return text;
    }
    var result = text;
    for (var i = 0; i < _patternCache!.length; i++) {
      try {
        result = result.replaceAll(_patternCache![i], _replaceCache![i]);
      } catch (_) {}
    }
    return result;
  }
}
