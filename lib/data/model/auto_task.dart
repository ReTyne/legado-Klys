/// 定时任务实体（对齐 legado 官方原版 AutoTask / AutoTaskRule）。
///
/// 一条任务 = 一个「动作 + 一个调度策略」。动作既可是内置预设
/// （刷新书架 / 缓存最新章 / 自动备份 / 更新书源订阅），也可是书源 JS。
/// 调度支持每日定点（hour/minute）与按分钟间隔（intervalMinutes）两种。
class AutoTask {
  AutoTask({
    this.id,
    required this.name,
    this.action = 'refresh',
    this.jsCode = '',
    this.hour = 8,
    this.minute = 0,
    this.intervalMinutes = 0,
    this.enabled = 1,
    this.lastRunTime,
    this.note = '',
    this.customOrder = 0,
  });

  final int? id;
  String name;

  /// 动作标识：refresh / cache / backup / ruleSub / js
  String action;

  /// action == 'js' 时要执行的代码（可引用 source/java 桥）。
  String jsCode;

  /// 每日定点小时（0-23），仅 intervalMinutes==0 时生效。
  int hour;
  int minute;

  /// >0 时按间隔触发，忽略 hour/minute。
  int intervalMinutes;
  int enabled;
  int? lastRunTime;
  String note;
  int customOrder;

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'action': action,
        'jsCode': jsCode,
        'hour': hour,
        'minute': minute,
        'intervalMinutes': intervalMinutes,
        'enabled': enabled,
        'lastRunTime': lastRunTime,
        'note': note,
        'customOrder': customOrder,
      };

  factory AutoTask.fromMap(Map<String, dynamic> m) => AutoTask(
        id: m['id'] as int?,
        name: (m['name'] ?? '') as String,
        action: (m['action'] ?? 'refresh') as String,
        jsCode: (m['jsCode'] ?? '') as String,
        hour: (m['hour'] ?? 8) as int,
        minute: (m['minute'] ?? 0) as int,
        intervalMinutes: (m['intervalMinutes'] ?? 0) as int,
        enabled: (m['enabled'] ?? 1) as int,
        lastRunTime: m['lastRunTime'] as int?,
        note: (m['note'] ?? '') as String,
        customOrder: (m['customOrder'] ?? 0) as int,
      );

  Map<String, dynamic> toJson() => toMap();
  factory AutoTask.fromJson(Map<String, dynamic> j) => AutoTask.fromMap(j);

  /// 计算下一次触发时间（毫秒）。
  int nextRunTime({int? from}) {
    final now = from ?? DateTime.now().millisecondsSinceEpoch;
    final base = lastRunTime ?? 0;
    if (intervalMinutes > 0) {
      final interval = intervalMinutes * 60 * 1000;
      final next = base + interval;
      return next > now ? next : now + interval;
    }
    final local = DateTime.fromMillisecondsSinceEpoch(now);
    var next = DateTime(local.year, local.month, local.day, hour, minute);
    if (next.millisecondsSinceEpoch <= now) {
      next = next.add(const Duration(days: 1));
    }
    return next.millisecondsSinceEpoch;
  }

  String get scheduleLabel => intervalMinutes > 0
      ? '每 $intervalMinutes 分钟'
      : '每日 ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  static const List<String> actionLabels = [
    'refresh',
    'cache',
    'backup',
    'ruleSub',
    'js',
  ];

  static String actionName(String a) => switch (a) {
        'cache' => '缓存最新章节',
        'backup' => '自动备份',
        'ruleSub' => '更新规则订阅',
        'js' => '执行自定义脚本',
        _ => '刷新书架',
      };
}
