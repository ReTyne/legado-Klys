/// 轻量 JSONPath 解析器，覆盖书源规则常用语法。
///
/// 支持：
///  * `$.a.b.c`        点路径
///  * `$.a[0].b`       数组索引（含负索引）
///  * `$.a[*].b`       数组通配
///  * `$.*`            对象/数组通配
///  * `$..key`         递归下降并保持后续路径
///  * `$.a[1:3]`       数组切片（支持省略端点与步长）
///  * `$['a','b']`     键/索引联合
///  * `[?(@.f==v)]`    简单过滤器（== != < > <= >=）
///  * `$.a.length()`   长度
///  * `a||b`           多路径或取值
///  * `$.a@text`       兼容写法（忽略 @ 后处理标记）
class JsonPath {
  /// 按 JSONPath 取值，返回命中的所有节点。
  static List<dynamic> select(dynamic root, String path) {
    if (path.trim().isEmpty) {
      return root == null ? <dynamic>[] : <dynamic>[root];
    }

    // 多路径 ||：取第一个有命中的分支
    if (path.contains('||')) {
      for (final p in _splitTopLevel(path, '||')) {
        final r = select(root, p.trim());
        if (r.isNotEmpty) return r;
      }
      return <dynamic>[];
    }

    var expr = path.trim();
    // 剥离结尾的取值后缀（不触碰路径中间的 @ 与过滤器内的 @）
    expr = expr.replaceAll(
        RegExp(
            r'@(?:textNodes|textContent|outerHtml|innerHtml|ownText|text|html|all|href|src)\s*$'),
        '');
    if (expr.startsWith(r'$')) expr = expr.substring(1);
    if (expr.isEmpty) return root == null ? <dynamic>[] : <dynamic>[root];

    final segments = _tokenize(expr);
    var results = <dynamic>[root];
    for (final seg in segments) {
      final next = <dynamic>[];
      for (final node in results) {
        next.addAll(_applySegment(node, seg));
      }
      results = next;
      if (results.isEmpty) break;
    }
    return results;
  }

  /// 取第一个命中值。
  static dynamic selectFirst(dynamic root, String path) {
    final r = select(root, path);
    return r.isEmpty ? null : r.first;
  }

  /// 取第一个命中值并转字符串。
  static String? selectString(dynamic root, String path) =>
      selectFirst(root, path)?.toString();

  /// 内联 JSONPath 展开：把规则串里的 `{$.a.b}` 先按 [evalPath] 求值再拼回。
  ///
  /// [evalPath] 接收完整路径（如 `$.a.b`），返回其字符串值。
  static String expandInnerRules(
      String rule, String Function(String) evalPath) {
    return rule.replaceAllMapped(RegExp(r'\{\$([^{}]*)\}'), (m) {
      return evalPath('\$${m.group(1)}');
    });
  }

  // ============================== 表达式切分 ==============================

  static List<_Seg> _tokenize(String expr) {
    final segs = <_Seg>[];
    final buf = StringBuffer();

    void flush() {
      if (buf.isEmpty) return;
      final k = buf.toString();
      buf.clear();
      if (k == '*') {
        segs.add(_Seg(_SegType.wildcard));
      } else if (k == 'length()' || k == 'length') {
        segs.add(_Seg(_SegType.length));
      } else {
        segs.add(_Seg(_SegType.key, value: k));
      }
    }

    var i = 0;
    while (i < expr.length) {
      final c = expr[i];
      if (c == '.') {
        flush();
        if (i + 1 < expr.length && expr[i + 1] == '.') {
          segs.add(_Seg(_SegType.recursive));
          i += 2;
          continue;
        }
        i += 1;
        continue;
      }
      if (c == '[') {
        flush();
        final end = _matchBracket(expr, i);
        if (end < 0) {
          buf.write(expr.substring(i));
          break;
        }
        segs.add(_parseBracket(expr.substring(i + 1, end)));
        i = end + 1;
        continue;
      }
      buf.write(c);
      i += 1;
    }
    flush();
    return segs;
  }

