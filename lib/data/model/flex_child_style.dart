import 'dart:convert';

/// 发现页分类控件的 flex 布局样式。
///
/// 六个字段对应 JSON 键 `layout_flexGrow` / `layout_flexShrink` /
/// `layout_alignSelf` / `layout_flexBasisPercent` / `layout_wrapBefore` /
/// `layout_justifySelf`。
class FlexChildStyle {
  final double layoutFlexGrow;
  final double layoutFlexShrink;
  final String? layoutAlignSelf;
  final double layoutFlexBasisPercent;
  final bool layoutWrapBefore;
  final String? layoutJustifySelf;

  const FlexChildStyle({
    this.layoutFlexGrow = 0,
    this.layoutFlexShrink = 1,
    this.layoutAlignSelf,
    this.layoutFlexBasisPercent = -1,
    this.layoutWrapBefore = false,
    this.layoutJustifySelf,
  });

  /// 默认样式（未配置时使用）。
  static const FlexChildStyle defaultStyle = FlexChildStyle();

  factory FlexChildStyle.fromJson(dynamic source) {
    final Map<String, dynamic> m = _asMap(source);
    return FlexChildStyle(
      layoutFlexGrow: _asDouble(m['layout_flexGrow'], 0),
      layoutFlexShrink: _asDouble(m['layout_flexShrink'], 1),
      layoutAlignSelf: m['layout_alignSelf']?.toString(),
      layoutFlexBasisPercent: _asDouble(m['layout_flexBasisPercent'], -1),
      layoutWrapBefore: _asBool(m['layout_wrapBefore']),
      layoutJustifySelf: m['layout_justifySelf']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'layout_flexGrow': layoutFlexGrow,
        'layout_flexShrink': layoutFlexShrink,
        if (layoutAlignSelf != null) 'layout_alignSelf': layoutAlignSelf,
        'layout_flexBasisPercent': layoutFlexBasisPercent,
        'layout_wrapBefore': layoutWrapBefore,
        if (layoutJustifySelf != null) 'layout_justifySelf': layoutJustifySelf,
      };

  /// alignSelf 值规范化：把大小写 / 连字符 / 简写变体映射到统一的取值。
  static const Map<String, String> _alignValues = <String, String>{
    'auto': 'auto',
    'flex_start': 'flex_start',
    'flex-start': 'flex_start',
    'flexstart': 'flex_start',
    'start': 'flex_start',
    'flex_end': 'flex_end',
    'flex-end': 'flex_end',
    'flexend': 'flex_end',
    'end': 'flex_end',
    'center': 'center',
    'centre': 'center',
    'baseline': 'baseline',
    'stretch': 'stretch',
  };

  /// 返回规范化后的 alignSelf 值；未配置或未识别一律返回 `auto`。
  String alignSelf() {
    final key = (layoutAlignSelf ?? '').toLowerCase().trim();
    return _alignValues[key] ?? 'auto';
  }

  static Map<String, dynamic> _asMap(dynamic source) {
    if (source is Map) return Map<String, dynamic>.from(source);
    if (source is String) {
      try {
        final decoded = jsonDecode(source);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return <String, dynamic>{};
  }

  static double _asDouble(dynamic value, double fallback) =>
      double.tryParse(value?.toString() ?? '') ?? fallback;

  static bool _asBool(dynamic value) =>
      value == true || value == 1 || value == '1' || value == 'true';
}
