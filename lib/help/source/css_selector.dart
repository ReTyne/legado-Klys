import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// CSS 选择器工具，封装 html 包并补齐 Legado 书源常用的取值后缀
/// 规则形如：div.book@text、a@href、img@src、xxx@html
class CssSelector {
  /// 解析 HTML 字符串为文档
  static dom.Document parse(String html) => html_parser.parse(html);

  /// 在节点（Document 或 Element）下选择多个元素
  static List<dom.Element> selectAll(dom.Node? scope, String selector) {
    if (scope == null) return [];
    try {
      if (scope is dom.Document) return scope.querySelectorAll(selector);
      if (scope is dom.Element) return scope.querySelectorAll(selector);
      return [];
    } catch (_) {
      return [];
    }
  }

  /// 在节点（Document 或 Element）下选择单个元素
  static dom.Element? selectOne(dom.Node? scope, String selector) {
    if (scope == null) return null;
    try {
      if (scope is dom.Document) return scope.querySelector(selector);
      if (scope is dom.Element) return scope.querySelector(selector);
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 从规则中分离选择器与取值方式（@text/@href/@src/@html/@textNodes）
  /// 返回 (cssSelector, attr)
  static (String, String) splitRule(String rule) {
    final atIdx = rule.lastIndexOf('@');
    if (atIdx < 0) return (rule, 'text');
    return (rule.substring(0, atIdx), rule.substring(atIdx + 1));
  }

  /// 从单个元素按取值方式取字符串
  static String extract(dom.Element el, String attr) {
    switch (attr) {
      case 'text':
      case 'textContent':
        return el.text.trim();
      case 'ownText':
        return el.nodes
            .where((n) => n.nodeType == dom.Node.TEXT_NODE)
            .map((n) => n.text?.trim() ?? '')
            .where((s) => s.isNotEmpty)
            .join(' ');
      case 'html':
      case 'innerHTML':
        return el.innerHtml;
      case 'outerHtml':
        return el.outerHtml;
      default:
        if (attr.startsWith('attr:')) {
          return el.attributes[attr.substring(5)] ?? '';
        }
        // 直接当作属性名
        return el.attributes[attr] ?? el.text.trim();
    }
  }

  /// 从 HTML 字符串按规则提取字符串列表
  static List<String> selectTextList(String html, String rule) {
    final doc = parse(html);
    final (selector, attr) = splitRule(rule);
    return selectAll(doc, selector)
        .map((e) => extract(e, attr).trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// 从 HTML 字符串按规则提取首个字符串
  static String? selectText(String html, String rule) {
    final list = selectTextList(html, rule);
    return list.isEmpty ? null : list.first;
  }
}