  /// 从 [open]（指向 `[`）起找配对的 `]`，跳过引号与嵌套的 `[`/`(`，
  /// 找不到返回 -1。
  static int _matchBracket(String s, int open) {
    var depth = 0;
    var quote = '';
    for (var i = open; i < s.length; i++) {
      final c = s[i];
      if (quote.isNotEmpty) {
        if (c == quote) quote = '';
        continue;
      }
      if (c == "'" || c == '"') {
        quote = c;
        continue;
      }
      if (c == '[' || c == '(') {
        depth++;
      } else if (c == ']' || c == ')') {
        depth--;
        if (depth == 0 && c == ']') return i;
      }
    }
    return -1;
  }

  static _Seg _parseBracket(String inner) {
    final t = inner.trim();
    if (t == '*') return _Seg(_SegType.wildcard);
    if (t.startsWith('?')) {
      return _Seg(_SegType.filter, filter: _parseFilter(t));
    }
    if (t.contains(',')) {
      final keys = <String>[];
      for (final part in _splitTopLevel(t, ',')) {
        final p = _unquote(part.trim());
        if (p.isNotEmpty) keys.add(p);
      }
      return _Seg(_SegType.union, keys: keys);
    }
    if (t.contains(':') && !t.contains("'") && !t.contains('"')) {
      final seg = t.split(':');
      int? num(String s) => s.trim().isEmpty ? null : int.tryParse(s.trim());
      return _Seg(
        _SegType.slice,
        start: num(seg[0]),
        end: seg.length > 1 ? num(seg[1]) : null,
        step: seg.length > 2 ? num(seg[2]) : null,
      );
    }
    final idx = int.tryParse(_unquote(t));
    if (idx != null) return _Seg(_SegType.idx, value: idx.toString());
    return _Seg(_SegType.key, value: _unquote(t));
  }

  static _Filter? _parseFilter(String t) {
    var s = t.trim();
    if (s.startsWith('?')) s = s.substring(1).trim();
    if (s.startsWith('(') && s.endsWith(')')) {
      s = s.substring(1, s.length - 1).trim();
    }
    final m =
        RegExp(r'^@?\.?([\w.]+)\s*(==|!=|<=|>=|<|>)\s*(.*)$').firstMatch(s);
    if (m == null) return null;
    return _Filter(m.group(1)!, m.group(2)!, _unquote(m.group(3)!.trim()));
  }

