/// 轻量 JSONPath 解析器，对齐 Legado 书源常用语法
/// 支持：
///  $.a.b.c        点路径
///  $.a[0].b       数组索引
///  $.a[*].b       数组通配，返回列表
///  $..key         递归下降查找
///  a||b           多路径或取值
///  $.a@text       兼容写法（忽略@后处理标记）
class JsonPath {
  /// 按 JSONPath 取值，返回命中的所有节点
  static List<dynamic> select(dynamic root, String path) {
    if (path.trim().isEmpty) return root == null ? [] : [root];

    // 多路径 ||
    if (path.contains('||')) {
      for (final p in path.split('||')) {
        final r = select(root, p.trim());
        if (r.isNotEmpty) return r;
      }
      return [];
    }

    var expr = path.trim();
    // 去掉 @text/@html 等后处理标记
    final atIdx = expr.indexOf('@');
    if (atIdx >= 0 && !expr.contains('[')) expr = expr.substring(0, atIdx);

    if (expr.startsWith(r'$')) expr = expr.substring(1);
    if (expr.startsWith('.')) expr = expr.substring(1);
    if (expr.isEmpty) return root == null ? [] : [root];

    // 递归下降 $..key
    if (path.trim().startsWith(r'$..')) {
      final key = expr.split('.').first.split('[').first;
      final rest = expr.contains('.') ? expr.substring(key.length) : '';
      final found = <dynamic>[];
      _recursiveFind(root, key, found);
      if (rest.isEmpty) return found;
      final result = <dynamic>[];
      for (final node in found) {
        result.addAll(select(node, rest));
      }
      return result;
    }

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

  /// 取第一个命中值
  static dynamic selectFirst(dynamic root, String path) {
    final r = select(root, path);
    return r.isEmpty ? null : r.first;
  }

  /// 取第一个命中值并转字符串
  static String? selectString(dynamic root, String path) {
    final v = selectFirst(root, path);
    if (v == null) return null;
    return v.toString();
  }

  // 把 a.b[0].c[*] 切分为段
  static List<_Seg> _tokenize(String expr) {
    final segs = <_Seg>[];
    final re = RegExp("([^.\\[\\]]+)|\\[(\\*|\\d+|'[^']*'|\"[^\"]*\")\\]");
    for (final m in re.allMatches(expr)) {
      if (m.group(1) != null && m.group(1)!.isNotEmpty) {
        segs.add(_Seg(_SegType.key, m.group(1)!));
      } else if (m.group(2) != null) {
        final idx = m.group(2)!;
        if (idx == '*') {
          segs.add(_Seg(_SegType.wildcard, '*'));
        } else if (int.tryParse(idx) != null) {
          segs.add(_Seg(_SegType.idx, idx));
        } else {
          segs.add(_Seg(_SegType.key, idx.replaceAll(RegExp('[\'"]'), '')));
        }
      }
    }
    return segs;
  }

  static List<dynamic> _applySegment(dynamic node, _Seg seg) {
    switch (seg.type) {
      case _SegType.key:
        if (node is Map && node.containsKey(seg.value)) return [node[seg.value]];
        return [];
      case _SegType.idx:
        if (node is List) {
          final i = int.parse(seg.value);
          final idx = i < 0 ? node.length + i : i;
          if (idx >= 0 && idx < node.length) return [node[idx]];
        }
        return [];
      case _SegType.wildcard:
        if (node is List) return node;
        if (node is Map) return node.values.toList();
        return [];
    }
  }

  static void _recursiveFind(dynamic node, String key, List<dynamic> out) {
    if (node is Map) {
      if (node.containsKey(key)) out.add(node[key]);
      for (final v in node.values) {
        _recursiveFind(v, key, out);
      }
    } else if (node is List) {
      for (final v in node) {
        _recursiveFind(v, key, out);
      }
    }
  }
}

enum _SegType { key, idx, wildcard }

class _Seg {
  final _SegType type;
  final String value;
  _Seg(this.type, this.value);
}
