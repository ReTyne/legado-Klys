import 'package:legado_md3/help/source/js/js_source.dart';

/// RSS订阅源模型 - 对齐原版RssSource
class RssSource implements JsSource {
  int? id;
  String sourceName;
  String sourceUrl;
  String? sourceIcon;
  String? sourceGroup;
  String? sourceComment;
  String? searchUrl;
  String? sortUrl;
  String? loginUrl;
  String? loginUi;
  String? loginCheckJs;
  String? coverDecodeJs;
  String? header;
  String? variableComment;
  String? concurrentRate;
  String? jsLib;
  // Start规则
  String? startHtml;
  String? startStyle;
  String? startJs;
  String? preloadJs;
  // List规则
  String? ruleArticles;
  String? ruleNextPage;
  String? ruleTitle;
  String? rulePubDate;
  String? ruleDescription;
  String? ruleImage;
  String? ruleLink;
  // WebView规则
  String? ruleContent;
  String? style;
  String? injectJs;
  String? contentWhitelist;
  String? contentBlacklist;
  String? shouldOverrideUrlLoading;
  // 状态
  bool? enabled;
  int? customOrder;
  int? lastUpdateTime;
  int? unreadCount;

  // 运行时 / 兼容字段
  @override
  String? variable;
  @override
  bool enabledCookieJar;
  int? articleStyle; // JSON articleStyle（0 默认 / 1 图片 / 2 视频等）
  bool enableJs;
  bool loadWithBaseUrl;
  bool preload;
  bool singleUrl;
  bool cacheFirst;
  String? redirectPolicy;
  int sourceType;

  // ---- JsSource 适配 ----
  @override
  String get jsUrl => sourceUrl;
  @override
  String get jsName => sourceName;
  @override
  String get jsHttpUrl => sourceUrl.startsWith('http') ? sourceUrl : '';

  // 兼容别名
  String get name => sourceName;
  set name(String v) => sourceName = v;
  String get url => sourceUrl;
  set url(String v) => sourceUrl = v;
  String? get group => sourceGroup;
  set group(String? v) => sourceGroup = v;
  String? get icon => sourceIcon;
  set icon(String? v) => sourceIcon = v;

