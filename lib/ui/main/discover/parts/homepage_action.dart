/// 由 homepage_module_widgets.dart 按「一类一文件」拆出的 HomepageAction。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../homepage_module_widgets.dart';


/// 卡片点击动作类型。
enum HomepageAction { none, search, book, explore, url }

HomepageAction _parseAction(String? v) => switch (v) {
      'search' => HomepageAction.search,
      'book' => HomepageAction.book,
      'explore' => HomepageAction.explore,
      'url' => HomepageAction.url,
      _ => HomepageAction.none,
    };
