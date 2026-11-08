/// 多套排版预设（对齐 Sigma ReadBookConfig.configList / shareLayout）
class ReadPreset {
  int? id;
  String name;
  String config; // ReadConfig 序列化 JSON
  int isDefault;
  int? createTime;

  ReadPreset({
    this.id,
    required this.name,
    required this.config,
    this.isDefault = 0,
    int? createTime,
  }) : createTime = createTime ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'config': config,
        'isDefault': isDefault,
        'createTime': createTime,
      };

  factory ReadPreset.fromMap(Map<String, dynamic> m) => ReadPreset(
        id: m['id'],
        name: m['name'] ?? '',
        config: m['config'] ?? '{}',
        isDefault: m['isDefault'] ?? 0,
        createTime: m['createTime'],
      );
}
