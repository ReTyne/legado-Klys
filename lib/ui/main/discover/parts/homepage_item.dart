/// 由 homepage_module_widgets.dart 按「一类一文件」拆出的 HomepageItem。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../homepage_module_widgets.dart';


/// 首页模块内的一张卡片数据。
///
/// config JSON 中除 title/subtitle/cover/badge/action 外的键统一收进 [params]
/// （字符串化），便于动作携带 keyword / sourceUrl / exploreUrl / bookUrl /
/// origin 等参数，点击动作由 HomepageFeed 的 onAction 回调真实分发。
class HomepageItem {
  const HomepageItem({
    required this.title,
    this.subtitle = '',
    this.cover,
    this.badge,
    this.action = HomepageAction.none,
    this.params = const <String, String>{},
  });

  final String title;
  final String subtitle;
  final String? cover;
  final String? badge;
  final HomepageAction action;
  final Map<String, String> params;

  String param(String key) => params[key] ?? '';

  factory HomepageItem.fromMap(Map<String, dynamic> map) {
    final params = <String, String>{};
    const reserved = {'title', 'subtitle', 'cover', 'badge', 'action'};
    map.forEach((k, v) {
      if (!reserved.contains(k) && v != null) {
        params[k.toString()] = v.toString();
      }
    });
    return HomepageItem(
      title: (map['title'] ?? '').toString(),
      subtitle: (map['subtitle'] ?? '').toString(),
      cover: map['cover']?.toString(),
      badge: map['badge']?.toString(),
      action: _parseAction(map['action']?.toString()),
      params: params,
    );
  }

  /// 由发现 / 搜索书籍构造：默认动作 = 打开书籍详情。
  factory HomepageItem.fromSearchBook(SearchBook b) => HomepageItem(
        title: b.name,
        subtitle: b.author,
        cover: b.coverUrl,
        badge: b.lastChapter,
        action: HomepageAction.book,
        params: <String, String>{
          'bookName': b.name,
          'bookAuthor': b.author,
          'cover': b.coverUrl ?? '',
          'intro': b.intro ?? '',
          'kind': b.kind ?? '',
          'bookUrl': b.bookUrl ?? '',
          'origin': b.origin ?? '',
          'originName': b.originName ?? '',
          'lastChapter': b.lastChapter ?? '',
        },
      );
}
