import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// 轻量 XPath 子集解析器，覆盖 Legado 书源常见写法
/// 支持：
///   //tag                       全局选取标签
///   //tag[@class='x']           属性谓词（=、contains）
///   //tag[@id='x']/a            层级
///   //tag[1]                    索引（从1开始，last()）
///   //tag/text()                取文本
///   //tag/@href                 取属性
///   .//tag                      相对当前节点
class XpathSelector {
  /// 从 HTML 字符串按 xpath 提取字符串列表
  static List<String> selectText(String html, String xpath) {
    final doc = html_parser.parse(html);
    return selectTextFromNode(doc, xpath);
  }

  /// 从已解析节点按 xpath 提取字符串列表
  static List<String> selectTextFromNode(dom.Node root, String xpath) {
    final nodes = selectNodes(root, xpath);
    return nodes.map(_nodeToString).where((s) => s.isNotEmpty).toList();
  }

  /// 选取节点（元素）；若结尾是 text()/@attr 则返回对应字符串节点
  static List<dom.Node> selectNodes(dom.Node root, String xpath) {
    var expr = xpath.trim();
    if (expr.startsWith('.')) expr = expr.substring(1);
    if (expr.startsWith('//')) {
      // 递归起点
      return _evalSteps(root, expr.substring(2), recursiveFirst: true);
    } else if (expr.startsWith('/')) {
      return _evalSteps(root, expr.substring(1), recursiveFirst: false);
    }
    return _evalSteps(root, expr, recursiveFirst: false);
  }

  static List<dom.Node> _evalSteps(dom.Node root, String steps, {required bool recursiveFirst}) {
    final parts = _splitSteps(steps);
    List<dom.Node> current = [root];
    var recursive = recursiveFirst;

    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      if (part.isEmpty) {
        recursive = true;
        continue;
      }
      // 结尾取值
      if (part == 'text()') {
        return current.expand((n) => n.nodes.where((c) => c.nodeType == dom.Node.TEXT_NODE)).toList();
      }
      if (part.startsWith('@')) {
        final attr = part.substring(1);
        return current
            .whereType<dom.Element>()
            .map((e) => dom.Text(e.attributes[attr] ?? ''))
            .toList();
      }

      final parsed = _parseStep(part);
      final next = <dom.Node>[];
      for (final node in current) {
        final candidates = recursive ? _allElements(node) : _directChildren(node);
        for (final el in candidates) {
          if (_matches(el, parsed)) next.add(el);
        }
      }
      // 索引
      if (parsed.index != null && next.isNotEmpty) {
        var idx = parsed.index!;
        if (idx == -1) {
          final last = next.last;
          current = [last];
        } else if (idx >= 1 && idx <= next.length) {
          current = [next[idx - 1]];
        } else {
          current = [];
        }
      } else {
        current = next;
      }
      recursive = false;
    }
    return current;
  }

  static List<String> _splitSteps(String steps) {
    // 不拆谓词内部的 /
    final result = <String>[];
    final buffer = StringBuffer();
    var depth = 0;
    for (var i = 0; i < steps.length; i++) {
      final ch = steps[i];
      if (ch == '[') depth++;
      if (ch == ']') depth--;
      if (ch == '/' && depth == 0) {
        result.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(ch);
      }
    }
    if (buffer.isNotEmpty) result.add(buffer.toString());
    return result;
  }

  static _Step _parseStep(String raw) {
    var tag = raw;
    String? attrKey;
    String? attrVal;
    bool attrContains = false;
    int? index;

    final predMatch = RegExp(r'^([^\[]+)(?:\[(.*)\])?$').firstMatch(raw);
    if (predMatch != null) {
      tag = predMatch.group(1) ?? raw;
      final pred = predMatch.group(2);
      if (pred != null) {
        // 支持 @attr='x' / @attr="x" / contains(@attr,'x') / contains(@attr,"x")
        final attrM = RegExp(r'''@?([\w-]+)\s*(?:=|contains\()\s*['"]?([^'"\)]*)['"]?\)?''').firstMatch(pred);
        if (attrM != null && pred.contains('@')) {
          attrKey = attrM.group(1);
          attrVal = attrM.group(2);
          attrContains = pred.contains('contains');
        } else {
          if (pred.trim() == 'last()') {
            index = -1;
          } else {
            index = int.tryParse(pred.trim());
          }
        }
      }
    }
    if (tag == '*') tag = '';
    return _Step(tag, attrKey, attrVal, attrContains, index);
  }

  static bool _matches(dom.Element el, _Step step) {
    if (step.tag.isNotEmpty && el.localName != step.tag) return false;
    if (step.attrKey != null) {
      final actual = el.attributes[step.attrKey] ?? '';
      if (step.attrContains) {
        if (!actual.contains(step.attrVal ?? '')) return false;
      } else {
        if (actual != step.attrVal) return false;
      }
    }
    return true;
  }

  static List<dom.Element> _allElements(dom.Node node) {
    if (node is dom.Document) return node.querySelectorAll('*');
    if (node is dom.Element) return node.querySelectorAll('*');
    return [];
  }

  static List<dom.Element> _directChildren(dom.Node node) {
    return node.nodes.whereType<dom.Element>().toList();
  }

  static String _nodeToString(dom.Node node) {
    if (node is dom.Text) return node.text.trim();
    if (node is dom.Element) return node.text.trim();
    return node.text?.trim() ?? '';
  }
}

class _Step {
  final String tag;
  final String? attrKey;
  final String? attrVal;
  final bool attrContains;
  final int? index;
  _Step(this.tag, this.attrKey, this.attrVal, this.attrContains, this.index);
}
