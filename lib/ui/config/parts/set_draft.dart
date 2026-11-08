/// 由 homepage_module_screen.dart 按「一类一文件」拆出的 _SetDraft。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../homepage_module_screen.dart';


/// 模块集编辑草稿。
class _SetDraft {
  _SetDraft(this.name, this.moduleIds);
  final String name;
  final List<int> moduleIds;
}
