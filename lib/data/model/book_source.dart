import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:legado_md3/constant/app_const.dart';
import 'package:legado_md3/constant/book_type.dart';
import 'package:legado_md3/data/model/rule/book_info_rule.dart';
import 'package:legado_md3/data/model/rule/content_rule.dart';
import 'package:legado_md3/data/model/rule/explore_rule.dart';
import 'package:legado_md3/data/model/rule/review_rule.dart';
import 'package:legado_md3/data/model/rule/search_rule.dart';
import 'package:legado_md3/data/model/rule/toc_rule.dart';
import 'package:legado_md3/help/source/js/js_source.dart';

/// Legado书源模型 - 完全兼容原版JSON格式
class BookSource implements JsSource {
  // 基础信息
  String bookSourceUrl;
  String bookSourceName;
  String? bookSourceGroup;
  int bookSourceType; // 0=文本, 1=音频, 2=图片, 3=文件, 4=视频（legado 标准）
  String? bookSourceComment;
  @override
  int? lastUpdateTime;
  bool enabled;
  bool enabledExplore;
  int customOrder;
  int? respondTime;
  int weight;

  // 请求相关
  @override
  String? header;
  @override
  String? loginUrl;
  String? loginUi;
  String? loginCheckJs;
  String? bookUrlPattern;
  String? charset;
  String? coverDecodeJs;
  bool eventListener;
  /// 事件回调脚本：读者交互/生命周期事件发生时由引擎执行。
  String callBackJs;
  bool customButton;
  @override
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

  // 变量规则（@put:/@get: 跨步骤传值，如登录后拿 token 传给后续请求）。
  // 参与导入/导出（fromJson/toJson）与数据库读写（toMap/fromMap），
  // book_sources 表已含 rulePut/ruleGet 两列。
  String? rulePut;
  String? ruleGet;

  // 变量
  @override
  String? variableComment;
  @override
  String? jsLib;
  @override
  String? variable;

  /// 未知扩展字段透传：社区书源常携带模型未显式声明的字段（如
  /// httpUserAgent / _conflux_version / 自定义元数据）。导入时原样保留，
  /// 导出/分享时回写，保证 fromJson → toJson 往返零丢失。
  Map<String, dynamic> extraFields;

  // ---- JsSource 适配 ----
  @override
  String get jsUrl => bookSourceUrl;
  @override
  String get jsName => bookSourceName;
  @override
  String get jsHttpUrl => bookSourceUrl.startsWith('http') ? bookSourceUrl : '';
  @override
  String get jsGroup => bookSourceGroup ?? '';
  @override
  String get jsComment => bookSourceComment ?? '';
  @override
  int get jsType => bookSourceType;
  @override
  String get jsBookUrlPattern => bookUrlPattern ?? '';
  @override
  int get jsConcurrentRate => int.tryParse(concurrentRate ?? '') ?? 0;
  @override
  bool get jsEnabledExplore => enabledExplore;
  @override
  String get jsExploreUrl => exploreUrl ?? '';
  @override
  String get jsSearchUrl => searchUrl ?? '';
  @override
  String get jsTocUrl => ruleBookInfo?['tocUrl'] ?? '';
  @override
  String get jsRuleBookUrlPattern => ruleBookInfo?['bookUrlPattern'] ?? '';

