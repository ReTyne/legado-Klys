/// 由 legado_js_runtime.dart 按「一类一文件」拆出的 JsEvalResult。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../legado_js_runtime.dart';


/// 一次 JS 求值的结果。
class JsEvalResult {
  JsEvalResult({
    this.value,
    this.variable,
    this.loginInfo,
    this.cookies = const {},
    this.kv = const {},
    this.logs = const [],
    this.toasts = const [],
    this.error,
  });

  /// 脚本完成值（对象/数组转 Map/List，其余为 String/num/bool）
  final dynamic value;
  final String? variable;
  final String? loginInfo;
  final Map<String, dynamic> cookies;
  final Map<String, dynamic> kv;
  final List<String> logs;
  final List<String> toasts;
  final String? error;

  String? get stringValue {
    final v = value;
    if (v == null) return null;
    if (v is String) return v;
    return jsonEncode(v);
  }
}
