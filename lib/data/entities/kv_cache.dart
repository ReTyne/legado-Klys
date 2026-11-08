/// 通用带过期的 KV 缓存（对齐 Sigma CacheDao / deadline 语义）
class KvCache {
  String key;
  String? value;
  int deadline; // 0 表示永不过期

  KvCache({required this.key, this.value, this.deadline = 0});

  bool get expired =>
      deadline > 0 && DateTime.now().millisecondsSinceEpoch > deadline;

  Map<String, dynamic> toMap() => {
        'key': key,
        'value': value,
        'deadline': deadline,
      };

  factory KvCache.fromMap(Map<String, dynamic> m) => KvCache(
        key: m['key'] ?? '',
        value: m['value'],
        deadline: m['deadline'] ?? 0,
      );
}
