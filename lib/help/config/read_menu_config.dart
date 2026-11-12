import 'package:shared_preferences/shared_preferences.dart';

import 'package:legado_md3/constant/e_placement.dart';

/// 阅读界面可配置菜单
/// 以有序 key 列表记录显示项与顺序。
class ReadMenuConfig {
  static const String kToolBar = 'read_toolbar_order';
  static const String kMoreMenu = 'read_moremenu_order';
  static const String kSelectMenu = 'read_selectmenu_order';

  /// 底部工具栏按钮
  static const Map<String, String> toolBarItems = {
    'font': '字体',
    'pageanim': '翻页动画',
    'brightness': '亮度',
    'settings': '设置',
    'tts': '朗读',
  };
  static const List<String> defaultToolBar = ['font', 'pageanim', 'brightness', 'settings', 'tts'];

  /// 更多菜单项（顺序即默认展示顺序）
  static const Map<String, String> moreMenuItems = {
    'toc': '目录',
    'search': '搜索',
    'translate': '翻译',
    'autoread': '自动阅读',
    'changesource': '章节换源',
    'copypage': '复制当前页',
    'summary': '章节摘要',
    'contentedit': '内容编辑',
    'replace': '生效替换',
    'detail': '书籍详情',
    'refreshtoc': '刷新目录',
    'cache': '离线缓存',
    'addbookmark': '添加书签',
    'bookmarklist': '书签列表',
    'share': '分享书籍',
    'reverse': '反转内容',
    'resegment': '重新分段',
    'delruby': '删除注音',
    'delh': '删除标题标签',
    'chineseconvert': '简繁转换',
    'charset': '选择编码',
    'txttoc': 'TXT目录规则',
    'debug': '调试日志',
    'sourceaction': '书源操作',
  };
  static const List<String> defaultMoreMenu = [
    'toc', 'search', 'translate', 'autoread', 'changesource', 'copypage', 'summary',
    'contentedit', 'replace', 'detail', 'refreshtoc', 'cache', 'addbookmark', 'bookmarklist',
    'share', 'reverse', 'resegment', 'delruby', 'delh', 'chineseconvert', 'charset', 'txttoc', 'debug', 'sourceaction',
  ];

  // ── 文本选择菜单 ──────────────────────────────────────────────────────
  // 可配置能力为 扩展扩展，默认：
  // 生产默认选字菜单固定为 EPlacement.textSelectActions 的 8 项
  // （替换/拷贝/书签/朗读/字典/全文搜索/浏览器/分享），顺序严格按单一真源；
  // 扩展的划线/查词/翻译/加书签 等动作保留在下方可选动作池与
  // configurableSelectMenu 可配置能力里，但不进入默认菜单，主界面保持 1:1。
  static const Map<String, String> selectMenuItems = {
    'copy': '复制',
    'marking': '划线',
    'dict': '查词',
    'translate': '翻译',
    'bookmark': '加书签',
    'tts': '朗读',
    'search': '搜索正文',
    'browser': '浏览器',
    'share': '分享',
    'replace': '替换',
  };

  /// 默认选字菜单：严格派生自 EPlacement.textSelectActions 的 8 项 id，顺序按常量。
  static List<String> get defaultSelectMenu =>
      EPlacement.textSelectActions.map((e) => e.id).toList();

  /// 扩展可选动作池（划线 / 查词 / 翻译 / 加书签 等），默认不启用。
  static const List<String> kExtraSelectActions = [
    'marking', 'dict', 'translate', 'bookmark',
  ];

  /// 可配置选字菜单能力（扩展扩展）：默认仍为 8 项，可在动作池内调整。
  static List<String> configurableSelectMenu([List<String>? chosen]) =>
      chosen == null ? defaultSelectMenu : List.of(chosen);

  /// 全部可选动作（E 8 项 + 扩展），供配置页展示，不改变默认。
  static List<String> get allSelectActions =>
      [...defaultSelectMenu, ...kExtraSelectActions];

  /// 悬浮快捷栏（阅读时边缘悬浮按钮）
  static const String kFloatingBar = 'read_floatingbar_order';
  static const Map<String, String> floatingBarItems = {
    'prev': '上一章',
    'toc': '目录',
    'next': '下一章',
    'search': '搜索',
    'tts': '朗读',
    'more': '更多',
  };
  static const List<String> defaultFloatingBar = ['prev', 'toc', 'next'];

  static Future<List<String>> load(String key, List<String> fallback) async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(key);
    if (list == null || list.isEmpty) return List.of(fallback);
    // 合并新增项（版本升级后新 key 自动补齐到末尾）
    final merged = list.where(fallback.contains).toList();
    for (final k in fallback) {
      if (!merged.contains(k)) merged.add(k);
    }
    return merged;
  }

  static Future<void> save(String key, List<String> order) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(key, order);
  }
}