  RssSource({
    this.id,
    String sourceName = '',
    String sourceUrl = '',
    this.sourceIcon,
    this.sourceGroup,
    this.sourceComment,
    this.searchUrl,
    this.sortUrl,
    this.loginUrl,
    this.loginUi,
    this.loginCheckJs,
    this.coverDecodeJs,
    this.header,
    this.variableComment,
    this.concurrentRate,
    this.jsLib,
    this.startHtml,
    this.startStyle,
    this.startJs,
    this.preloadJs,
    this.ruleArticles,
    this.ruleNextPage,
    this.ruleTitle,
    this.rulePubDate,
    this.ruleDescription,
    this.ruleImage,
    this.ruleLink,
    this.ruleContent,
    this.style,
    this.injectJs,
    this.contentWhitelist,
    this.contentBlacklist,
    this.shouldOverrideUrlLoading,
    this.enabled = true,
    this.customOrder,
    this.lastUpdateTime,
    this.unreadCount = 0,
    this.variable,
    this.enabledCookieJar = false,
    this.articleStyle,
    this.enableJs = false,
    this.loadWithBaseUrl = false,
    this.preload = false,
    this.singleUrl = false,
    this.cacheFirst = false,
    this.redirectPolicy,
    this.sourceType = 0,
  })  : sourceName = sourceName,
        sourceUrl = sourceUrl;

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': sourceName,
    'url': sourceUrl,
    'sourceIcon': sourceIcon,
    'group_name': sourceGroup,
    'sourceComment': sourceComment,
    'searchUrl': searchUrl,
    'sortUrl': sortUrl,
    'loginUrl': loginUrl,
    'loginUi': loginUi,
    'loginCheckJs': loginCheckJs,
    'coverDecodeJs': coverDecodeJs,
    'header': header,
    'variableComment': variableComment,
    'concurrentRate': concurrentRate,
    'jsLib': jsLib,
    'startHtml': startHtml,
    'startStyle': startStyle,
    'startJs': startJs,
    'preloadJs': preloadJs,
    'ruleArticles': ruleArticles,
    'ruleNextPage': ruleNextPage,
    'ruleTitle': ruleTitle,
    'rulePubDate': rulePubDate,
    'ruleDescription': ruleDescription,
    'ruleImage': ruleImage,
    'ruleLink': ruleLink,
    'ruleContent': ruleContent,
    'style': style,
    'injectJs': injectJs,
    'contentWhitelist': contentWhitelist,
    'contentBlacklist': contentBlacklist,
    'shouldOverrideUrlLoading': shouldOverrideUrlLoading,
    'enabled': enabled == true ? 1 : 0,
    'customOrder': customOrder,
    'lastUpdateTime': lastUpdateTime,
    'unreadCount': unreadCount,
    'variable': variable,
    'enabledCookieJar': enabledCookieJar ? 1 : 0,
  };

  factory RssSource.fromMap(Map<String, dynamic> map) => RssSource(
    id: map['id'] as int?,
    sourceName: (map['name'] ?? map['sourceName'] ?? '') as String,
    sourceUrl: (map['url'] ?? map['sourceUrl'] ?? '') as String,
    sourceIcon: map['sourceIcon'] as String?,
    sourceGroup: map['group_name'] as String? ?? map['sourceGroup'] as String?,
    sourceComment: map['sourceComment'] as String?,
    searchUrl: map['searchUrl'] as String?,
    sortUrl: map['sortUrl'] as String?,
    loginUrl: map['loginUrl'] as String?,
    loginUi: map['loginUi'] as String?,
    loginCheckJs: map['loginCheckJs'] as String?,
    coverDecodeJs: map['coverDecodeJs'] as String?,
    header: map['header'] as String?,
    variableComment: map['variableComment'] as String?,
    concurrentRate: map['concurrentRate'] as String?,
    jsLib: map['jsLib'] as String?,
    startHtml: map['startHtml'] as String?,
    startStyle: map['startStyle'] as String?,
    startJs: map['startJs'] as String?,
    preloadJs: map['preloadJs'] as String?,
    ruleArticles: map['ruleArticles'] as String?,
    ruleNextPage: map['ruleNextPage'] as String?,
    ruleTitle: map['ruleTitle'] as String?,
    rulePubDate: map['rulePubDate'] as String?,
    ruleDescription: map['ruleDescription'] as String?,
    ruleImage: map['ruleImage'] as String?,
    ruleLink: map['ruleLink'] as String?,
    ruleContent: map['ruleContent'] as String?,
    style: map['style'] as String?,
    injectJs: map['injectJs'] as String?,
    contentWhitelist: map['contentWhitelist'] as String?,
    contentBlacklist: map['contentBlacklist'] as String?,
    shouldOverrideUrlLoading: map['shouldOverrideUrlLoading'] as String?,
    enabled: (map['enabled'] as int?) == 1,
    customOrder: map['customOrder'] as int?,
    lastUpdateTime: map['lastUpdateTime'] as int?,
    unreadCount: map['unreadCount'] as int? ?? 0,
    variable: map['variable'] as String?,
    enabledCookieJar: (map['enabledCookieJar'] as int?) == 1,
    articleStyle: map['articleStyle'] is int
        ? map['articleStyle'] as int
        : int.tryParse(map['articleStyle']?.toString() ?? ''),
  );

  /// 原版JSON格式兼容
  Map<String, dynamic> toJson() => {
    'sourceName': sourceName,
    'sourceUrl': sourceUrl,
    'sourceIcon': sourceIcon,
    'sourceGroup': sourceGroup,
    'sourceComment': sourceComment,
    'searchUrl': searchUrl,
    'sortUrl': sortUrl,
    'loginUrl': loginUrl,
    'loginUi': loginUi,
    'loginCheckJs': loginCheckJs,
    'coverDecodeJs': coverDecodeJs,
    'header': header,
    'variableComment': variableComment,
    'concurrentRate': concurrentRate,
    'jsLib': jsLib,
    'articleStyle': articleStyle ?? int.tryParse(startStyle ?? ''),
    'ruleArticles': ruleArticles,
    'ruleNextPage': ruleNextPage,
    'ruleTitle': ruleTitle,
    'rulePubDate': rulePubDate,
    'ruleDescription': ruleDescription,
    'ruleImage': ruleImage,
    'ruleLink': ruleLink,
    'ruleContent': ruleContent,
    'style': style,
    'injectJs': injectJs,
    'contentWhitelist': contentWhitelist,
    'contentBlacklist': contentBlacklist,
    'shouldOverrideUrlLoading': shouldOverrideUrlLoading,
    'enabled': enabled,
    'enabledCookieJar': enabledCookieJar,
    'enableJs': enableJs,
    'loadWithBaseUrl': loadWithBaseUrl,
    'preload': preload,
    'singleUrl': singleUrl,
    'cacheFirst': cacheFirst,
    'redirectPolicy': redirectPolicy,
    'customOrder': customOrder,
    'lastUpdateTime': lastUpdateTime,
    'type': sourceType,
  };

  factory RssSource.fromJson(Map<String, dynamic> json) => RssSource(
    sourceName: json['sourceName'] as String? ?? '',
    sourceUrl: json['sourceUrl'] as String? ?? '',
    sourceIcon: json['sourceIcon'] as String?,
    sourceGroup: json['sourceGroup'] as String?,
    sourceComment: json['sourceComment'] as String?,
    searchUrl: json['searchUrl'] as String?,
    sortUrl: json['sortUrl'] as String?,
    loginUrl: json['loginUrl'] as String?,
    loginUi: json['loginUi'] as String?,
    loginCheckJs: json['loginCheckJs'] as String?,
    coverDecodeJs: json['coverDecodeJs'] as String?,
    header: json['header'] as String?,
    variableComment: json['variableComment'] as String?,
    concurrentRate: json['concurrentRate'] as String?,
    jsLib: json['jsLib'] as String?,
    startStyle: json['articleStyle']?.toString(),
    articleStyle: json['articleStyle'] is int
        ? json['articleStyle'] as int
        : int.tryParse(json['articleStyle']?.toString() ?? ''),
    ruleArticles: json['ruleArticles'] as String?,
    ruleNextPage: json['ruleNextPage'] as String?,
    ruleTitle: json['ruleTitle'] as String?,
    rulePubDate: json['rulePubDate'] as String?,
    ruleDescription: json['ruleDescription'] as String?,
    ruleImage: json['ruleImage'] as String?,
    ruleLink: json['ruleLink'] as String?,
    ruleContent: json['ruleContent'] as String?,
    style: json['style'] as String?,
    injectJs: json['injectJs'] as String?,
    contentWhitelist: json['contentWhitelist'] as String?,
    contentBlacklist: json['contentBlacklist'] as String?,
    shouldOverrideUrlLoading: json['shouldOverrideUrlLoading'] as String?,
    enabled: json['enabled'] as bool? ?? true,
    enabledCookieJar: json['enabledCookieJar'] as bool? ?? false,
    enableJs: json['enableJs'] as bool? ?? false,
    loadWithBaseUrl: json['loadWithBaseUrl'] as bool? ?? false,
    preload: json['preload'] as bool? ?? false,
    singleUrl: json['singleUrl'] as bool? ?? false,
    cacheFirst: json['cacheFirst'] as bool? ?? false,
    redirectPolicy: json['redirectPolicy']?.toString(),
    customOrder: json['customOrder'] is int
        ? json['customOrder'] as int
        : int.tryParse(json['customOrder']?.toString() ?? ''),
    lastUpdateTime: json['lastUpdateTime'] is int
        ? json['lastUpdateTime'] as int
        : int.tryParse(json['lastUpdateTime']?.toString() ?? ''),
    sourceType: json['type'] is int
        ? json['type'] as int
        : int.tryParse(json['type']?.toString() ?? '') ?? 0,
  );
}
