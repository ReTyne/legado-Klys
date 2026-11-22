int? _bgInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString().trim());
}

bool _bgBool(dynamic v, bool fallback) {
  if (v == null) return fallback;
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = v.toString().trim().toLowerCase();
  if (s == 'true' || s == '1') return true;
  if (s == 'false' || s == '0') return false;
  return fallback;
}

class BookGroup {
  int? id;
  String name;
  int order;
  int show;
  String? cover;

  /// 分组位标志与刷新/排序行为配置。
  int? groupId;
  bool enableRefresh;
  int? bookSort;
  bool onlyUpdateRead;

  BookGroup({
    this.id,
    required this.name,
    this.order = 0,
    this.show = 1,
    this.cover,
    this.groupId,
    this.enableRefresh = true,
    this.bookSort,
    this.onlyUpdateRead = false,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'order': order,
    'show': show,
    'cover': cover,
    'groupId': groupId,
    'enableRefresh': enableRefresh ? 1 : 0,
    'bookSort': bookSort,
    'onlyUpdateRead': onlyUpdateRead ? 1 : 0,
  };

  factory BookGroup.fromMap(Map<String, dynamic> map) => BookGroup(
    id: _bgInt(map['id']),
    name: (map['name'] ?? map['groupName'] ?? '').toString(),
    order: _bgInt(map['order'] ?? map['sortOrder']) ?? 0,
    show: _bgInt(map['show']) ?? 1,
    cover: map['cover']?.toString(),
    groupId: _bgInt(map['groupId']),
    enableRefresh: _bgBool(map['enableRefresh'], true),
    bookSort: _bgInt(map['bookSort']),
    onlyUpdateRead: _bgBool(map['onlyUpdateRead'], false),
  );
}