  /// 按顶层分隔符切分（忽略引号与 `[]()` 内部）。
  static List<String> _splitTopLevel(String s, String sep) {
    final out = <String>[];
    final buf = StringBuffer();
    var quote = '';
    var depth = 0;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (quote.isNotEmpty) {
        buf.write(c);
        if (c == quote) quote = '';
        continue;
      }
      if (c == "'" || c == '"') {
        quote = c;
        buf.write(c);
        continue;
      }
      if (c == '[' || c == '(') {
        depth++;
      } else if (c == ']' || c == ')') {
        depth--;
      }
      if (depth == 0) {
        if (sep.length == 1 && c == sep) {
          out.add(buf.toString());
          buf.clear();
          continue;
        }
        if (sep.length > 1 &&
            i + sep.length <= s.length &&
            s.substring(i, i + sep.length) == sep) {
          out.add(buf.toString());
          buf.clear();
          i += sep.length - 1;
          continue;
        }
      }
      buf.write(c);
    }
    out.add(buf.toString());
    return out;
  }

  // ============================== 段应用 ==============================

  static List<dynamic> _applySegment(dynamic node, _Seg seg) {
    switch (seg.type) {
      case _SegType.key:
        if (node is Map && node.containsKey(seg.value)) {
          return <dynamic>[node[seg.value]];
        }
        return <dynamic>[];
      case _SegType.idx:
        if (node is List) {
          final i = int.parse(seg.value);
          final idx = i < 0 ? node.length + i : i;
          if (idx >= 0 && idx < node.length) return <dynamic>[node[idx]];
        }
        return <dynamic>[];
      case _SegType.wildcard:
        if (node is List) return List<dynamic>.from(node);
        if (node is Map) return node.values.toList();
        return <dynamic>[];
      case _SegType.recursive:
        final out = <dynamic>[];
        _collectNodes(node, out);
        return out;
      case _SegType.length:
        if (node is List || node is Map || node is String) {
          return <dynamic>[node.length];
        }
        return <dynamic>[0];
      case _SegType.slice:
        if (node is List) {
          return _sliceIndices(node.length, seg.start, seg.end, seg.step)
              .map((i) => node[i])
              .toList();
        }
        return <dynamic>[];
      case _SegType.union:
        final out = <dynamic>[];
        for (final k in seg.keys) {
          final asInt = int.tryParse(k);
          if (node is List && asInt != null) {
            final idx = asInt < 0 ? node.length + asInt : asInt;
            if (idx >= 0 && idx < node.length) out.add(node[idx]);
          } else if (node is Map && node.containsKey(k)) {
            out.add(node[k]);
          }
        }
        return out;
      case _SegType.filter:
        if (seg.filter == null) return <dynamic>[];
        final source = node is List
            ? node
            : (node is Map ? node.values.toList() : <dynamic>[]);
        return source.where((e) => _testFilter(e, seg.filter!)).toList();
    }
  }

  static List<int> _sliceIndices(int total, int? start, int? end, int? step) {
    var st = step ?? 1;
    if (st == 0) st = 1;
    if (st > 0) {
      var s = start ?? 0;
      var e = end ?? total;
      if (s < 0) s += total;
      if (e < 0 && end != null) e += total;
      if (s < 0) s = 0;
      if (e > total) e = total;
      final out = <int>[];
      for (var i = s; i < e && i < total; i += st) {
        out.add(i);
      }
      return out;
    }
    var s = start ?? total - 1;
    var e = end ?? -1;
    if (s < 0) s += total;
    if (e < 0 && end != null) e += total;
    if (s >= total) s = total - 1;
    final out = <int>[];
    for (var i = s; i > e && i >= 0; i += st) {
      out.add(i);
    }
    return out;
  }

  static bool _testFilter(dynamic element, _Filter f) {
    dynamic actual = element is Map ? _pathValue(element, f.field) : element;
    if (actual == null) return false;
    final a = actual.toString();
    final b = f.value;
    final an = num.tryParse(a);
    final bn = num.tryParse(b);
    final cmp = (an != null && bn != null) ? an.compareTo(bn) : a.compareTo(b);
    switch (f.op) {
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

  static dynamic _pathValue(Map node, String field) {
    dynamic cur = node;
    for (final k in field.split('.')) {
      if (k.isEmpty) continue;
      if (cur is Map && cur.containsKey(k)) {
        cur = cur[k];
      } else {
        return null;
      }
    }
    return cur;
  }

  static void _collectNodes(dynamic node, List<dynamic> out) {
    out.add(node);
    if (node is Map) {
      for (final v in node.values) {
        _collectNodes(v, out);
      }
    } else if (node is List) {
      for (final v in node) {
        _collectNodes(v, out);
      }
    }
  }

  static String _unquote(String s) {
    if (s.length >= 2 &&
        ((s.startsWith('"') && s.endsWith('"')) ||
            (s.startsWith("'") && s.endsWith("'")))) {
      return s.substring(1, s.length - 1);
    }
    return s;
  }
}

enum _SegType {
  key,
  idx,
  wildcard,
  recursive,
  slice,
  union,
  filter,
  length,
}

class _Seg {
  final _SegType type;
  final String value;
  final int? start;
  final int? end;
  final int? step;
  final List<String> keys;
  final _Filter? filter;

  _Seg(
    this.type, {
    this.value = '',
    this.start,
    this.end,
    this.step,
    this.keys = const <String>[],
    this.filter,
  });
}

class _Filter {
  final String field;
  final String op;
  final String value;
  _Filter(this.field, this.op, this.value);
}
