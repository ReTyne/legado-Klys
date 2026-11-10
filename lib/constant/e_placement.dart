// legado-E「功能位置」单一真源（Single Source of Truth）。
//
// 本文件只保存「功能落在哪里」的权威清单，逐项来自上游
// /workspace/legado-E/legado-E-main/app/src/main/res/{menu,xml,layout}/，
// 生产代码与各对齐测试共同引用，杜绝多处硬编码漂移。
//
// 口径（用户拍板）：E 主落点严格 1:1 —— 导航层级、各页 overflow 项集合与顺序、
// 长按菜单、设置分组与层级、交互触发点、阅读页底部按钮数/序、默认视图全部按 E；
// 仅配色/圆角/字体/图标风格等 MD3 纯视觉保留不同。
// K 版独有功能不删除、不建独立扩展页，沉到所在页内部次级位置（见 kSecondary）。
//
// 注意：本文件放在 lib/constant/ 而非 lib/ui/，是为了不参与
// test/ui_refactor_contract_test.dart 的「lib/ui 设计令牌覆盖」扫描分母。

/// 一个 E 版菜单项。`id` 为上游 `android:id="@+id/xxx"` 去掉前缀后的名字，
/// 作为稳定标识（`key`）供顺序断言使用，避免中文文案改动导致误判。
class EMenuItem {
  const EMenuItem(
    this.id,
    this.zh, {
    this.always = false,
    this.checkable = false,
    this.checkedByDefault = false,
    this.visibleByDefault = true,
    this.group,
  });

  /// 上游菜单 id（如 `menu_update_toc`）。
  final String id;

  /// 上游 values-zh/strings.xml 的中文标题（权威文案）。
  final String zh;

  /// showAsAction="always"（常驻 AppBar 图标）为 true；"never"（overflow）为 false。
  final bool always;

  /// android:checkable="true"。
  final bool checkable;

  /// android:checked="true" 的默认勾选态。
  final bool checkedByDefault;

  /// android:visible="false" 记为 false —— Flutter 侧默认不渲染，不伪造空壳。
  final bool visibleByDefault;

  /// 所属 <group android:id>（如 `menu_group_on_line`、`menu_group_epub`）。
  final String? group;

  /// 稳定 Key，供 widget 测试用 `getTopLeft(...).dy` 做严格顺序断言。
  String get key => 'e_menu::$id';

  /// 是否属于 overflow（非常驻）项。
  bool get overflow => !always;
}

class EPlacement {
  const EPlacement._();

  // ── 1. 底部导航（main_bnv.xml）────────────────────────────────────────
  /// 4 个 tab，顺序固定。E 版无 DrawerLayout。
  static const List<EMenuItem> tabs = [
    EMenuItem('menu_bookshelf', '书架', always: true),
    EMenuItem('menu_discovery', '发现', always: true),
    EMenuItem('menu_rss', '订阅', always: true),
    EMenuItem('menu_my_config', '我的', always: true),
  ];

  /// 各 tab 顶部工具栏菜单（main_*.xml）的项与顺序。
  static const Map<String, List<EMenuItem>> mainMenus = {
    // main_bookshelf.xml：搜索常驻，其余 11 项 overflow。
    'bookshelf': [
      EMenuItem('menu_search', '搜索', always: true),
      EMenuItem('menu_update_toc', '更新目录'),
      EMenuItem('menu_add_local', '添加本地'),
      EMenuItem('menu_remote', '远程书籍'),
      EMenuItem('menu_add_url', '添加网址'),
      EMenuItem('menu_bookshelf_manage', '书架管理'),
      EMenuItem('menu_download', '缓存/导出'),
      EMenuItem('menu_group_manage', '分组管理'),
      EMenuItem('menu_bookshelf_layout', '书架布局'),
      EMenuItem('menu_export_bookshelf', '导出书单'),
      EMenuItem('menu_import_bookshelf', '导入书单'),
      EMenuItem('menu_log', '日志'),
    ],
    // main_explore.xml：仅「分组」1 项（常驻，内嵌动态子菜单）。
    'explore': [
      EMenuItem('menu_group', '分组', always: true),
    ],
    // main_rss.xml：4 项全常驻。
    'rss': [
      EMenuItem('menu_read_record', '阅读记录', always: true),
      EMenuItem('menu_rss_star', '收藏', always: true),
      EMenuItem('menu_group', '分组', always: true),
      EMenuItem('menu_rss_config', '设置', always: true),
    ],
    // main_my.xml：仅「帮助」1 项常驻。
    'my': [
      EMenuItem('menu_help', '帮助', always: true),
    ],
  };

