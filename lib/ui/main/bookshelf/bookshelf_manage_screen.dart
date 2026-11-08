import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/di/book_provider.dart';
import 'package:legado_md3/help/source/source_engine.dart';
import 'package:legado_md3/help/storage/download_service.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';

part 'parts/bookshelf_manage_screen_state.dart';
part 'parts/book_search_delegate.dart';


/// 书架管理 —— 对齐 legado-E `ui/book/manage/BookshelfManageActivity.kt`。
///
/// 顶栏：标题「书架管理」+ 搜索过滤（书名/作者）+ 全选/反选；
/// 列表：勾选框 + 封面 + 书名/作者，拖动右侧手柄手动排序（持久化 order）；
/// 底部操作栏（E 的 SelectActionBar）对齐 `menu/bookshelf_menage_sel.xml`：
/// 移动分组 / 移除分组 / 缓存 / 清理缓存 / 批量换源 / 允许更新 / 禁止更新 /
/// 导出 / 选中区间 / 删除。缓存接入 DownloadService 真实队列。
class BookshelfManageScreen extends StatefulWidget {
  const BookshelfManageScreen({super.key});

  @override
  State<BookshelfManageScreen> createState() => _BookshelfManageScreenState();
}
