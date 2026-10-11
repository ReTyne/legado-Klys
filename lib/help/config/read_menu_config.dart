import 'package:shared_preferences/shared_preferences.dart';

/// 阅读界面可配置菜单（对齐原版：底部工具栏 / 更多菜单 / 文本选择菜单）
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
    'charset': '选择编码',
    'txttoc': 'TXT目录规则',
    'debug': '调试日志',
  };
  static const List<String> defaultMoreMenu = [
    'toc', 'search', 'translate', 'autoread', 'changesource', 'copypage', 'summary',
    'contentedit', 'replace', 'detail', 'refreshtoc', 'cache', 'addbookmark', 'bookmarklist',
    'share', 'reverse', 'resegment', 'delruby', 'delh', 'charset', 'txttoc', 'debug',
  ];

  /// 文本选择菜单
  static const Map<String, String> selectMenuItems = {
    'copy': '复制',
    'marking': '划线',
    'dict': '查词',
    'translate': '翻译',
  };
  static const List<String> defaultSelectMenu = ['copy', 'marking', 'dict', 'translate'];

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
