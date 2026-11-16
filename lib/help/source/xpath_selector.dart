import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// 轻量 XPath 子集解析器，覆盖书源规则常见写法。
///
/// 支持：
///  * `//tag`、`//tag[@class='x']/a`、属性谓词
///  * `..` 父轴、`following-sibling::` / `preceding-sibling::` 兄弟轴
///  * `//tag[1]`、`last()`、`position()` 位置谓词
///  * `text()` / `@href` 取值，`string(.)`、`normalize-space()`、`count()`
///  * `contains(text(),'x')`、`starts-with(@attr,'x')`、`not(...)`
///  * 谓词 `and` / `or`
///  * `exprA | exprB` 联合（去重）
///  * `.//tag` 相对当前节点
class XpathSelector {
  /// 从 HTML 字符串按 xpath 提取字符串列表。
  static List<String> selectText(String html, String xpath) {
    final doc = html_parser.parse(html);
    return selectTextFromNode(doc, xpath);
  }

  /// 从已解析节点按 xpath 提取字符串列表。
  static List<String> selectTextFromNode(dom.Node root, String xpath) {
    final nodes = selectNodes(root, xpath);
    return nodes.map(_nodeToString).where((s) => s.isNotEmpty).toList();
  }

  /// 选取节点（元素）；若结尾是取值函数则返回对应文本节点。
  static List<dom.Node> selectNodes(dom.Node root, String xpath) {
    var expr = xpath.trim();

    // 顶层 | 联合：各分支求值后按文档序去重合并
    final unions = _splitUnion(expr);
    if (unions.length > 1) {
      final seen = Set<dom.Node>.identity();
      final out = <dom.Node>[];
      for (final u in unions) {
        for (final n in selectNodes(root, u)) {
          if (seen.add(n)) out.add(n);
        }
      }
      return out;
    }

    if (expr.startsWith('.')) expr = expr.substring(1);
    if (expr.startsWith('//')) {
      return _evalSteps(root, expr.substring(2), recursiveFirst: true);
    } else if (expr.startsWith('/')) {
      return _evalSteps(root, expr.substring(1), recursiveFirst: false);
    }
    return _evalSteps(root, expr, recursiveFirst: false);
  }

  static List<dom.Node> _evalSteps(
    dom.Node root,
    String steps, {
    required bool recursiveFirst,
  }) {
    final parts = _splitSteps(steps);
    List<dom.Node> current = <dom.Node>[root];
    var recursive = recursiveFirst;

    for (var i = 0; i < parts.length; i++) {
      final part = parts[i].trim();
      if (part.isEmpty) {
        recursive = true;
        continue;
      }

      // 父轴 ..
      if (part == '..') {
        final next = <dom.Node>[];
        for (final n in current) {
          final p = n.parent;
          if (p != null) next.add(p);
        }
        current = next;
        recursive = false;
        continue;
      }

      // 结尾取值函数 / text() / @attr
      final valueStep = _parseValueStep(part);
      if (valueStep != null) {
        return _applyValueStep(root, current, valueStep);
      }

      final parsed = _parseStep(part);
      final next = <dom.Node>[];
      for (final node in current) {
        final candidates = _axisCandidates(node, parsed.axis, recursive);
        var matched = <dom.Element>[];
        for (final el in candidates) {
          if (parsed.tag.isNotEmpty && el.localName != parsed.tag) continue;
          matched.add(el);
        }
        // 谓词逐层过滤，每层重新计算 position/last
        for (final pred in parsed.preds) {
          final total = matched.length;
          var pos = 0;
          matched = matched.where((el) {
            pos++;
            return _evalPredicate(root, el, pred, pos, total);
          }).toList();
        }
        next.addAll(matched);
      }
      current = next;
      recursive = false;
    }
    return current;
  }

