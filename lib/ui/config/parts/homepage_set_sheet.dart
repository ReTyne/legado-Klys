/// 由 homepage_module_screen.dart 按「一类一文件」拆出的 _HomepageSetSheet。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../homepage_module_screen.dart';


/// 模块集管理 sheet：列出 / 切换 / 新建 / 编辑 / 删除模块集。
/// DAO 未提供 updateHomepageCustomSet，故「编辑」= 删除旧行 + 插入新行
/// （真实落库），编辑后若该集为当前集则自动把新行重新设为当前集。
class _HomepageSetSheet extends StatefulWidget {
  const _HomepageSetSheet({required this.db, required this.onChanged});

  final DatabaseService db;
  final Future<void> Function() onChanged;

  @override
  State<_HomepageSetSheet> createState() => _HomepageSetSheetState();
}