  // ── 2. 「我的」tab 主体（pref_main.xml，14 项）────────────────────────
  /// 顶层 6 项（无 Category）。
  static const List<EMenuItem> myTop = [
    EMenuItem('bookSourceManage', '书源管理'),
    EMenuItem('txtTocRuleManage', 'TXT目录规则'),
    EMenuItem('replaceManage', '替换净化'),
    EMenuItem('dictRuleManage', '字典规则'),
    EMenuItem('themeMode', '主题模式'),
    EMenuItem('webService', 'Web 服务'),
  ];

  /// Category「设置」3 项。
  static const List<EMenuItem> mySettingCategory = [
    EMenuItem('web_dav_setting', '备份与恢复'),
    EMenuItem('theme_setting', '主题设置'),
    EMenuItem('setting', '其它设置'),
  ];

  /// Category「其它」5 项。
  static const List<EMenuItem> myOtherCategory = [
    EMenuItem('bookmark', '书签'),
    EMenuItem('readRecord', '阅读记录'),
    EMenuItem('fileManage', '文件管理'),
    EMenuItem('about', '关于'),
    EMenuItem('exit', '退出'),
  ];

  /// 完整 14 项（顶层 + 两个分类），用于存在性/顺序交叉校验。
  static List<EMenuItem> get myAll =>
      [...myTop, ...mySettingCategory, ...myOtherCategory];

  /// 分类标题（用于分区标题断言）。
  static const List<String> myCategoryTitles = ['设置', '其它'];

  // ── 3. 关于页（about.xml，独立页 9 项，非弹窗）────────────────────────
  static const List<EMenuItem> aboutTop = [
    EMenuItem('contributors', '贡献者'),
    EMenuItem('update_log', '更新日志'),
    EMenuItem('check_update', '检查更新'),
  ];
  static const List<EMenuItem> aboutOtherCategory = [
    EMenuItem('crashLog', '崩溃日志'),
    EMenuItem('saveLog', '保存日志'),
    EMenuItem('createHeapDump', '创建堆栈转储'),
    EMenuItem('privacyPolicy', '隐私政策'),
    EMenuItem('license', '开源协议'),
    EMenuItem('disclaimer', '免责声明'),
  ];
  static List<EMenuItem> get aboutAll => [...aboutTop, ...aboutOtherCategory];

  // ── 4. 设置多级分类树（pref_config_*.xml）─────────────────────────────
  /// 入口页的 3 个分类（对应 pref_main 的 Category「设置」3 项跳转目标）。
  /// 每个分类是一个独立子页，子页内部再按 Category 分区。
  static const List<String> settingEntryCategories = [
    '备份与恢复', // → BackupConfig (pref_config_backup.xml)
    '主题设置', // → ThemeConfig  (pref_config_theme.xml)
    '其它设置', // → OtherConfig  (pref_config_other.xml)
  ];

