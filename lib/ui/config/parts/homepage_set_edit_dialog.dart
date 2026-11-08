/// 由 homepage_module_screen.dart 按「一类一文件」拆出的 _HomepageSetEditDialog。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../homepage_module_screen.dart';


/// 新建 / 编辑模块集：名称 + 勾选纳入的模块（顺序即 Feed 展示顺序）。
class _HomepageSetEditDialog extends StatefulWidget {
  const _HomepageSetEditDialog({this.set, required this.modules});

  final HomepageCustomSet? set;
  final List<HomepageModule> modules;

  @override
  State<_HomepageSetEditDialog> createState() => _HomepageSetEditDialogState();
}
