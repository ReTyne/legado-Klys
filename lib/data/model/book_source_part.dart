import 'book_source.dart';

/// 书源投影实体。
///
/// 只承载书源管理列表需要的列，配合投影查询避免整行读取。
/// [hasLoginUrl] / [hasExploreUrl] 是查询得到的计算列；[toBookSource]
/// 用投影字段（含可选的原始地址）还原一个 BookSource 供编辑基础信息。
class BookSourcePart {
  final String bookSourceUrl;
  final String bookSourceName;
  final String? bookSourceGroup;
  final int bookSourceType;
  final bool enabled;
  final bool enabledExplore;
  final int customOrder;

  /// 计算列：是否配置了登录地址 / 发现地址。
  final bool hasLoginUrl;
  final bool hasExploreUrl;

  /// 原始登录 / 发现地址（投影可选列），供 [toBookSource] 还原。
  final String? loginUrl;
  final String? exploreUrl;

  const BookSourcePart({
    required this.bookSourceUrl,
    this.bookSourceName = '',
    this.bookSourceGroup,
    this.bookSourceType = 0,
    this.enabled = true,
    this.enabledExplore = true,
    this.customOrder = 0,
    this.hasLoginUrl = false,
    this.hasExploreUrl = false,
    this.loginUrl,
    this.exploreUrl,
  });

  factory BookSourcePart.fromMap(Map<String, dynamic> map) {
    final loginUrl = map['loginUrl']?.toString();
    final exploreUrl = map['exploreUrl']?.toString();
    return BookSourcePart(
      bookSourceUrl: map['bookSourceUrl']?.toString() ?? '',
      bookSourceName: map['bookSourceName']?.toString() ?? '',
      bookSourceGroup: map['bookSourceGroup']?.toString(),
      bookSourceType: map['bookSourceType'] is int
          ? map['bookSourceType'] as int
          : int.tryParse(map['bookSourceType']?.toString() ?? '0') ?? 0,
      enabled: map.containsKey('enabled') ? _flag(map['enabled']) : true,
      enabledExplore: map.containsKey('enabledExplore')
          ? _flag(map['enabledExplore'])
          : true,
      customOrder: map['customOrder'] is int
          ? map['customOrder'] as int
          : int.tryParse(map['customOrder']?.toString() ?? '0') ?? 0,
      hasLoginUrl: _computedFlag(map, 'hasLoginUrl', loginUrl),
      hasExploreUrl: _computedFlag(map, 'hasExploreUrl', exploreUrl),
      loginUrl: loginUrl,
      exploreUrl: exploreUrl,
    );
  }

  /// 由投影还原一个 BookSource（规则字段留空）。
  BookSource toBookSource() => BookSource(
        bookSourceUrl: bookSourceUrl,
        bookSourceName: bookSourceName,
        bookSourceGroup: bookSourceGroup,
        bookSourceType: bookSourceType,
        enabled: enabled,
        enabledExplore: enabledExplore,
        customOrder: customOrder,
        loginUrl: loginUrl,
        exploreUrl: exploreUrl,
      );

  static bool _flag(dynamic v) =>
      v == 1 || v == true || v == '1' || v == 'true';

  static bool _computedFlag(
      Map<String, dynamic> map, String key, String? rawValue) {
    if (map.containsKey(key)) return _flag(map[key]);
    return rawValue != null && rawValue.trim().isNotEmpty;
  }
}