  /// 各设置子页的 key 顺序（用于子页项集/序交叉校验）。
  static const Map<String, List<String>> settingConfigKeys = {
    // pref_config_other.xml：顶层 1 + 主界面 6 + 其它设置 31
    'other': [
      'language',
      '|main_activity',
      'auto_refresh', 'onlyUpdateRead', 'defaultToRead', 'showDiscovery',
      'showRss', 'defaultHomePage',
      '|other_setting',
      'localPassword', 'userAgent', 'customHosts', 'webServiceWakeLock',
      'defaultBookTreeUri', 'sourceEditMaxLine', 'checkSource', 'uploadRule',
      'Cronet', 'antiAlias', 'bitmapCacheSize', 'imageRetainNum',
      'preDownloadNum', 'replaceEnableDefault', 'mediaButtonOnExit',
      'readAloudByMediaButton', 'ignoreAudioFocus', 'autoClearExpired',
      'showAddToShelfAlert', 'updateToVariant', 'autoUpdateVariant',
      'showMangaUi', 'videoSetting', 'webPort', 'cleanCache',
      'clearWebViewData', 'shrinkDatabase', 'threadCount', 'process_text',
      'recordLog', 'recordHeapDump',
    ],
    // pref_config_backup.xml：WebDav 7 + 备份与恢复 6
    'backup': [
      '|web_dav_set',
      'web_dav_url', 'web_dav_account', 'web_dav_password', 'webDavDir',
      'webDavDeviceName', 'syncBookProgress', 'syncBookProgressPlus',
      '|backup_restore',
      'backupUri', 'web_dav_backup', 'web_dav_restore', 'restoreIgnore',
      'onlyLatestBackup', 'autoCheckNewBackup',
    ],
    // pref_config_theme.xml：顶层 8 + 白天 7 + 夜间 7
    'theme': [
      'launcherIcon', 'welcomeStyle', 'transparentStatusBar',
      'immNavigationBar', 'barElevation', 'fontScale', 'coverConfig',
      'themeList',
      '|day',
      'colorPrimary', 'colorAccent', 'colorBackground', 'colorBottomBackground',
      'backgroundImage', 'transparentNavBar', 'saveDayTheme',
      '|night',
      'colorPrimaryNight', 'colorAccentNight', 'colorBackgroundNight',
      'colorBottomBackgroundNight', 'backgroundImageNight',
      'transparentNavBarNight', 'saveNightTheme',
    ],
    // pref_config_cover.xml
    'cover': [
      'loadCoverOnlyWifi', 'coverRule', 'useDefaultCover',
      '|day', 'defaultCover', 'coverShowName', 'coverShowAuthor',
      '|night', 'defaultCoverDark', 'coverShowNameN', 'coverShowAuthorN',
    ],
    // pref_config_welcome.xml
    'welcome': [
      'welcomeShowTime', 'customWelcome',
      '|day', 'welcomeImagePath', 'welcomeShowText', 'welcomeShowIcon',
      '|night', 'welcomeImagePathDark', 'welcomeShowTextDark',
      'welcomeShowIconDark',
    ],
    // pref_config_aloud.xml：朗读配置 8 项（单层 Category）
    'aloud': [
      '|aloud_config',
      'ignoreAudioFocus', 'pauseReadAloudWhilePhoneCalls',
      'readAloudWakeLock', 'mediaButtonPerNext', 'readAloudByPage',
      'streamReadAloudAudio', 'appTtsEngine', 'sysTtsConfig',
    ],
    // pref_config_read.xml：阅读页「设置」弹窗，单层 33 项（无 Category）
    'read': [
      'screenOrientation', 'keep_light', 'hideStatusBar', 'hideNavigationBar',
      'readBodyToLh', 'paddingDisplayCutouts', 'doubleHorizontalPage',
      'progressBarBehavior', 'useZhLayout', 'textFullJustify',
      'textBottomJustify', 'adaptSpecialStyle', 'mouseWheelPage',
      'volumeKeyPage', 'volumeKeyPageOnPlay', 'keyPageOnLongPress',
      'pageTouchSlop', 'pageTouchClick', 'autoChangeSource', 'selectText',
      'showBrightnessView', 'noAnimScrollPage', 'clickImgWay', 'optimizeRender',
      'clickRegionalConfig', 'disableReturnKey', 'customPageKey',
      'expandTextMenu', 'showReadTitleAddition', 'readBarStyleFollowPage',
    ],
  };

  // ── 5. 阅读页（book_read.xml / view_read_menu.xml / content_select_action.xml）
  /// 常驻 AppBar 图标：在线书 3 项（menu_group_on_line），本地 TXT 1 项
  /// （menu_group_text，visible=false），本地书 1 项（menu_group_local）。
  static const List<EMenuItem> readAlwaysOnline = [
    EMenuItem('menu_change_source', '换源', always: true, group: 'menu_group_on_line'),
    EMenuItem('menu_refresh', '刷新', always: true, group: 'menu_group_on_line'),
    EMenuItem('menu_download', '离线缓存', always: true, group: 'menu_group_on_line'),
  ];
  static const List<EMenuItem> readAlwaysText = [
    EMenuItem('menu_toc_regex', 'TXT 目录规则',
        always: true, visibleByDefault: false, group: 'menu_group_text'),
  ];
  static const List<EMenuItem> readAlwaysLocal = [
    EMenuItem('menu_set_charset', '设置编码',
        always: true, group: 'menu_group_local'),
  ];

  /// overflow（showAsAction="never"）项与顺序，含 3 个 visible=false 项与
  /// checkable 勾选态；menu_group_epub 下两项归组。
  static const List<EMenuItem> readOverflow = [
    EMenuItem('menu_add_bookmark', '添加书签'),
    EMenuItem('menu_edit_content', '编辑内容'),
    EMenuItem('menu_page_anim', '翻页动画（本书）'),
    EMenuItem('menu_get_progress', '拉取云端进度', visibleByDefault: false),
    EMenuItem('menu_cover_progress', '覆盖云端进度', visibleByDefault: false),
    EMenuItem('menu_reverse_content', '反转内容'),
    EMenuItem('menu_simulated_reading', '模拟追读'),
    EMenuItem('menu_enable_replace', '替换净化',
        checkable: true, checkedByDefault: true),
    EMenuItem('menu_same_title_removed', '移除重复标题', checkable: true),
    EMenuItem('menu_re_segment', '重新分段', checkable: true),
    EMenuItem('menu_enable_review', '段评',
        checkable: true, visibleByDefault: false),
    EMenuItem('menu_del_ruby_tag', '删除ruby标签',
        checkable: true, group: 'menu_group_epub'),
    EMenuItem('menu_del_h_tag', '删除h标签',
        checkable: true, group: 'menu_group_epub'),
    EMenuItem('menu_image_style', '图片样式'),
    EMenuItem('menu_update_toc', '更新目录'),
    EMenuItem('menu_effective_replaces', '起效的替换'),
    EMenuItem('menu_log', '日志'),
    EMenuItem('menu_help', '帮助'),
  ];

