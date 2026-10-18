import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 高亮标签规则：用户在「高亮标签规则」页维护的 名称|||正则|||颜色 列表，
/// 存于 SharedPreferences 的 `highlight_rules`。本服务读取规则，并把正文
/// 中命中的片段构建为带背景/前景高亮的 TextSpan。
class HighlightService {
  HighlightService._();

  static List<_HLRule>? _cache;

  static Future<void> reload() async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList('highlight_rules') ?? const <String>[];
    _cache = [];
    for (final raw in list) {
      final parts = raw.split('|||');
      if (parts.length < 2 || parts[1].isEmpty) continue;
      try {
        final colorValue = parts.length > 2 ? int.tryParse(parts[2]) : null;
        _cache!.add(_HLRule(
          RegExp(parts[1], multiLine: true, dotAll: false),
          colorValue != null ? Color(colorValue) : Colors.yellow,
        ));
      } catch (_) {}
    }
  }

  static bool get hasRules => _cache?.isNotEmpty ?? false;

  /// 把一页文本按高亮规则切成 TextSpan 列表；无规则/未加载时返回 null（调用方退回普通 Text）。
  /// 需先 await reload() 完成后再在 build 中同步调用。
  static List<InlineSpan>? spansFor(String text, TextStyle base) {
    final rules = _cache;
    if (rules == null || rules.isEmpty) return null;

    // 收集所有命中区间（start,end,color），按起点排序；重叠时先到先得
    final hits = <_Hit>[];
    for (final r in rules) {
      for (final m in r.pattern.allMatches(text)) {
        if (m.start < m.end) hits.add(_Hit(m.start, m.end, r.color));
      }
    }
    if (hits.isEmpty) return null;
    hits.sort((a, b) => a.start == b.start ? a.end.compareTo(b.end) : a.start.compareTo(b.start));

    final merged = <_Hit>[];
    int cursor = 0;
    for (final h in hits) {
      if (h.start < cursor) continue; // 与已取区间重叠，跳过
      merged.add(h);
      cursor = h.end;
    }
    merged.sort((a, b) => a.start.compareTo(b.start));

    final spans = <InlineSpan>[];
    int pos = 0;
    for (final h in merged) {
      if (h.start > pos) spans.add(TextSpan(text: text.substring(pos, h.start), style: base));
      spans.add(TextSpan(
        text: text.substring(h.start, h.end),
        style: base.copyWith(
          color: Colors.white,
          backgroundColor: h.color.withOpacity(0.55),
          fontWeight: FontWeight.w600,
        ),
      ));
      pos = h.end;
    }
    if (pos < text.length) spans.add(TextSpan(text: text.substring(pos), style: base));
    return spans;
  }
}

class _HLRule {
  final RegExp pattern;
  final Color color;
  _HLRule(this.pattern, this.color);
}

class _Hit {
  final int start, end;
  final Color color;
  _Hit(this.start, this.end, this.color);
}
