import 'dart:async';

import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/auto_task.dart';
import 'package:legado_md3/help/storage/backup_service.dart';
import 'package:legado_md3/help/storage/download_service.dart';
import 'package:legado_md3/help/storage/auto_update_service.dart';
import 'package:legado_md3/help/storage/rule_sub_auto_update.dart';

/// 定时任务调度器（对齐 legado 官方原版 AutoTaskScheduler / AutoTaskRunner）。
///
/// 应用运行期间以 1 分钟为节拍轮询 [AutoTask.nextRunTime]，到点执行动作并
/// 回写 lastRunTime。动作全部复用项目既有服务，保证调用链真实连通：
/// - refresh → AutoUpdateService._run 的公开入口 [AutoUpdateService.instance]
/// - cache   → DownloadService 为「最近阅读」的书缓存最新章节
/// - backup  → BackupService.runAutoBackup（真实 zip + 加密备份）
/// - ruleSub → RuleSubAutoUpdate.runDue()
/// - js      → 交给 [jsRunner] 回调（由 UI 层注入 JS 引擎执行，避免 service 层
///             直接依赖 flutter_webview/JS 运行时；未注入时记为跳过并留日志）
class AutoTaskService {
  AutoTaskService._();
  static final AutoTaskService instance = AutoTaskService._();

  final DatabaseService _db = DatabaseService();
  Timer? _ticker;
  bool _running = false;
  final List<String> _logs = <String>[];

  /// 最近 50 条执行日志（调试页展示）。
  List<String> get logs => List.unmodifiable(_logs);

  /// 自定义 JS 动作执行器（返回执行结果文本）。由 UI/主程序注入。
  Future<String> Function(String code)? jsRunner;

  void _log(String msg) {
    _logs.insert(0, '${DateTime.now().toIso8601String().substring(5, 19)} $msg');
    if (_logs.length > 50) _logs.removeLast();
  }

  /// 启动调度（幂等）。[onFinished] 用于 UI 刷新列表。
  void start({void Function()? onFinished}) {
    if (_ticker != null) return;
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) => _tick(onFinished));
    // 启动后 10 秒先跑一次，避免首分钟空窗
    Timer(const Duration(seconds: 10), () => _tick(onFinished));
  }

  void stop() {
    _ticker?.cancel();
    _ticker = null;
  }

  Future<void> _tick(void Function()? onFinished) async {
    if (_running) return;
    _running = true;
    try {
      final tasks = await _db.getAutoTasks();
      final now = DateTime.now().millisecondsSinceEpoch;
      var changed = false;
      for (final t in tasks) {
        if (t.enabled != 1) continue;
        if (t.nextRunTime(from: now) > now + 60000) continue;
        final result = await runNow(t);
        _log('${t.name}: $result');
        t.lastRunTime = now;
        await _db.updateAutoTask(t);
        changed = true;
      }
      if (changed) onFinished?.call();
    } finally {
      _running = false;
    }
  }

  /// 立即执行一条任务（调试页「运行」按钮复用），返回结果描述。
  Future<String> runNow(AutoTask t) async {
    switch (t.action) {
      case 'refresh':
        // 复用既有自动更新服务：以一次 start() 无法强制触发，故调用其公开 runOnce。
        final n = await AutoUpdateService.instance.runOnce();
        return '刷新书架完成，更新 $n 本';
      case 'cache':
        final n = await DownloadService.instance.enqueueLatestChapters();
        return '已加入 $n 个缓存任务';
      case 'backup':
        final path = await BackupService.runAutoBackup();
        return path == null ? '备份未触发（未到间隔）' : '备份完成：$path';
      case 'ruleSub':
        final n = await RuleSubAutoUpdate.runDue();
        return '更新 $n 条订阅';
      case 'js':
        final runner = jsRunner;
        if (runner == null || t.jsCode.trim().isEmpty) {
          return '跳过：未注入 JS 执行器或脚本为空';
        }
        try {
          return await runner(t.jsCode);
        } catch (e) {
          return '脚本执行失败：$e';
        }
      default:
        return '未知动作：${t.action}';
    }
  }

  /// 依据当前时间判断任务是否即将执行（供 UI 展示「下次运行」）。
  static String describeNext(AutoTask t) {
    if (t.enabled != 1) return '已停用';
    final next = DateTime.fromMillisecondsSinceEpoch(t.nextRunTime());
    return '${t.scheduleLabel} · 下次 ${next.month}/${next.day} '
        '${next.hour.toString().padLeft(2, '0')}:${next.minute.toString().padLeft(2, '0')}';
  }
}
