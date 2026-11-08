/// 由 backup_service.dart 按「一类一文件」拆出的 BackupResult。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../backup_service.dart';


/// 备份恢复结果
class BackupResult {
  bool success = false;
  String? error;
  int booksRestored = 0;
  int booksFailed = 0;
  int sourcesRestored = 0;
  int sourcesFailed = 0;
  int rulesRestored = 0;
  int rulesFailed = 0;

  /// 其他类型的恢复计数（key -> 条数）
  final Map<String, int> otherCounts = {};

  /// 记录某类型恢复条数
  void count(String key, [int n = 1]) => otherCounts[key] = (otherCounts[key] ?? 0) + n;

  String get summary {
    if (!success) return error ?? '恢复失败';
    final parts = <String>[
      '书籍: $booksRestored成功/$booksFailed失败',
      '书源: $sourcesRestored成功/$sourcesFailed失败',
      '规则: $rulesRestored成功/$rulesFailed失败',
    ];
    otherCounts.forEach((k, v) => parts.add('$k: $v'));
    return parts.join(', ');
  }
}
