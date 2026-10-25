/// 发现分类（对齐 legado `io.legado.app.data.entities.rule.ExploreKind`）。
///
/// 由 `<js>`/`@js:` 型 exploreUrl 求值得到 JSON 数组解析而来：
/// ```json
/// [{"title": "个性推荐", "url": "https://...", "type": "url",
///   "style": {"layout_flexGrow": 1, "layout_flexBasisPercent": 0.45}}]
/// ```
/// type 取值：url（分类入口）/ text（输入框）/ button（按钮）/
/// toggle（切换）/ select（下拉选择）。
class ExploreKind {
  final String title;
  final String? url;
  final String type;
  final String? action;
  final List<String>? chars;
  final String? defaultValue;
  final String? viewName;
  final Map<String, dynamic>? style;

  const ExploreKind({
    this.title = '',
    this.url,
    this.type = 'url',
    this.action,
    this.chars,
    this.defaultValue,
    this.viewName,
    this.style,
  });

  static const String typeUrl = 'url';
  static const String typeText = 'text';
  static const String typeButton = 'button';
  static const String typeToggle = 'toggle';
  static const String typeSelect = 'select';

  bool get isUrl => type == typeUrl;
  bool get isControl => type != typeUrl;

  /// 是否为错误占位（legado 在 exploreUrl 求值失败时写入
  /// `ExploreKind("ERROR:msg", stackTrace)`，UI 点击时展示错误详情）。
  bool get isError => title.startsWith('ERROR:');

  factory ExploreKind.fromJson(Map<String, dynamic> json) {
    return ExploreKind(
      title: (json['title'] ?? '').toString(),
      url: json['url']?.toString(),
      type: (json['type'] ?? 'url').toString(),
      action: json['action']?.toString(),
      chars: (json['chars'] as List?)?.map((e) => e?.toString() ?? '').toList(),
      defaultValue: json['default']?.toString(),
      viewName: json['viewName']?.toString(),
      style: json['style'] is Map ? Map<String, dynamic>.from(json['style'] as Map) : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        if (url != null) 'url': url,
        'type': type,
        if (action != null) 'action': action,
        if (chars != null) 'chars': chars,
        if (defaultValue != null) 'default': defaultValue,
        if (viewName != null) 'viewName': viewName,
        if (style != null) 'style': style,
      };

  @override
  bool operator ==(Object other) =>
      other is ExploreKind &&
      other.title == title &&
      other.type == type &&
      other.url == url &&
      other.action == action &&
      other.defaultValue == defaultValue;

  @override
  int get hashCode => Object.hash(title, type, url, action, defaultValue);
}
