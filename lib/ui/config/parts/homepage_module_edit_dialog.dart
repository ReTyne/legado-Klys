/// 由 homepage_module_screen.dart 按「一类一文件」拆出的 _HomepageModuleEditDialog。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../homepage_module_screen.dart';


/// 模块新增 / 编辑：名称、类型（单选）、可选书源/发现/JSON 配置、启用。
/// config 为 Feed 卡片数据（HomepageModuleData 解析）：
/// `{"title":"...","items":[{"title":"...","subtitle":"...","cover":"...",`
/// `"action":"search|book|explore|url","keyword":"...","sourceUrl":"...",`
/// `"exploreUrl":"...","url":"...","bookUrl":"..."}]}`；留空则 Feed 用
/// 关联书源 + 发现地址拉取真实书籍填充。
class _HomepageModuleEditDialog extends StatefulWidget {
  final HomepageModule? module;
  final int defaultOrder;
  const _HomepageModuleEditDialog({this.module, this.defaultOrder = 0});

  @override
  State<_HomepageModuleEditDialog> createState() =>
      _HomepageModuleEditDialogState();
}
