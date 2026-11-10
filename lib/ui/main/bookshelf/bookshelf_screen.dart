import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_chapter.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/data/model/bookmark.dart';
import 'package:legado_md3/data/model/replace_rule.dart';
import 'package:legado_md3/di/book_provider.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/help/source/source_engine.dart';
import 'package:legado_md3/help/storage/crash_log_helper.dart';
import 'package:legado_md3/help/storage/export_book_service.dart';
import 'package:legado_md3/ui/book/detail/book_detail_screen.dart';
import 'package:legado_md3/ui/book/import/remote_book_screen.dart';
import 'package:legado_md3/ui/book/reader_router.dart';
import 'package:legado_md3/ui/book/local_import_screen.dart';
import 'package:legado_md3/ui/book/search/search_screen.dart';
import 'package:legado_md3/ui/book/detail/change_source_screen.dart';
import 'package:legado_md3/ui/book/detail/change_cover_screen.dart';
import 'package:legado_md3/ui/cache/cache_manage_screen.dart';
import 'package:legado_md3/ui/main/bookshelf/bookshelf_manage_screen.dart';
import 'package:legado_md3/ui/main/bookshelf/group_manage_screen.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';
import 'package:legado_md3/constant/e_placement.dart';
import 'package:legado_md3/help/net/network_monitor.dart';
import 'package:legado_md3/help/config/app_config.dart';
import 'package:legado_md3/ui/book/detail/parts/delete_book_helper.dart';
import 'package:legado_md3/ui/main/bookshelf/parts/update_error_store.dart';

part 'parts/cover_cfg.dart';
part 'parts/bookshelf_screen.dart';
part 'parts/bookshelf_screen_state.dart';


/// 书架视图配置（来自 SharedPreferences，由书架配置页写入）
class _ViewCfg {
  int columnCount;
  double coverWidth;
  bool compactTitle;
  bool centerTitle;
  bool showDivider;
  bool compactDetails;
  bool showLatestChapter;
  bool showSynopsis;
  int synopsisLines;
  bool showTags;
  int maxTitleLines;
  bool coverShadow;
  int groupStyle; // 0:折叠(标签) 1:平铺(分区)
  bool hideEmptyGroups;
  int sortType; // 0最近阅读 1书名 2作者 3添加时间 4手动
  bool sortAscending;
  bool showUnread;
  bool showUnreadNew;
  bool showBookCount;
  bool showLastUpdateTime;
  bool searchFilterFirst;
  bool showTabMenu;
  int updateLimit;
  /// bs_showLocalBook：书架是否显示本地导入书籍（默认值与设置页一致：false）
  bool showLocalBook;
  /// bs_showWaitUpdateCount：分组页签是否显示待更新数量
  bool showWaitUpdateCount;
  /// bs_showFastScroller：书架是否显示快速滚动条
  bool showFastScroller;
  /// bs_gridNameMode：网格布局下书名显示方式（0显示 1隐藏 2叠加到封面）
  int gridNameMode;

  _ViewCfg({
    this.columnCount = 3,
    this.coverWidth = 100,
    this.compactTitle = false,
    this.centerTitle = false,
    this.showDivider = false,
    this.compactDetails = false,
    this.showLatestChapter = true,
    this.showSynopsis = false,
    this.synopsisLines = 2,
    this.showTags = false,
    this.maxTitleLines = 2,
    this.coverShadow = true,
    this.groupStyle = 0,
    this.hideEmptyGroups = false,
    this.sortType = 0,
    this.sortAscending = false,
    this.showUnread = false,
    this.showUnreadNew = true,
    this.showBookCount = true,
    this.showLastUpdateTime = false,
    this.searchFilterFirst = false,
    this.showTabMenu = true,
    this.updateLimit = 0,
    this.showLocalBook = false,
    this.showWaitUpdateCount = false,
    this.showFastScroller = true,
    this.gridNameMode = 0,
  });

  static Future<_ViewCfg> load() async {
    final p = await SharedPreferences.getInstance();
    return _ViewCfg(
      columnCount: p.getInt('bs_columnCount') ?? 3,
      coverWidth: p.getDouble('bs_coverWidth') ?? 100,
      compactTitle: p.getBool('bs_compactTitle') ?? false,
      centerTitle: p.getBool('bs_centerTitle') ?? false,
      showDivider: p.getBool('bs_showDivider') ?? false,
      compactDetails: p.getBool('bs_compactDetails') ?? false,
      showLatestChapter: p.getBool('bs_showLatestChapter') ?? true,
      showSynopsis: p.getBool('bs_showSynopsis') ?? false,
      synopsisLines: p.getInt('bs_synopsisLines') ?? 2,
      showTags: p.getBool('bs_showTags') ?? false,
      maxTitleLines: p.getInt('bs_maxTitleLines') ?? 2,
      coverShadow: p.getBool('bs_coverShadow') ?? true,
      groupStyle: p.getInt('bs_groupStyle') ?? 0,
      hideEmptyGroups: p.getBool('bs_hideEmptyGroups') ?? false,
      sortType: p.getInt('bs_sortType') ?? 0,
      sortAscending: p.getBool('bs_sortAscending') ?? false,
      showUnread: p.getBool('bs_showUnread') ?? false,
      showUnreadNew: p.getBool('bs_showUnreadNew') ?? true,
      showBookCount: p.getBool('bs_showBookCount') ?? true,
      showLastUpdateTime: p.getBool('bs_showLastUpdateTime') ?? false,
      searchFilterFirst: p.getBool('bs_searchFilterFirst') ?? false,
      showTabMenu: p.getBool('bs_showTabMenu') ?? true,
      updateLimit: p.getInt('bs_updateLimit') ?? 0,
      showLocalBook: p.getBool('bs_showLocalBook') ?? false,
      showWaitUpdateCount: p.getBool('bs_showWaitUpdateCount') ?? false,
      showFastScroller: p.getBool('bs_showFastScroller') ?? true,
      gridNameMode: p.getInt('bs_gridNameMode') ?? 0,
    );
  }

  /// 配置排序索引 -> 书架内部排序索引
  /// 配置: 0最近阅读 1书名 2作者 3添加时间 4手动
  /// 内部: 0智能/手动 1书名 2作者 3最近阅读 4添加时间 5字数
  static const sortMap = [3, 1, 2, 4, 0];
}
