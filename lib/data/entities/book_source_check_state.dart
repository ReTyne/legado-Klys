/// 书源检测状态落库（对齐 Sigma CheckSource 的持久化结果）
class BookSourceCheckState {
  int? id;
  String origin;
  String name;
  int state; // 0 未检 / 1 可用 / 2 失效 / 3 超时
  int respondTime;
  String? errorMsg;
  int? checkTime;

  BookSourceCheckState({
    this.id,
    required this.origin,
    this.name = '',
    this.state = 0,
    this.respondTime = -1,
    this.errorMsg,
    this.checkTime,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'origin': origin,
        'name': name,
        'state': state,
        'respondTime': respondTime,
        'errorMsg': errorMsg,
        'checkTime': checkTime,
      };

  factory BookSourceCheckState.fromMap(Map<String, dynamic> m) =>
      BookSourceCheckState(
        id: m['id'],
        origin: m['origin'] ?? '',
        name: m['name'] ?? '',
        state: m['state'] ?? 0,
        respondTime: m['respondTime'] ?? -1,
        errorMsg: m['errorMsg'],
        checkTime: m['checkTime'],
      );
}
