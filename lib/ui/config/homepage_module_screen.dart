import 'package:flutter/material.dart';

import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/homepage_module.dart';
import 'package:legado_md3/ui/main/discover/homepage_module_widgets.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';

part 'parts/homepage_module_screen_state.dart';
part 'parts/homepage_module_edit_dialog.dart';
part 'parts/homepage_module_edit_dialog_state.dart';
part 'parts/set_draft.dart';
part 'parts/homepage_set_sheet.dart';
part 'parts/homepage_set_sheet_state.dart';
part 'parts/homepage_set_edit_dialog.dart';
part 'parts/homepage_set_edit_dialog_state.dart';


/// 首页模块管理（fork 特性：卡片式模块化首页）。
///
/// 模块：增删改 / 启停 / 拖拽排序 / 类型选择，全部走
/// getHomepageModules / insertHomepageModule / updateHomepageModule /
/// deleteHomepageModule；默认发现页的 HomepageFeed 直接消费本表渲染。
/// 模块集（HomepageCustomSet）：新建 / 编辑 / 删除 / 切换，走
/// getHomepageCustomSets / insertHomepageCustomSet / deleteHomepageCustomSet，
/// 当前启用的模块集 id 由 HomepageSetStore 持久化，Feed 按其 moduleIds 过滤排序。
class HomepageModuleScreen extends StatefulWidget {
  const HomepageModuleScreen({super.key});

  @override
  State<HomepageModuleScreen> createState() => _HomepageModuleScreenState();
}
