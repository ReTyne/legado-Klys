import 'dart:convert';

import 'package:legado_md3/help/source/js/js_source.dart';

/// Legado书源模型 - 完全兼容原版JSON格式
class BookSource implements JsSource {
  // 基础信息
  String bookSourceUrl;
  String bookSourceName;
  String? bookSourceGroup;
  int bookSourceType; // 0=文本, 1=音频, 2=图片, 3=文件
  String? bookSourceComment;
  int? lastUpdateTime;
  bool enabled;
  bool enabledExplore;
  int customOrder;
  int? respondTime;
  int weight;

  // 请求相关
  String? header;
  String? loginUrl;
  String? loginUi;
  String? loginCheckJs;
  String? bookUrlPattern;
  String? charset;
  String? coverDecodeJs;
  bool eventListener;
  bool customButton;
  bool enabledCookieJar;
  String? concurrentRate;
  String? homepageModules;

  // 搜索
  String? searchUrl;
  String? checkKeyWord;

  // 发现
  String? exploreUrl;
  String? exploreScreen;

  // 规则（嵌套JSON对象 - 原版格式）
  Map<String, dynamic>? ruleSearch;
  Map<String, dynamic>? ruleExplore;
  Map<String, dynamic>? ruleBookInfo;
  Map<String, dynamic>? ruleToc;
  Map<String, dynamic>? ruleContent;
  Map<String, dynamic>? ruleReview;
  Map<String, dynamic>? ruleImage;

  // 变量
  String? variableComment;
  String? jsLib;
  String? variable;

  // ---- JsSource 适配 ----
  @override
  String get jsUrl => bookSourceUrl;
  @override
  String get jsName => bookSourceName;
  @override
  String get jsHttpUrl =>
      bookSourceUrl.startsWith('http') ? bookSourceUrl : '';

  BookSource({
    required this.bookSourceUrl,
    required this.bookSourceName,
    this.bookSourceGroup,
    this.bookSourceType = 0,
    this.bookSourceComment,
    this.lastUpdateTime,
    this.enabled = true,
    this.enabledExplore = false,
    this.customOrder = 0,
    this.respondTime = 180000,
    this.weight = 0,
    this.header,
    this.loginUrl,
    this.loginUi,
    this.loginCheckJs,
    this.bookUrlPattern,
    this.charset,
    this.coverDecodeJs,
    this.eventListener = false,
    this.customButton = false,
    this.enabledCookieJar = false,
    this.concurrentRate,
    this.homepageModules,
    this.searchUrl,
    this.checkKeyWord,
    this.exploreUrl,
    this.exploreScreen,
    this.ruleSearch,
    this.ruleExplore,
    this.ruleBookInfo,
    this.ruleToc,
    this.ruleContent,
    this.ruleReview,
    this.ruleImage,
    this.variableComment,
    this.jsLib,
    this.variable,
  });

  /// 从JSON Map创建书源（兼容原版格式）
  factory BookSource.fromJson(Map<String, dynamic> json) {
    return BookSource(
      bookSourceUrl: json['bookSourceUrl'] ?? '',
      bookSourceName: json['bookSourceName'] ?? '',
      bookSourceGroup: json['bookSourceGroup'],
      bookSourceType: json['bookSourceType'] is int
          ? json['bookSourceType']
          : int.tryParse(json['bookSourceType']?.toString() ?? '0') ?? 0,
      bookSourceComment: json['bookSourceComment'],
      lastUpdateTime: json['lastUpdateTime'] is int
          ? json['lastUpdateTime']
          : int.tryParse(json['lastUpdateTime']?.toString() ?? '0'),
      enabled: json['enabled'] ?? true,
      enabledExplore: json['enabledExplore'] ?? false,
      customOrder: json['customOrder'] is int
          ? json['customOrder']
          : int.tryParse(json['customOrder']?.toString() ?? '0') ?? 0,
      respondTime: json['respondTime'] is int
          ? json['respondTime']
          : int.tryParse(json['respondTime']?.toString() ?? '180000') ?? 180000,
      weight: json['weight'] is int
          ? json['weight']
          : int.tryParse(json['weight']?.toString() ?? '0') ?? 0,
      header: json['header'],
      loginUrl: json['loginUrl'],
      loginUi: json['loginUi'],
      loginCheckJs: json['loginCheckJs'],
      bookUrlPattern: json['bookUrlPattern'],
      charset: json['charset'],
      coverDecodeJs: json['coverDecodeJs'],
      eventListener: json['eventListener'] ?? false,
      customButton: json['customButton'] ?? false,
      enabledCookieJar: json['enabledCookieJar'] ?? false,
      concurrentRate: json['concurrentRate']?.toString(),
      homepageModules: json['homepageModules'],
      searchUrl: json['searchUrl'],
      checkKeyWord: json['checkKeyWord'],
      exploreUrl: json['exploreUrl'],
      exploreScreen: json['exploreScreen'],
      ruleSearch: _parseRule(json['ruleSearch']),
      ruleExplore: _parseRule(json['ruleExplore']),
      ruleBookInfo: _parseRule(json['ruleBookInfo']),
      ruleToc: _parseRule(json['ruleToc']),
      ruleContent: _parseRule(json['ruleContent']),
      ruleReview: _parseRule(json['ruleReview']),
      ruleImage: _parseRule(json['ruleImage']),
      variableComment: json['variableComment'],
      jsLib: json['jsLib'],
      variable: json['variable'],
    );
  }

