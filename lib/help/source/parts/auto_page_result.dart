/// 由 rule_auto_completer.dart 按「一类一文件」拆出的 AutoPageResult。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../rule_auto_completer.dart';


/// 单页规则推导结果（详情 / 正文）
class AutoPageResult {
  final Map<String, String> fields;

  /// 推导出的下一跳绝对地址（详情页->目录页；正文页未用）
  final String? nextUrl;

  final List<String> notes;

  AutoPageResult({this.fields = const {}, this.nextUrl, this.notes = const []});
}
