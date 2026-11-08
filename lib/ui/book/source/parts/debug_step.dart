/// 由 source_debug_screen.dart 按「一类一文件」拆出的 _DebugStep。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../source_debug_screen.dart';


/// 分步调试步骤：记录执行状态、耗时（Stopwatch 统计）、请求 URL、返回摘要与引擎日志
class _DebugStep {
  _DebugStep(this.key, this.title, this.icon);
  final String key;
  final String title;
  final IconData icon;
  _StepStatus status = _StepStatus.idle;
  int durationMs = 0;
  String url = '';
  String summary = '';
  String? error;
  List<String> engineLogs = [];
}
