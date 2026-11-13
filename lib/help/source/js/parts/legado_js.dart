/// 由 legado_js_runtime.dart 按「一类一文件」拆出的 LegadoJs。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../legado_js_runtime.dart';


/// JS 运行时抽象（WebView 真引擎 / 迷你回退共用接口）。
abstract class LegadoJs {
  Future<void> loadSource(JsSource source);
  Future<JsEvalResult> eval(JsEvalRequest req);
  Future<void> dispose();
}

/// 判断规则是否包含需要 JS 引擎的写法。
bool ruleNeedsRealJs(String? rule) {
  if (rule == null || rule.isEmpty) return false;
  return rule.contains('<js>') ||
      rule.contains('@js:') ||
      rule.contains('@webjs:') ||
      rule.contains('{{');
}
