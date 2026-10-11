import 'dart:convert';

/// 首页模块类型
enum HomepageModuleType {
  banner,      // 横幅
  buttonGroup, // 按钮组
  card,        // 卡片
  grid,        // 网格
  gridRanking, // 网格排行
  ranking,     // 排行榜
  waterfall,   // 瀑布流
  custom,      // 自定义
}

/// 首页模块
class HomepageModule {
  int? id;
  String name;
  HomepageModuleType type;
  String? sourceUrl;      // 关联书源URL
  String? exploreUrl;     // 发现URL
  String? config;         // JSON配置
  int customOrder;
  bool enabled;

  HomepageModule({
    this.id,
    required this.name,
    required this.type,
    this.sourceUrl,
    this.exploreUrl,
    this.config,
    this.customOrder = 0,
    this.enabled = true,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'type': type.index,
    'sourceUrl': sourceUrl,
    'exploreUrl': exploreUrl,
    'config': config,
    'customOrder': customOrder,
    'enabled': enabled ? 1 : 0,
  };

  factory HomepageModule.fromMap(Map<String, dynamic> map) => HomepageModule(
    id: map['id'] as int?,
    name: map['name'] as String? ?? '',
    type: HomepageModuleType.values[map['type'] as int? ?? 0],
    sourceUrl: map['sourceUrl'] as String?,
    exploreUrl: map['exploreUrl'] as String?,
    config: map['config'] as String?,
    customOrder: map['customOrder'] as int? ?? 0,
    enabled: (map['enabled'] as int? ?? 1) == 1,
  );

  String toJson() => jsonEncode(toMap());
  factory HomepageModule.fromJson(String str) => HomepageModule.fromMap(jsonDecode(str));
}

/// 首页模块自定义集
class HomepageCustomSet {
  int? id;
  String name;
  String? moduleIds; // JSON数组
  int customOrder;

  HomepageCustomSet({
    this.id,
    required this.name,
    this.moduleIds,
    this.customOrder = 0,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'moduleIds': moduleIds,
    'customOrder': customOrder,
  };

  factory HomepageCustomSet.fromMap(Map<String, dynamic> map) => HomepageCustomSet(
    id: map['id'] as int?,
    name: map['name'] as String? ?? '',
    moduleIds: map['moduleIds'] as String?,
    customOrder: map['customOrder'] as int? ?? 0,
  );
}