  /// 阅读页底部 4 按钮（view_read_menu.xml ll_catalog/ll_read_aloud/ll_font/ll_setting）。
  static const List<EMenuItem> readBottomButtons = [
    EMenuItem('ll_catalog', '目录'),
    EMenuItem('ll_read_aloud', '朗读'),
    EMenuItem('ll_font', '界面'),
    EMenuItem('ll_setting', '设置'),
  ];

  /// 长按选字浮动菜单（content_select_action.xml）8 项固定顺序。
  static const List<EMenuItem> textSelectActions = [
    EMenuItem('menu_replace', '替换'),
    EMenuItem('menu_copy', '拷贝'),
    EMenuItem('menu_bookmark', '书签'),
    EMenuItem('menu_aloud', '朗读'),
    EMenuItem('menu_dict', '字典'),
    EMenuItem('menu_search_content', '全文搜索'),
    EMenuItem('menu_browser', '浏览器'),
    EMenuItem('menu_share_str', '分享'),
  ];

  // ── 6. K 版独有功能 → 所在页内部次级位置（用户拍板「E 主落点优先」）────
  /// 这些功能 E 版没有，不删除、不建独立扩展页，沉到所在页内部次级位置，
  /// 且必须不出现在任何 E 主落点（B5 用 absent 断言锁死 + 次级可触达断言）。
  static const Map<String, List<String>> kSecondary = {
    'profile': [
      'AI 助手', '智能体工具', '阅读统计', '下载管理', '首页模块', '定时任务',
      '朗读引擎', '欢迎页设置', '桌面图标', '视频设置', '词典规则',
      'GitHub 项目', '分享应用', '评分',
    ],
    'discover': [
      '首页模块 Feed', 'OPDS 目录', '分类管理', '过滤', '排序',
    ],
    'subscribe': [
      '规则订阅', '布局与排序', '新增订阅源', '刷新全部', '导入订阅源',
    ],
    'reading': [
      '章节摘要', '段评·本章评论', '刷新当前章节', '刷新全文', '刷新目录',
      '云进度面板', '获取云进度', '覆盖云进度', '交互网页', '排版预设',
      '重新估算全书页数', '背景音乐(BGM)', '切换为 EPUB 保版式阅读', '备忘',
      '简繁转换',
    ],
    'reading_secondary_button': ['备忘'],
  };

  // ── 7. 平台/容器降级清单（显式标注，不伪造）──────────────────────────
  /// 每项为「E 能力 → Flutter 处理」。基线测试断言降级项默认不渲染。
  static const Map<String, String> degradations = {
    'showAsAction=always/never':
        'AppBar IconButton(always) / overflow MenuAnchor(never)，容器不同、语义等价',
    'android:checkable': 'trailing 勾选框，视觉降级、状态语义等价',
    'android:visible=false':
        'visibleByDefault=false，默认不渲染、条件可见，不造假空壳',
    'PreferenceScreen 多级 Category': '独立页面 + 分区标题，层级等价、容器不同',
    'about.xml createHeapDump':
        'Android 专属（HeapDump），Flutter 无等价能力，平台降级不实现',
    'exit(SystemNavigator.pop)': 'iOS 行为差异，平台降级',
    '<menu/> 动态子分组': 'PopupMenuButton 动态 itemBuilder，等价',
    'DrawerLayout': 'E 版本身为 0 匹配，K 版亦无，无需处理',
    'view_read_menu 亮度侧栏/悬浮按钮行/章节进度条':
        '归入「界面/设置」子面板，MD3 表现不同、功能等价',
  };

  /// E 版 XML 源码根路径（供 test/e_placement_baseline_test.dart 交叉校验）。
  /// CI 上不存在时由测试 `skip` 并显式打印，不静默通过、不伪造。
  static const String eSourceRoot =
      '/workspace/legado-E/legado-E-main/app/src/main/res';
}