  /// 按 / 切分步骤（忽略谓词 [] 与函数 () 内部）。
  static List<String> _splitSteps(String steps) {
    final result = <String>[];
    final buffer = StringBuffer();
    var depth = 0;
    for (var i = 0; i < steps.length; i++) {
      final ch = steps[i];
      if (ch == '[' || ch == '(') depth++;
      if (ch == ']' || ch == ')') depth--;
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

  static List<String> _splitUnion(String s) {
    final out = <String>[];
    final buffer = StringBuffer();
    var depth = 0;
    var quote = '';
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (quote.isNotEmpty) {
        buffer.write(c);
        if (c == quote) quote = '';
        continue;
      }
      if (c == "'" || c == '"') {
        quote = c;
        buffer.write(c);
        continue;
      }
      if (c == '[' || c == '(') depth++;
      if (c == ']' || c == ')') depth--;
      if (depth == 0 && c == '|') {
        // 跳过 ||（非单一联合符）
        if ((i > 0 && s[i - 1] == '|') ||
            (i + 1 < s.length && s[i + 1] == '|')) {
          buffer.write(c);
          continue;
        }
        out.add(buffer.toString());
        buffer.clear();
        continue;
      }
      buffer.write(c);
    }
    out.add(buffer.toString());
    return out.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  // ============================== step 解析 ==============================

  static _Step _parseStep(String raw) {
    var s = raw.trim();
    var axis = '';
    final axisIdx = s.indexOf('::');
    if (axisIdx >= 0) {
      axis = s.substring(0, axisIdx).trim().toLowerCase();
      s = s.substring(axisIdx + 2).trim();
    }
    final extracted = _extractPredicates(s);
    var tag = extracted.$1.trim();
    if (tag == '*') tag = '';
    return _Step(tag, axis, extracted.$2);
  }

  /// 拆分 `nodetest[..][..]` 为 (nodetest, 谓词列表)。
  static (String, List<String>) _extractPredicates(String s) {
    final preds = <String>[];
    final head = StringBuffer();
    final pred = StringBuffer();
    var inPred = false;
    var depth = 0;
    var quote = '';
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (!inPred) {
        if (c == '[') {
          inPred = true;
          depth = 1;
          pred.clear();
          continue;
        }
        head.write(c);
        continue;
      }
      if (quote.isNotEmpty) {
        pred.write(c);
        if (c == quote) quote = '';
        continue;
      }
      if (c == "'" || c == '"') {
        quote = c;
        pred.write(c);
        continue;
      }
      if (c == '[' || c == '(') {
        depth++;
        pred.write(c);
        continue;
      }
      if (c == ']' || c == ')') {
        depth--;
        if (depth == 0 && c == ']') {
          preds.add(pred.toString());
          pred.clear();
          inPred = false;
          continue;
        }
        pred.write(c);
        continue;
      }
      pred.write(c);
    }
    return (head.toString(), preds);
  }

  static List<dom.Element> _axisCandidates(
      dom.Node node, String axis, bool recursive) {
    switch (axis) {
      case 'following-sibling':
      case 'preceding-sibling':
        final out = <dom.Element>[];
        final parent = node.parent;
        if (parent == null) return out;
        final sibs = parent.nodes.whereType<dom.Element>().toList();
        var selfIdx = -1;
        for (var k = 0; k < sibs.length; k++) {
          if (identical(sibs[k], node)) {
            selfIdx = k;
            break;
          }
        }
        if (selfIdx < 0) return out;
        if (axis == 'following-sibling') {
          for (var k = selfIdx + 1; k < sibs.length; k++) {
            out.add(sibs[k]);
          }
        } else {
          for (var k = 0; k < selfIdx; k++) {
            out.add(sibs[k]);
          }
        }
        return out;
      case 'parent':
        final p = node.parent;
        return p is dom.Element ? <dom.Element>[p] : <dom.Element>[];
      case 'self':
        return node is dom.Element ? <dom.Element>[node] : <dom.Element>[];
      case 'descendant':
        return _allElements(node);
      case 'child':
        return _directChildren(node);
      default:
        return recursive ? _allElements(node) : _directChildren(node);
    }
  }

  // ============================== 取值函数 ==============================

  static _ValueStep? _parseValueStep(String part) {
    final s = part.trim();
    if (s == 'text()') return _ValueStep(_ValueKind.text, '');
    if (s.startsWith('@') && !s.contains('[')) {
      return _ValueStep(_ValueKind.attr, s.substring(1));
    }
    final m = RegExp(r'^(string|normalize-space|count)\((.*)\)$', dotAll: true)
        .firstMatch(s);
    if (m != null) {
      final kind = <String, _ValueKind>{
        'string': _ValueKind.string,
        'normalize-space': _ValueKind.normalizeSpace,
        'count': _ValueKind.count,
      }[m.group(1)]!;
      return _ValueStep(kind, m.group(2)!.trim());
    }
    return null;
  }

  static List<dom.Node> _applyValueStep(
      dom.Node root, List<dom.Node> current, _ValueStep vs) {
    switch (vs.kind) {
      case _ValueKind.text:
        return current
            .expand(
                (n) => n.nodes.where((c) => c.nodeType == dom.Node.TEXT_NODE))
            .toList();
      case _ValueKind.attr:
        return current
            .whereType<dom.Element>()
            .map((e) => dom.Text(e.attributes[vs.arg] ?? ''))
            .toList();
      case _ValueKind.string:
      case _ValueKind.normalizeSpace:
        Iterable<dom.Node> source = current;
        if (_isPathArg(vs.arg)) source = selectNodes(root, vs.arg);
        return source.map((n) {
          final t = _nodeToString(n);
          return dom.Text(
              vs.kind == _ValueKind.normalizeSpace ? _normalizeSpace(t) : t);
        }).toList();
      case _ValueKind.count:
        final count = _isPathArg(vs.arg)
            ? selectNodes(root, vs.arg).length
            : current.length;
        return <dom.Node>[dom.Text(count.toString())];
    }
  }

  static bool _isPathArg(String arg) =>
      arg.isNotEmpty &&
      arg != '.' &&
      (arg.startsWith('/') || arg.startsWith('.') || arg.contains('::'));

  static String _normalizeSpace(String s) =>
      s.trim().replaceAll(RegExp(r'\s+'), ' ');

  // ============================== 谓词求值 ==============================

  static bool _evalPredicate(
      dom.Node root, dom.Element el, String pred, int pos, int total) {
    final orParts = _splitLogic(pred, 'or');
    if (orParts.length > 1) {
      return orParts.any((p) => _evalPredicate(root, el, p, pos, total));
    }
    final andParts = _splitLogic(pred, 'and');
    if (andParts.length > 1) {
      return andParts.every((p) => _evalPredicate(root, el, p, pos, total));
    }
    return _evalAtom(root, el, pred.trim(), pos, total);
  }

  static List<String> _splitLogic(String s, String op) {
    final out = <String>[];
    final buffer = StringBuffer();
    var depth = 0;
    var quote = '';
    var i = 0;
    while (i < s.length) {
      final c = s[i];
      if (quote.isNotEmpty) {
        buffer.write(c);
        if (c == quote) quote = '';
        i++;
        continue;
      }
      if (c == "'" || c == '"') {
        quote = c;
        buffer.write(c);
        i++;
        continue;
      }
      if (c == '[' || c == '(') depth++;
      if (c == ']' || c == ')') depth--;
      if (depth == 0 &&
          i + op.length <= s.length &&
          s.substring(i, i + op.length) == op) {
        final beforeOk = i == 0 || !_isWord(s[i - 1]);
        final afterOk = i + op.length >= s.length || !_isWord(s[i + op.length]);
        if (beforeOk && afterOk) {
          out.add(buffer.toString());
          buffer.clear();
          i += op.length;
          continue;
        }
      }
      buffer.write(c);
      i++;
    }
    out.add(buffer.toString());
    return out;
  }

  static bool _isWord(String c) => RegExp(r'[\w.\-]').hasMatch(c);

  static bool _evalAtom(
      dom.Node root, dom.Element el, String atom, int pos, int total) {
    final s = atom.trim();
    if (s.startsWith('not(') && s.endsWith(')')) {
      return !_evalPredicate(
          root, el, s.substring(4, s.length - 1), pos, total);
    }
    final n = int.tryParse(s);
    if (n != null) return pos == n;
    if (s == 'last()') return pos == total;
    if (s == 'position()') return true;

    final pm =
        RegExp(r'^position\(\)\s*(==|=|!=|<|>|<=|>=)\s*(\d+)$').firstMatch(s);
    if (pm != null) {
      return _compareNum(pos, pm.group(1)!, int.parse(pm.group(2)!));
    }

    final fn = RegExp(r'^(contains|starts-with)\(\s*([^,]+?)\s*,\s*(.*?)\s*\)$')
        .firstMatch(s);
    if (fn != null) {
      final left = _atomValue(el, fn.group(2)!.trim());
      final right = _unquote(fn.group(3)!.trim());
      return fn.group(1) == 'contains'
          ? left.contains(right)
          : left.startsWith(right);
    }

    final cmp = RegExp(r'^(text\(\)|@?[\w-]+)\s*(==|=|!=|<|>|<=|>=)\s*(.*)$')
        .firstMatch(s);
    if (cmp != null) {
      final left = _atomValue(el, cmp.group(1)!);
      final right = _unquote(cmp.group(3)!.trim());
      return _compareStr(left, cmp.group(2)!, right);
    }

    // 存在性谓词：@attr / text()
    if (s.startsWith('@')) return el.attributes.containsKey(s.substring(1));
    if (s == 'text()') return el.text.isNotEmpty;
    return false;
  }

  static String _atomValue(dom.Element el, String expr) {
    if (expr == 'text()' || expr == '.' || expr == 'string(.)') return el.text;
    if (expr.startsWith('@')) {
      return el.attributes[expr.substring(1)] ?? '';
    }
    return el.attributes[expr] ?? el.text;
  }

  static bool _compareNum(int a, String op, int b) {
    switch (op) {
      case '=':
      case '==':
        return a == b;
      case '!=':
        return a != b;
      case '<':
        return a < b;
      case '>':
        return a > b;
      case '<=':
        return a <= b;
      case '>=':
        return a >= b;
    }
    return false;
  }

  static bool _compareStr(String a, String op, String b) {
    final an = num.tryParse(a);
    final bn = num.tryParse(b);
    final int cmp;
    if (an != null && bn != null) {
      cmp = an.compareTo(bn);
    } else {
      cmp = a.compareTo(b);
    }
    switch (op) {
      case '=':
      case '==':
        return (an != null && bn != null) ? cmp == 0 : a == b;
      case '!=':
        return (an != null && bn != null) ? cmp != 0 : a != b;
      case '<':
        return cmp < 0;
      case '>':
        return cmp > 0;
      case '<=':
        return cmp <= 0;
      case '>=':
        return cmp >= 0;
    }
    return false;
  }

  static String _unquote(String s) {
    if (s.length >= 2 &&
        ((s.startsWith('"') && s.endsWith('"')) ||
            (s.startsWith("'") && s.endsWith("'")))) {
      return s.substring(1, s.length - 1);
    }
    return s;
  }

  // ============================== 节点工具 ==============================

  static List<dom.Element> _allElements(dom.Node node) {
    if (node is dom.Document) return node.querySelectorAll('*');
    if (node is dom.Element) return node.querySelectorAll('*');
    return <dom.Element>[];
  }

  static List<dom.Element> _directChildren(dom.Node node) =>
      node.nodes.whereType<dom.Element>().toList();

  static String _nodeToString(dom.Node node) {
    if (node is dom.Text) return node.text.trim();
    if (node is dom.Element) return node.text.trim();
    return node.text?.trim() ?? '';
  }
}

class _Step {
  final String tag;
  final String axis;
  final List<String> preds;
  _Step(this.tag, this.axis, this.preds);
}

enum _ValueKind { text, attr, string, normalizeSpace, count }

class _ValueStep {
  final _ValueKind kind;
  final String arg;
  _ValueStep(this.kind, this.arg);
}
