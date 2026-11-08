/// 由 legado_js_runtime.dart 按「一类一文件」拆出的 MiniLegadoJs。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../legado_js_runtime.dart';


/// 迷你回退运行时（桌面/测试/不支持平台）。
class MiniLegadoJs implements LegadoJs {
  @override
  Future<void> loadSource(JsSource source) async {}

  @override
  Future<JsEvalResult> eval(JsEvalRequest req) async {
    final r = req.result;
    final out = JsMiniEvaluator.eval(
      req.script,
      result: r is String ? r : (r == null ? null : jsonEncode(r)),
      key: req.key,
      page: req.page,
      baseUrl: req.baseUrl,
    );
    return JsEvalResult(value: out, variable: req.source.variable);
  }

  @override
  Future<void> dispose() async {}
}