  BookSource({
    required this.bookSourceUrl,
    required this.bookSourceName,
    this.bookSourceGroup,
    this.bookSourceType = 0,
    this.bookSourceComment,
    this.lastUpdateTime = 0,
    this.enabled = true,
    this.enabledExplore = true,
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
    this.callBackJs = '',
    this.customButton = false,
    this.enabledCookieJar = true,
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
    this.rulePut,
    this.ruleGet,
    this.variableComment,
    this.jsLib,
    this.variable,
    Map<String, dynamic>? extraFields,
  }) : extraFields = extraFields ?? const <String, dynamic>{};

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
          : int.tryParse(json['lastUpdateTime']?.toString() ?? '0') ?? 0,
      enabled: json['enabled'] ?? true,
      enabledExplore: json['enabledExplore'] ?? true,
      customOrder: json['customOrder'] is int
          ? json['customOrder']
          : int.tryParse(json['customOrder']?.toString() ?? '0') ?? 0,
      respondTime: json['respondTime'] is int
          ? json['respondTime']
          : int.tryParse(json['respondTime']?.toString() ?? '180000') ?? 180000,
      weight: json['weight'] is int
          ? json['weight']
          : int.tryParse(json['weight']?.toString() ?? '0') ?? 0,
      header: _asRuleString(json['header']),
      loginUrl: _asRuleString(json['loginUrl']),
      loginUi: _asRuleString(json['loginUi']),
      loginCheckJs: _asRuleString(json['loginCheckJs']),
      bookUrlPattern: _asRuleString(json['bookUrlPattern']),
      charset: _asRuleString(json['charset']),
      coverDecodeJs: _asRuleString(json['coverDecodeJs']),
      eventListener: json['eventListener'] ?? false,
      callBackJs: json['callBackJs'] ?? '',
      customButton: json['customButton'] ?? false,
      enabledCookieJar: json['enabledCookieJar'] ?? true,
      concurrentRate: json['concurrentRate']?.toString(),
      homepageModules: json['homepageModules'],
      searchUrl: _asRuleString(json['searchUrl']),
      checkKeyWord: _asRuleString(json['checkKeyWord']),
      exploreUrl: _asRuleString(json['exploreUrl']),
      exploreScreen: _asRuleString(json['exploreScreen']),
      ruleSearch: _parseRule(json['ruleSearch']),
      ruleExplore: _parseRule(json['ruleExplore']),
      ruleBookInfo: _parseRule(json['ruleBookInfo']),
      ruleToc: _parseRule(json['ruleToc']),
      ruleContent: _parseRule(json['ruleContent']),
      ruleReview: _parseRule(json['ruleReview']),
      ruleImage: _parseRule(json['ruleImage']),
      rulePut: _asRuleString(json['rulePut']),
      ruleGet: _asRuleString(json['ruleGet']),
      variableComment: _asRuleString(json['variableComment']),
      jsLib: _asRuleString(json['jsLib']),
      variable: _asRuleString(json['variable']),
      extraFields: _collectExtra(json),
    );
  }

  /// 规则/脚本文本字段有时以 JSON 对象/数组形态出现在社区书源里（如
  /// header 直接写成对象），统一转为 JSON 字符串，避免强转崩溃。
  static String? _asRuleString(dynamic v) {
    if (v == null) return null;
    if (v is String) return v;
    if (v is Map || v is List) return jsonEncode(v);
    return v.toString();
  }

  static Map<String, dynamic>? _parseRule(dynamic rule) {
    if (rule == null) return null;
    if (rule is Map<String, dynamic>) return rule;
    if (rule is Map) return Map<String, dynamic>.from(rule);
    if (rule is String) {
      try {
        final decoded = jsonDecode(rule);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {}
    }
    // 空列表 / 其他形态：规约成空规则 Map，引擎按「无规则」处理。
    if (rule is List && rule.isEmpty) return <String, dynamic>{};
    return null;
  }

  /// 模型未显式声明的键原样收集（含自定义元数据），供导出时回写。
  static const Set<String> _knownKeys = {
    'bookSourceUrl', 'bookSourceName', 'bookSourceGroup', 'bookSourceType',
    'bookSourceComment', 'lastUpdateTime', 'enabled', 'enabledExplore',
    'customOrder', 'respondTime', 'weight', 'header', 'loginUrl', 'loginUi',
    'loginCheckJs', 'bookUrlPattern', 'charset', 'coverDecodeJs',
    'eventListener', 'callBackJs', 'customButton', 'enabledCookieJar',
    'concurrentRate', 'homepageModules', 'searchUrl', 'checkKeyWord',
    'exploreUrl', 'exploreScreen', 'ruleSearch', 'ruleExplore', 'ruleBookInfo',
    'ruleToc', 'ruleContent', 'ruleReview', 'ruleImage', 'rulePut', 'ruleGet',
    'variableComment', 'jsLib', 'variable',
  };

  static Map<String, dynamic> _collectExtra(Map<String, dynamic> json) {
    final extra = <String, dynamic>{};
    for (final entry in json.entries) {
      final k = entry.key;
      final v = entry.value;
      if (!_knownKeys.contains(k)) {
        extra[k] = v; // 未知键原样
        continue;
      }
      // 已知键若原始形态与模型规范化后的形态不同，也保留原值，
      // 使 toJson 能无损还原原版书源格式（分享/导入往返一致）。
      if (k == 'ruleSearch' || k == 'ruleExplore' || k == 'ruleBookInfo' ||
          k == 'ruleToc' || k == 'ruleContent' || k == 'ruleReview' ||
          k == 'ruleImage') {
        final normalized = _parseRule(v);
        if (normalized == null ||
            (v is List && v.isEmpty) ||
            v is String) {
          extra[k] = v; // 空数组 / JSON字符串形态 → 保留原始
        }
      } else if (k == 'header' || k == 'loginUrl' || k == 'loginUi' ||
          k == 'loginCheckJs' || k == 'bookUrlPattern' || k == 'charset' ||
          k == 'coverDecodeJs' || k == 'rulePut' || k == 'ruleGet' ||
          k == 'variableComment' || k == 'jsLib' || k == 'variable' ||
          k == 'searchUrl' || k == 'checkKeyWord' || k == 'exploreUrl' ||
          k == 'exploreScreen') {
        if (v is Map || v is List) extra[k] = v; // 非字符串形态 → 保留原始
      }
    }
    return Map.unmodifiable(extra);
  }

  /// 转为JSON Map（导出/分享用）
  Map<String, dynamic> toJson() => {
        'bookSourceUrl': bookSourceUrl,
        'bookSourceName': bookSourceName,
        'bookSourceGroup': bookSourceGroup,
        'bookSourceType': bookSourceType,
        'bookSourceComment': bookSourceComment,
        'lastUpdateTime':
            lastUpdateTime ?? DateTime.now().millisecondsSinceEpoch,
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
        'callBackJs': callBackJs,
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
        'rulePut': rulePut,
        'ruleGet': ruleGet,
        'variableComment': variableComment,
        'jsLib': jsLib,
        'variable': variable,
        // 未知扩展字段原样回写（键集合与上面已知字段互斥，无覆盖风险）
        ...extraFields,
      };

  String toJsonString() => jsonEncode(toJson());

  /// 转为数据库存储格式（规则字段序列化为JSON字符串）
  Map<String, dynamic> toMap() => {
        'bookSourceUrl': bookSourceUrl,
        'bookSourceName': bookSourceName,
        'bookSourceGroup': bookSourceGroup,
        'bookSourceType': bookSourceType,
        'bookSourceComment': bookSourceComment,
        'lastUpdateTime':
            lastUpdateTime ?? DateTime.now().millisecondsSinceEpoch,
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
        'callBackJs': callBackJs,
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
        'rulePut': rulePut,
        'ruleGet': ruleGet,
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
            : int.tryParse(map['lastUpdateTime']?.toString() ?? '0') ?? 0,
        enabled: (map['enabled'] ?? 1) == 1,
        enabledExplore: (map['enabledExplore'] ?? 1) == 1,
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
        callBackJs: map['callBackJs'] ?? '',
        customButton: (map['customButton'] ?? 0) == 1,
        enabledCookieJar: (map['enabledCookieJar'] ?? 1) == 1,
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
        jsLib: map['jsLib'],
        variable: map['variable'],
        rulePut: map['rulePut'],
        ruleGet: map['ruleGet'],
      );

  // 兼容旧方法名
  Map<String, dynamic> toDbMap() => toMap();
  factory BookSource.fromDbMap(Map<String, dynamic> map) =>
      BookSource.fromMap(map);

  static BookSource fromJsonString(String str) =>
      BookSource.fromJson(jsonDecode(str));

  static List<BookSource> fromJsonStringList(String str) {
    final decoded = jsonDecode(str);
    if (decoded is List) {
      return decoded
          .whereType<Map<String, dynamic>>()
          .map((e) => BookSource.fromJson(e))
          .toList();
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

  /// 调试页推荐关键词：legado 定义在 `ruleSearch.checkKeyWord`
  /// （BookSourceDebugActivity 直接读该字段），部分源写在顶层，
  /// 这里统一回退取值（不校验用户输入，仅作调试默认值）。
  String? get effectiveCheckKeyWord {
    final fromRule = ruleSearch?['checkKeyWord']?.toString();
    if (fromRule != null && fromRule.trim().isNotEmpty) return fromRule;
    return checkKeyWord;
  }

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

  // ---- 强类型规则视图（现有 Map getter 保持不变）----

  SearchRule? get ruleSearchTyped =>
      ruleSearch == null ? null : SearchRule.fromJson(ruleSearch);

  ExploreRule? get ruleExploreTyped =>
      ruleExplore == null ? null : ExploreRule.fromJson(ruleExplore);

  BookInfoRule? get ruleBookInfoTyped =>
      ruleBookInfo == null ? null : BookInfoRule.fromJson(ruleBookInfo);

  TocRule? get ruleTocTyped =>
      ruleToc == null ? null : TocRule.fromJson(ruleToc);

  ContentRule? get ruleContentTyped =>
      ruleContent == null ? null : ContentRule.fromJson(ruleContent);

  ReviewRule? get ruleReviewTyped =>
      ruleReview == null ? null : ReviewRule.fromJson(ruleReview);

  // ---- 判等 ----

  /// 按书源地址判等。
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BookSource && other.bookSourceUrl == bookSourceUrl);

  @override
  int get hashCode => bookSourceUrl.hashCode;

  /// 全字段比对（含嵌套规则深比较），判等之外的严格相等判断。
  bool equal(BookSource other) =>
      const DeepCollectionEquality().equals(_equalMap(), other._equalMap());

  Map<String, dynamic> _equalMap() => <String, dynamic>{
        'bookSourceUrl': bookSourceUrl,
        'bookSourceName': bookSourceName,
        'bookSourceGroup': bookSourceGroup,
        'bookSourceType': bookSourceType,
        'bookSourceComment': bookSourceComment,
        'lastUpdateTime': lastUpdateTime,
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
        'callBackJs': callBackJs,
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
        'rulePut': rulePut,
        'ruleGet': ruleGet,
        'variableComment': variableComment,
        'jsLib': jsLib,
        'variable': variable,
      };

  // ---- 分组 / 展示辅助 ----

  /// 分组串是否包含指定分组（按统一分隔符拆分后精确匹配）。
  bool hasGroup(String group) {
    final g = group.trim();
    if (g.isEmpty) return false;
    return AppConst.splitGroups(bookSourceGroup).contains(g);
  }

  /// 展示用「源名（分组）」；无分组时只返回源名。
  String getDisplayNameGroup() {
    final group = bookSourceGroup?.trim() ?? '';
    return group.isEmpty ? bookSourceName : '$bookSourceName ($group)';
  }

  /// 变量注释的展示文本：逐行去掉 `//` 前缀并过滤空行。
  String getDisplayVariableComment() {
    final raw = variableComment;
    if (raw == null || raw.trim().isEmpty) return '';
    return raw
        .split('\n')
        .map((line) {
          final t = line.trim();
          return t.startsWith('//') ? t.substring(2).trim() : t;
        })
        .where((line) => line.isNotEmpty)
        .join('\n');
  }

  /// 按书源类型返回位标志值。
  int getBookType() {
    switch (bookSourceType) {
      case BookSourceType.audio:
        return BookType.audio;
      case BookSourceType.image:
        return BookType.image;
      case BookSourceType.file:
        return BookType.webFile;
      case BookSourceType.video:
        return BookType.video;
      default:
        return BookType.text;
    }
  }

  /// 取校验关键字：优先规则内的纯文本关键字，其次顶层关键字，最后回退值。
  /// 含链接 / 正则 / 规则片段特征的文本不作为关键字。
  String checkKeywordOf([String fallback = '我的']) {
    String? pick(String? raw) {
      final t = raw?.trim() ?? '';
      if (t.isEmpty) return null;
      if (t.contains('http') ||
          t.contains('::') ||
          t.contains('++') ||
          t.contains('--')) {
        return null;
      }
      if (RegExp(r'[\\\[\](){}^$*+?|]').hasMatch(t)) return null;
      return t;
    }

    return pick(ruleSearch?['checkKeyWord']?.toString()) ??
        pick(checkKeyWord) ??
        fallback;
  }
}
