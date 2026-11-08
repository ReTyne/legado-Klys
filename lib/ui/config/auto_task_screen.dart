import 'package:flutter/material.dart';

import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/auto_task.dart';
import 'package:legado_md3/help/storage/auto_task_service.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';

/// 定时任务全链路 UI（对齐官方原版 AutoTaskActivity / AutoTaskEditActivity /
/// AutoTaskDebugActivity）。
///
/// 任务 CRUD 全部走 DatabaseService 的
/// getAutoTasks / insertAutoTask / updateAutoTask / deleteAutoTask；
/// 立即运行、调度日志、下次运行时间走 [AutoTaskService]。
/// 入口由主程序（我的页/设置页）接入，本文件不反向依赖任何主壳页面。
class AutoTaskScreen extends StatefulWidget {
  const AutoTaskScreen({super.key});

  @override
  State<AutoTaskScreen> createState() => _AutoTaskScreenState();
}

class _AutoTaskScreenState extends State<AutoTaskScreen> {
  final DatabaseService _db = DatabaseService();
  List<AutoTask> _tasks = [];
  bool _loading = true;
  bool _schedulerOn = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _db.getAutoTasks();
    if (!mounted) return;
    setState(() {
      _tasks = list;
      _loading = false;
    });
  }

  /// 应用内调度开关：只在应用存活期间按分钟轮询；后台常驻与 JS 执行器
  /// 由主程序在启动期接线（见交付报告「需要主代理接线」）。
  void _toggleScheduler(bool v) {
    setState(() => _schedulerOn = v);
    if (v) {
      AutoTaskService.instance.start(onFinished: _load);
    } else {
      AutoTaskService.instance.stop();
    }
  }

  Future<void> _edit([AutoTask? task]) async {
    final result = await showDialog<AutoTask>(
      context: context,
      builder: (_) => _AutoTaskEditDialog(task: task),
    );
    if (result == null) return;
    if (result.id == null) {
      await _db.insertAutoTask(result);
    } else {
      await _db.updateAutoTask(result);
    }
    await _load();
  }

  Future<void> _delete(AutoTask task) async {
    if (task.id == null) return;
    final ok = await showAppConfirmDialog(
      context,
      title: '删除定时任务',
      content: '确定删除「${task.name}」吗？',
      confirmText: '删除',
      danger: true,
    );
    if (!ok) return;
    await _db.deleteAutoTask(task.id!);
    await _load();
  }

  Future<void> _runNow(AutoTask task) async {
    final result = await runWithBusyDialog<String>(
      context,
      message: '正在执行「${task.name}」…',
      task: AutoTaskService.instance.runNow(task),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(result)));
    await _load();
  }

  void _showLogs() {
    final logs = AutoTaskService.instance.logs;
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('调试日志'),
        content: SizedBox(
          width: double.maxFinite,
          child: logs.isEmpty
              ? const Text('暂无运行日志，点击任务的「立即运行」可产生记录。')
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: logs
                        .map((l) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text(l,
                                  style: const TextStyle(fontSize: 12)),
                            ))
                        .toList(),
                  ),
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('关闭')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('定时任务'),
        actions: [
          IconButton(
            tooltip: '调试日志',
            icon: const Icon(Icons.article_outlined),
            onPressed: _showLogs,
          ),
          IconButton(
            tooltip: '新增任务',
            icon: const Icon(Icons.add),
            onPressed: () => _edit(),
          ),
        ],
      ),
      body: _loading
          ? const AppLoadingIndicator()
          : ListView(
              children: [
                AppSwitchTile(
                  title: '运行定时任务（应用内调度）',
                  subtitle: '应用运行期间按分钟轮询执行；后台常驻与 JS 执行器由主程序在启动期接线',
                  value: _schedulerOn,
                  onChanged: _toggleScheduler,
                ),
                const AppSectionHeader('任务列表'),
                if (_tasks.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: AppEmptyState(
                      icon: Icons.schedule_outlined,
                      title: '暂无定时任务',
                      message: '支持刷新书架 / 缓存最新章 / 自动备份 / 更新规则订阅 / 自定义脚本',
                      action: FilledButton.icon(
                        onPressed: () => _edit(),
                        icon: const Icon(Icons.add),
                        label: const Text('新增任务'),
                      ),
                    ),
                  )
                else
                  for (final task in _tasks) _buildTaskTile(task, cs),
                const SizedBox(height: 24),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        tooltip: '新增任务',
        onPressed: () => _edit(),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildTaskTile(AutoTask task, ColorScheme cs) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: Icon(
          task.enabled == 1 ? Icons.schedule : Icons.schedule_outlined,
          color: task.enabled == 1 ? cs.primary : cs.onSurfaceVariant,
        ),
        title: Text(task.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${AutoTask.actionName(task.action)} · ${task.scheduleLabel}',
                style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 2),
            Text(AutoTaskService.describeNext(task),
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: task.enabled == 1,
              onChanged: (v) async {
                task.enabled = v ? 1 : 0;
                await _db.updateAutoTask(task);
                await _load();
              },
            ),
            PopupMenuButton<String>(
              tooltip: '任务操作',
              onSelected: (v) {
                switch (v) {
                  case 'run':
                    _runNow(task);
                    break;
                  case 'edit':
                    _edit(task);
                    break;
                  case 'delete':
                    _delete(task);
                    break;
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'run', child: Text('立即运行')),
                PopupMenuItem(value: 'edit', child: Text('编辑')),
                PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
            ),
          ],
        ),
        onTap: () => _edit(task),
      ),
    );
  }
}

