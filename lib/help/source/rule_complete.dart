/// 「规则串智能补全」。
///
/// 书源里的字段规则常常只写了选择器（如 `class.item`），没写取值方式。
/// 上游在编辑页开启「自动补全」后，会按字段类型补上 getter：
/// - type 1 文字：`@text` / XPath `//text()`
/// - type 2 链接：`@href` / XPath `//@href`
/// - type 3 图片：`@src` / XPath `//@src`
///
/// 易被忽略的细节（本实现逐条复刻）：
/// 1. 尾部 `##正则##替换` 与 `,{...}` 参数原样保留，绝不参与补全；
/// 2. 含 `{{}}` / `<js>` / `@js:` / `@Json:` / `$.` 或以 `:`、`##` 开头的
///    复杂规则**不补全**（上游 `notComplete`），避免破坏脚本与 JSONPath；
/// 3. `preRule`（列表/初始化规则）含上述复杂语法时，整个字段也不补全；
/// 4. `&&` / `%%` / `||` 连接的每一段单独判断是否已带 getter，已带则不动；
/// 5. type 1 时把 `img...text` 修正为取 `@alt`（上游 `fixImgInfo`）；
/// 6. XPath 规则以 `//` 或 `@Xpath:` 开头时，getter 用 XPath 形式。
library;

/// 规则串补全器（纯函数，无副作用，便于单元回归）。
class RuleComplete {
  RuleComplete._();

  /// 1 文字（默认）
  static const int typeText = 1;

  /// 2 链接
  static const int typeLink = 2;

  /// 3 图片
  static const int typeImage = 3;

  /// 上游 `notComplete`：`^:|^##|\{\{|@js:|<js>|@Json:|\$\.`
  /// 命中即认为规则过于复杂，不做补全。
  static final RegExp _notComplete =
      RegExp(r'^(?::|##)|(?:\{\{|@js:|<js>|@Json:|\$\.)');

  /// 上游 `rules.split("##|,\{", 2)`：尾部正则替换 / 参数的分隔符。
  static final RegExp _tailSplit = RegExp(r'##|,\{');

  /// 上游 `isXpath`：`^//|^@Xpath:`
  static final RegExp _isXpath =
      RegExp(r'^//|^@Xpath:', caseSensitive: false);

  /// 上游 `needComplete` 的 seq 部分：`&&` / `%%` / `||`
  static final RegExp _connectors = RegExp(r'&&|%%|\|\|');

  /// 上游 `needComplete` 负向后顾里的 getter 名。
  static const String _getterNames =
      r'attr|text|ownText|textNodes|href|content|html|alt|all|value|src';

  /// 段末尾是否已经带了 getter（`@text` / `/text()` / 段本身就是 `text`）。
  ///  `(?<!(@|/|^|[|%&]{2})(getter)(\(\))?)` 的语义。
  static final RegExp _getterSuffix =
      RegExp(r'(?:@|/|^)(?:' + _getterNames + r')(?:\(\))?$');

  /// 上游 `fixImgInfo`：img 元素 + 可选属性 + `@`/`/` 分隔 + `text()`。
  /// 前瞻保证只匹配到规则单元末尾（连接符之前或整串结尾）。
  static final RegExp _imgText = RegExp(
      r'img((?:\[@?[^\]]+\])|(?:\.[-\w]+))?[@/]+text(?:\(\))?(?=&&|%%|\|\||$)');

  /// 按字段名返回补全类型；返回 null 表示该字段不是取值规则，不参与补全。
  ///
  ///  `BookSourceEditActivity` / `RssSourceEditActivity` 保存时对每个
  /// 字段调用 `ruleComplete(rule, preRule, type)` 的 type 实参：
  /// 封面/图片 → 3，各类 URL → 2，其余文本 → 1；
  /// 列表规则（bookList / chapterList / ruleArticles）、init、各类 JS 与开关
  /// 字段**不补全**。书源与 RSS 两套字段名在此统一映射。
  static int? fieldType(String key) {
    switch (key) {
      case 'coverUrl':
      case 'ruleImage':
        return typeImage;
      case 'bookUrl':
      case 'tocUrl':
      case 'chapterUrl':
      case 'nextTocUrl':
      case 'nextContentUrl':
      case 'ruleNextPage':
        return typeLink;
      case 'name':
      case 'author':
      case 'intro':
      case 'kind':
      case 'wordCount':
      case 'lastChapter':
      case 'chapterName':
      case 'content':
      case 'title':
      case 'subContent':
      case 'downloadUrls':
      case 'ruleTitle':
      case 'rulePubDate':
      case 'ruleDescription':
      case 'ruleLink':
      case 'ruleContent':
        return typeText;
      default:
        return null;
    }
  }

