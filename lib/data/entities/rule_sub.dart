class RuleSub {
  int? id;
  String name;
  String url;
  String type; // bookSource, rssSource, replaceRule, dictRule, txtTocRule, highlightRule
  int enabled;
  int? lastUpdateTime;
  int? customOrder;
  /// 是否启动期自动更新（对齐 legado-E 的 ruleSubsUp()）。
  int autoUpdate;
  /// 自动更新间隔（小时，0=每次启动检查）。
  int updateInterval;

  RuleSub({this.id, required this.name, required this.url, required this.type, this.enabled = 1, this.lastUpdateTime, this.customOrder, this.autoUpdate = 0, this.updateInterval = 0});

  Map<String, dynamic> toMap() => {
    'id': id, 'name': name, 'url': url, 'type': type,
    'enabled': enabled, 'lastUpdateTime': lastUpdateTime, 'customOrder': customOrder,
    'autoUpdate': autoUpdate, 'updateInterval': updateInterval,
  };

  factory RuleSub.fromMap(Map<String, dynamic> map) => RuleSub(
    id: map['id'], name: map['name'] ?? '', url: map['url'] ?? '',
    type: map['type'] ?? 'bookSource', enabled: map['enabled'] ?? 1,
    lastUpdateTime: map['lastUpdateTime'], customOrder: map['customOrder'],
    autoUpdate: map['autoUpdate'] ?? 0, updateInterval: map['updateInterval'] ?? 0,
  );
}
