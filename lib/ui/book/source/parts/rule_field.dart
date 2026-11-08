/// 由 source_edit_screen.dart 按「一类一文件」拆出的 _RuleField。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../source_edit_screen.dart';


/// 规则子字段描述
class _RuleField {
  final String key;
  final String label;
  final String hint;
  const _RuleField(this.key, this.label, this.hint);
}