  /// 某个规则组的「前置规则」字段名（上游 preRule 实参）。
  /// 正文组上游不带 preRule，返回 null。
  static String? preRuleKey(String group) {
    switch (group) {
      case 'ruleSearch':
      case 'ruleExplore':
        return 'bookList';
      case 'ruleBookInfo':
        return 'init';
      case 'ruleToc':
        return 'chapterList';
      default:
        return null;
    }
  }

  /// 对一条规则串做补全。
  ///
  /// [rules] 字段规则串；[preRule] 该组的前置规则（列表规则 / init），
  /// 用于上游同样的「前置规则复杂则整体不补全」容错；[type] 见常量。
  /// 返回补全后的规则，或原规则（不补全时原样返回，可能为 null）。
  static String? autoComplete(
    String? rules, {
    String? preRule,
    int type = typeText,
  }) {
    if (rules == null || rules.isEmpty) return rules;
    // 细节 2 / 3：复杂规则、或前置规则复杂 → 不补全
    if (_notComplete.hasMatch(rules)) return rules;
    if (preRule != null && preRule.isNotEmpty &&
        _notComplete.hasMatch(preRule)) {
      return rules;
    }
    if (type != typeText && type != typeLink && type != typeImage) {
      return rules;
    }

    // 细节 1：分离并保留尾部 `##...` / `,{...}`
    final tailMatch = _tailSplit.firstMatch(rules);
    final String cleaned;
    final String tail;
    if (tailMatch != null) {
      cleaned = rules.substring(0, tailMatch.start);
      tail = rules.substring(tailMatch.start);
    } else {
      cleaned = rules;
      tail = '';
    }
    if (cleaned.isEmpty) return rules;

    // 细节 6：XPath 用 XPath 形式 getter
    final bool xpath = _isXpath.hasMatch(cleaned);
    final String getter;
    if (type == typeLink) {
      getter = xpath ? '//@href' : '@href';
    } else if (type == typeImage) {
      getter = xpath ? '//@src' : '@src';
    } else {
      getter = xpath ? '//text()' : '@text';
    }

    // 细节 4：按连接符分段补全
    final completed = _completeSegments(cleaned, getter);
    // 细节 5：图片取 text 修正为取 alt
    final String result = type == typeText
        ? _fixImgText(completed, xpath: xpath)
        : completed;
    return result + tail;
  }

  /// 把 [rule] 按 `&&` / `%%` / `||` 切成段，逐段在末尾补 [getter]。
  /// 等价于上游 `needComplete.replace(cleanedRule, "$getter${seq}")`。
  static String _completeSegments(String rule, String getter) {
    final buf = StringBuffer();
    var start = 0;
    for (final m in _connectors.allMatches(rule)) {
      buf.write(_appendGetter(rule.substring(start, m.start), getter));
      buf.write(m.group(0));
      start = m.end;
    }
    buf.write(_appendGetter(rule.substring(start), getter));
    return buf.toString();
  }

  static String _appendGetter(String seg, String getter) {
    // 空段不补（畸形尾部连接符的容错，避免生成无意义规则）
    if (seg.isEmpty) return seg;
    // 段末尾已带 getter → 不重复补
    if (_getterSuffix.hasMatch(seg)) return seg;
    return seg + getter;
  }

  /// 上游 `fixImgInfo`：把 `img.xxx@text` / `img[@x]/text()` 改成取 alt。
  /// 上游用变长后顾限定 `img` 前必须是行首 / `tag.` / 选择器分隔符；
  /// Dart RegExp 对变长后顾支持有限，改为在回调里检查匹配起点前缀。
  static String _fixImgText(String rule, {required bool xpath}) {
    if (!rule.contains('img')) return rule;
    return rule.replaceAllMapped(_imgText, (m) {
      final start = m.start;
      if (start > 0) {
        final before = rule[start - 1];
        final isSep = '+/@>~| &'.contains(before);
        final isTagPrefix = start >= 4 && rule.substring(start - 4, start) == 'tag.';
        if (!isSep && !isTagPrefix) return m.group(0)!;
      }
      final at = m.group(1) ?? '';
      return xpath ? 'img$at/@alt' : 'img$at@alt';
    });
  }
}
