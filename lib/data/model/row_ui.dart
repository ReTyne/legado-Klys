import 'dart:convert';

import 'flex_child_style.dart';

/// 登录表单 / 发现页的一行控件描述。
///
/// 字段对应书源 JSON：name / type / action / chars / default / viewName / style。
/// type 同时接受 `toggle` 与 `switch` 两种开关写法；下拉选项同时接受
/// `chars` 与 `options` 两种键名。
class RowUi {
  final String name;
  final String type;
  final String? action;
  final List<String> chars;
  final String defaultValue;
  final String? viewName;
  final FlexChildStyle? style;

  const RowUi({
    this.name = '',
    this.type = typeText,
    this.action,
    this.chars = const <String>[],
    this.defaultValue = '',
    this.viewName,
    this.style,
  });

  static const String typeText = 'text';
  static const String typePassword = 'password';
  static const String typeButton = 'button';
  static const String typeToggle = 'toggle';
  static const String typeSelect = 'select';

  /// 归一化控件类型：缺省为 text，switch 归一为 toggle，其余转小写。
  static String normalizeType(String? raw) {
    final t = (raw ?? '').trim().toLowerCase();
    if (t == 'switch') return typeToggle;
    if (t.isEmpty) return typeText;
    return t;
  }

  factory RowUi.fromJson(dynamic source) {
    final Map<String, dynamic> m = _asMap(source);
    final opts = m['chars'] ?? m['options'];
    final List<String> chars = <String>[];
    if (opts is List) {
      for (final e in opts) {
        chars.add(e?.toString() ?? '');
      }
    } else if (opts is String && opts.isNotEmpty) {
      chars.addAll(opts
          .split(RegExp(r'[,，]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty));
    }
    return RowUi(
      name: m['name']?.toString() ?? '',
      type: normalizeType(m['type']?.toString()),
      action: m['action']?.toString(),
      chars: chars,
      defaultValue: m['default']?.toString() ?? '',
      viewName: m['viewName']?.toString(),
      style: m['style'] is Map ? FlexChildStyle.fromJson(m['style']) : null,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'type': type,
        if (action != null) 'action': action,
        if (chars.isNotEmpty) 'chars': chars,
        if (defaultValue.isNotEmpty) 'default': defaultValue,
        if (viewName != null) 'viewName': viewName,
        if (style != null) 'style': style!.toJson(),
      };

  bool get isToggle => type == typeToggle;
  bool get isSelect => type == typeSelect;

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
}