  static Map<String, dynamic>? _parseRule(dynamic rule) {
    if (rule == null) return null;
    if (rule is Map<String, dynamic>) return rule;
    if (rule is String) {
      try {
        final decoded = jsonDecode(rule);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {}
    }
    return null;
  }

  /// 转为JSON Map（导出/分享用）
  Map<String, dynamic> toJson() => {
    'bookSourceUrl': bookSourceUrl,
    'bookSourceName': bookSourceName,
    'bookSourceGroup': bookSourceGroup,
    'bookSourceType': bookSourceType,
    'bookSourceComment': bookSourceComment,
    'lastUpdateTime': lastUpdateTime ?? DateTime.now().millisecondsSinceEpoch,
    'enabled': enabled,
    'enabledExplore': enabledExplore,
    'customOrder': customOrder,
    'respondTime': respondTime,
    'weight': weight,
    'header': header,
    'loginUrl': loginUrl,
    'loginUi': loginUi,
    'loginCheckJs': loginCheckJs,
    'bookUrlPattern': bookUrlPattern,
    'charset': charset,
    'coverDecodeJs': coverDecodeJs,
    'eventListener': eventListener,
    'customButton': customButton,
    'enabledCookieJar': enabledCookieJar,
    'concurrentRate': concurrentRate,
    'homepageModules': homepageModules,
    'searchUrl': searchUrl,
    'checkKeyWord': checkKeyWord,
    'exploreUrl': exploreUrl,
    'exploreScreen': exploreScreen,
    'ruleSearch': ruleSearch,
    'ruleExplore': ruleExplore,
    'ruleBookInfo': ruleBookInfo,
    'ruleToc': ruleToc,
    'ruleContent': ruleContent,
    'ruleReview': ruleReview,
    'ruleImage': ruleImage,
    'variableComment': variableComment,
    'jsLib': jsLib,
    'variable': variable,
  };

  String toJsonString() => jsonEncode(toJson());

  /// 转为数据库存储格式（规则字段序列化为JSON字符串）
  Map<String, dynamic> toMap() => {
    'bookSourceUrl': bookSourceUrl,
    'bookSourceName': bookSourceName,
    'bookSourceGroup': bookSourceGroup,
    'bookSourceType': bookSourceType,
    'bookSourceComment': bookSourceComment,
    'lastUpdateTime': lastUpdateTime ?? DateTime.now().millisecondsSinceEpoch,
    'enabled': enabled ? 1 : 0,
    'enabledExplore': enabledExplore ? 1 : 0,
    'customOrder': customOrder,
    'respondTime': respondTime,
    'weight': weight,
    'header': header,
    'loginUrl': loginUrl,
    'loginUi': loginUi,
    'loginCheckJs': loginCheckJs,
    'bookUrlPattern': bookUrlPattern,
    'charset': charset,
    'coverDecodeJs': coverDecodeJs,
    'eventListener': eventListener ? 1 : 0,
    'customButton': customButton ? 1 : 0,
    'enabledCookieJar': enabledCookieJar ? 1 : 0,
    'concurrentRate': concurrentRate,
    'homepageModules': homepageModules,
    'searchUrl': searchUrl,
    'checkKeyWord': checkKeyWord,
    'exploreUrl': exploreUrl,
    'exploreScreen': exploreScreen,
    'ruleSearch': ruleSearch != null ? jsonEncode(ruleSearch) : null,
    'ruleExplore': ruleExplore != null ? jsonEncode(ruleExplore) : null,
    'ruleBookInfo': ruleBookInfo != null ? jsonEncode(ruleBookInfo) : null,
    'ruleToc': ruleToc != null ? jsonEncode(ruleToc) : null,
    'ruleContent': ruleContent != null ? jsonEncode(ruleContent) : null,
    'ruleReview': ruleReview != null ? jsonEncode(ruleReview) : null,
    'ruleImage': ruleImage != null ? jsonEncode(ruleImage) : null,
    'variableComment': variableComment,
    'jsLib': jsLib,
    'variable': variable,
  };

  /// 从数据库Map创建（规则字段从JSON字符串解析）
  factory BookSource.fromMap(Map<String, dynamic> map) => BookSource(
    bookSourceUrl: map['bookSourceUrl'] ?? '',
    bookSourceName: map['bookSourceName'] ?? '',
    bookSourceGroup: map['bookSourceGroup'],
    bookSourceType: map['bookSourceType'] is int
        ? map['bookSourceType']
        : int.tryParse(map['bookSourceType']?.toString() ?? '0') ?? 0,
    bookSourceComment: map['bookSourceComment'],
    lastUpdateTime: map['lastUpdateTime'] is int
        ? map['lastUpdateTime']
        : int.tryParse(map['lastUpdateTime']?.toString() ?? ''),
    enabled: (map['enabled'] ?? 1) == 1,
    enabledExplore: (map['enabledExplore'] ?? 0) == 1,
    customOrder: map['customOrder'] ?? 0,
    respondTime: map['respondTime'] ?? 180000,
    weight: map['weight'] ?? 0,
    header: map['header'],
    loginUrl: map['loginUrl'],
    loginUi: map['loginUi'],
    loginCheckJs: map['loginCheckJs'],
    bookUrlPattern: map['bookUrlPattern'],
    charset: map['charset'],
    coverDecodeJs: map['coverDecodeJs'],
    eventListener: (map['eventListener'] ?? 0) == 1,
    customButton: (map['customButton'] ?? 0) == 1,
    enabledCookieJar: (map['enabledCookieJar'] ?? 0) == 1,
    concurrentRate: map['concurrentRate']?.toString(),
    homepageModules: map['homepageModules'],
    searchUrl: map['searchUrl'],
    checkKeyWord: map['checkKeyWord'],
    exploreUrl: map['exploreUrl'],
    exploreScreen: map['exploreScreen'],
    ruleSearch: _parseRule(map['ruleSearch']),
    ruleExplore: _parseRule(map['ruleExplore']),
    ruleBookInfo: _parseRule(map['ruleBookInfo']),
    ruleToc: _parseRule(map['ruleToc']),
    ruleContent: _parseRule(map['ruleContent']),
    ruleReview: _parseRule(map['ruleReview']),
    ruleImage: _parseRule(map['ruleImage']),
    variableComment: map['variableComment'],
    variable: map['variable'],
  );

  // 兼容旧方法名
  Map<String, dynamic> toDbMap() => toMap();
  factory BookSource.fromDbMap(Map<String, dynamic> map) => BookSource.fromMap(map);

  static BookSource fromJsonString(String str) => BookSource.fromJson(jsonDecode(str));

  static List<BookSource> fromJsonStringList(String str) {
    final decoded = jsonDecode(str);
    if (decoded is List) {
      return decoded.whereType<Map<String, dynamic>>().map((e) => BookSource.fromJson(e)).toList();
    } else if (decoded is Map<String, dynamic>) {
      return [BookSource.fromJson(decoded)];
    }
    return [];
  }

  // 搜索规则快捷访问
  String? get searchBookList => ruleSearch?['bookList'];
  String? get searchName => ruleSearch?['name'];
  String? get searchAuthor => ruleSearch?['author'];
  String? get searchCoverUrl => ruleSearch?['coverUrl'];
  String? get searchBookUrl => ruleSearch?['bookUrl'];
  String? get searchIntro => ruleSearch?['intro'];
  String? get searchKind => ruleSearch?['kind'];
  String? get searchLastChapter => ruleSearch?['lastChapter'];
  String? get searchWordCount => ruleSearch?['wordCount'];

  // 目录规则快捷访问
  String? get tocChapterList => ruleToc?['chapterList'];
  String? get tocChapterName => ruleToc?['chapterName'];
  String? get tocChapterUrl => ruleToc?['chapterUrl'];
  String? get tocNextUrl => ruleToc?['nextTocUrl'];
  String? get tocIsVip => ruleToc?['isVip'];

  // 正文规则快捷访问
  String? get contentRule => ruleContent?['content'];
  String? get contentNextUrl => ruleContent?['nextContentUrl'];
  String? get contentWebJs => ruleContent?['webJs'];
  String? get contentSourceRegex => ruleContent?['sourceRegex'];

  // 详情规则快捷访问
  String? get bookInfoName => ruleBookInfo?['name'];
  String? get bookInfoAuthor => ruleBookInfo?['author'];
  String? get bookInfoCover => ruleBookInfo?['coverUrl'];
  String? get bookInfoIntro => ruleBookInfo?['intro'];
  String? get bookInfoKind => ruleBookInfo?['kind'];
  String? get bookInfoLastChapter => ruleBookInfo?['lastChapter'];
  String? get bookInfoTocUrl => ruleBookInfo?['tocUrl'];
}