/// 新增 / 编辑任务：名称、动作、每日定点 / 间隔、启用、脚本、备注。
class _AutoTaskEditDialog extends StatefulWidget {
  final AutoTask? task;
  const _AutoTaskEditDialog({this.task});

  @override
  State<_AutoTaskEditDialog> createState() => _AutoTaskEditDialogState();
}

class _AutoTaskEditDialogState extends State<_AutoTaskEditDialog> {
  late final TextEditingController _name;
  late final TextEditingController _js;
  late final TextEditingController _note;
  late String _action;
  late bool _intervalMode;
  late int _hour;
  late int _minute;
  late int _interval;
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    _name = TextEditingController(text: t?.name ?? '');
    _js = TextEditingController(text: t?.jsCode ?? '');
    _note = TextEditingController(text: t?.note ?? '');
    _action = t?.action ?? 'refresh';
    _hour = t?.hour ?? 8;
    _minute = t?.minute ?? 0;
    _interval = t?.intervalMinutes ?? 0;
    _intervalMode = _interval > 0;
    _enabled = (t?.enabled ?? 1) == 1;
  }

  @override
  void dispose() {
    _name.dispose();
    _js.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickAction() async {
    final v = await showAppRadioDialog<String>(
      context,
      title: '选择动作',
      groupValue: _action,
      options: [
        for (final a in AutoTask.actionLabels)
          AppRadioOption<String>(a, AutoTask.actionName(a)),
      ],
    );
    if (v != null) setState(() => _action = v);
  }

  Future<void> _pickScheduleMode() async {
    final v = await showAppRadioDialog<bool>(
      context,
      title: '调度方式',
      groupValue: _intervalMode,
      options: const [
        AppRadioOption<bool>(false, '每日定点'),
        AppRadioOption<bool>(true, '按间隔重复'),
      ],
    );
    if (v != null) setState(() => _intervalMode = v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.task == null ? '新增定时任务' : '编辑定时任务'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: '任务名称'),
            ),
            const SizedBox(height: 8),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('动作'),
              subtitle: Text(AutoTask.actionName(_action)),
              trailing: const Icon(Icons.arrow_drop_down),
              onTap: _pickAction,
            ),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('调度方式'),
              subtitle: Text(_intervalMode ? '按间隔重复' : '每日定点'),
              trailing: const Icon(Icons.arrow_drop_down),
              onTap: _pickScheduleMode,
            ),
            if (_intervalMode)
              AppStepTile(
                title: '间隔（分钟）',
                value: _interval,
                min: 1,
                max: 1440,
                onChanged: (v) => setState(() => _interval = v),
              )
            else ...[
              AppStepTile(
                title: '小时',
                value: _hour,
                min: 0,
                max: 23,
                onChanged: (v) => setState(() => _hour = v),
              ),
              AppStepTile(
                title: '分钟',
                value: _minute,
                min: 0,
                max: 59,
                onChanged: (v) => setState(() => _minute = v),
              ),
            ],
            const SizedBox(height: 8),
            TextField(
              controller: _js,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '脚本代码（动作为「执行自定义脚本」时生效）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _note,
              decoration: const InputDecoration(labelText: '备注（可选）'),
            ),
            AppSwitchTile(
              title: '启用任务',
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(
              context,
              AutoTask(
                id: widget.task?.id,
                name: name,
                action: _action,
                jsCode: _js.text,
                hour: _intervalMode ? 8 : _hour,
                minute: _intervalMode ? 0 : _minute,
                intervalMinutes: _intervalMode ? _interval : 0,
                enabled: _enabled ? 1 : 0,
                lastRunTime: widget.task?.lastRunTime,
                note: _note.text.trim(),
                customOrder: widget.task?.customOrder ?? 0,
              ),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
