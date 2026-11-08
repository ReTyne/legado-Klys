/// 由 homepage_module_widgets.dart 按「一类一文件」拆出的 HomepageModuleData。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../homepage_module_widgets.dart';


/// 模块的展示数据（标题 + 卡片列表），从 HomepageModule.config(JSON) 解析。
///
/// config 支持两种写法：
/// 1. `{"title":"...", "items":[{...}, ...]}`
/// 2. 直接 `[{...}, ...]`
/// 每个 item 的字段见 [HomepageItem.fromMap]。解析失败时安全退化为空列表，
/// 由 Feed 依据 sourceUrl/exploreUrl 拉取真实发现书籍填充。
class HomepageModuleData {
  const HomepageModuleData({required this.title, required this.items});

  final String title;
  final List<HomepageItem> items;

  factory HomepageModuleData.fromModule(HomepageModule m) {
    var title = m.name;
    final items = <HomepageItem>[];
    final cfg = m.config;
    if (cfg != null && cfg.trim().isNotEmpty) {
      try {
        final d = jsonDecode(cfg);
        if (d is Map) {
          final t = d['title']?.toString().trim() ?? '';
          if (t.isNotEmpty) title = t;
          final raw = d['items'];
          if (raw is List) {
            for (final e in raw) {
              if (e is Map) {
                items.add(HomepageItem.fromMap(Map<String, dynamic>.from(e)));
              }
            }
          }
        } else if (d is List) {
          for (final e in d) {
            if (e is Map) {
              items.add(HomepageItem.fromMap(Map<String, dynamic>.from(e)));
            }
          }
        }
      } catch (_) {}
    }
    return HomepageModuleData(title: title, items: items);
  }
}
