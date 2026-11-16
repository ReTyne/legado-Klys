import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/help/storage/rule_sub_auto_update.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';

/// 规则订阅页面 - RuleSubScreen
/// 订阅远程规则URL，可手动/自动更新书源/RSS源/替换规则
class RuleSubscriptionScreen extends StatefulWidget {
  const RuleSubscriptionScreen({super.key});

  @override
  State<RuleSubscriptionScreen> createState() => _RuleSubscriptionScreenState();
}

class _RuleSub {
  String name;
  String url;
  int type; // 0书源 1RSS源 2替换规则 3自动检测
  int? lastUpdate;

  /// 是否自动更新
  int autoUpdate;

  /// 自动更新间隔（小时，0=每次检查都更新）
  int updateInterval;

  _RuleSub({
    required this.name,
    required this.url,
    this.type = 3,
    this.lastUpdate,
    this.autoUpdate = 0,
    this.updateInterval = 0,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'url': url,
        'type': type,
        'lastUpdate': lastUpdate,
        'autoUpdate': autoUpdate,
        'updateInterval': updateInterval,
      };

  factory _RuleSub.fromJson(Map<String, dynamic> j) => _RuleSub(
        name: (j['name'] ?? '') as String,
        url: (j['url'] ?? '') as String,
        type: (j['type'] ?? 3) as int,
        lastUpdate: j['lastUpdate'] as int?,
        autoUpdate: (j['autoUpdate'] == true || j['autoUpdate'] == 1) ? 1 : 0,
        updateInterval: (j['updateInterval'] ?? 0) is int
            ? (j['updateInterval'] ?? 0) as int
            : 0,
      );
}

class _RuleSubscriptionScreenState extends State<RuleSubscriptionScreen> {
  static const _typeNames = ['书源', 'RSS源', '替换规则', '自动检测'];
  List<_RuleSub> _subs = [];
  bool _silent = false;
  bool _keepLocal = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(RuleSubAutoUpdate.prefsKey) ?? [];
    final silent = await RuleSubAutoUpdate.isSilentUpdate();
    final keepLocal = await RuleSubAutoUpdate.keepLocalOnConflict();
    if (!mounted) return;
    setState(() {
      _subs = list
          .map((s) => _RuleSub.fromJson(jsonDecode(s) as Map<String, dynamic>))
          .toList();
      _silent = silent;
      _keepLocal = keepLocal;
    });
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(RuleSubAutoUpdate.prefsKey,
        _subs.map((e) => jsonEncode(e.toJson())).toList());
  }

  void _edit([_RuleSub? sub]) {
    final nameCtl = TextEditingController(text: sub?.name ?? '');
    final urlCtl = TextEditingController(text: sub?.url ?? '');
    final intervalCtl =
        TextEditingController(text: '${sub?.updateInterval ?? 0}');
    int type = sub?.type ?? 3;
    bool autoUpdate = sub?.autoUpdate == 1;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          title: Text(sub == null ? '添加订阅' : '编辑订阅'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: nameCtl,
                  decoration: const InputDecoration(labelText: '名称')),
              const SizedBox(height: AppSpacing.m),
              TextField(
                  controller: urlCtl,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: '订阅URL')),
              const SizedBox(height: AppSpacing.m),
              DropdownButtonFormField<int>(
                value: type,
                decoration: const InputDecoration(labelText: '规则类型'),
                items: List.generate(
                    4,
                    (i) =>
                        DropdownMenuItem(value: i, child: Text(_typeNames[i]))),
                onChanged: (v) => setD(() => type = v ?? 3),
              ),
              const SizedBox(height: AppSpacing.s),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('自动更新'),
                subtitle: const Text('启动或到间隔时自动拉取该订阅',
                    style: TextStyle(fontSize: 11)),
                value: autoUpdate,
                onChanged: (v) => setD(() => autoUpdate = v),
              ),
              TextField(
                controller: intervalCtl,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: '更新间隔（小时，0=每次检查都更新）'),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                if (urlCtl.text.trim().isEmpty) return;
                final hours = int.tryParse(intervalCtl.text.trim()) ?? 0;
                final s = _RuleSub(
                  name: nameCtl.text.trim().isEmpty
                      ? urlCtl.text.trim()
                      : nameCtl.text.trim(),
                  url: urlCtl.text.trim(),
                  type: type,
                  lastUpdate: sub?.lastUpdate,
                  autoUpdate: autoUpdate ? 1 : 0,
                  updateInterval: hours < 0 ? 0 : hours,
                );
                setState(() {
                  if (sub == null) {
                    _subs.add(s);
                  } else {
                    final i = _subs.indexOf(sub);
                    if (i >= 0) _subs[i] = s;
                  }
                });
                await _save();
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _update(_RuleSub sub) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text('正在更新订阅: ${sub.name}')));
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Mobile'
        },
      ));
      final resp = await dio.get<String>(sub.url);
      // 直接复用共享服务的解析逻辑，避免与自动更新分叉
      final count = await _importByType(sub.type, resp.data ?? '',
          keepLocalOnConflict: _keepLocal, silent: _silent);
      sub.lastUpdate = DateTime.now().millisecondsSinceEpoch;
      await _save();
      if (mounted) {
        setState(() {});
        messenger.showSnackBar(
            SnackBar(content: Text('${sub.name} 更新完成，导入 $count 条')));
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('${sub.name} 更新失败: $e')));
      }
    }
  }

  /// 按类型解析并入库：直接复用共享服务 [RuleSubAutoUpdate.importByType]，
  /// 消除订阅页与自动更新的两处解析分叉（type=3 自动检测）。
  Future<int> _importByType(
    int type,
    String body, {
    bool keepLocalOnConflict = false,
    bool silent = false,
  }) =>
      RuleSubAutoUpdate.importByType(
        type,
        body,
        keepLocalOnConflict: keepLocalOnConflict,
        silent: silent,
      );

  /// 导入前对比预览：新增 / 变更 / 删除三类计数，再决定是否导入。
  Future<void> _preview(_RuleSub sub) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Mobile'
        },
      ));
      final resp = await dio.get<String>(sub.url);
      final body = resp.data ?? '';
      final preview = await RuleSubAutoUpdate.previewImport(sub.type, body);
      if (!mounted) return;
      final d = preview.diff;
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) {
          final scheme = Theme.of(c).colorScheme;
          return AlertDialog(
            title: Text('对比预览：${sub.name}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(preview.summary,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: AppSpacing.s),
                  _diffSection('新增', d.added, scheme),
                  _diffSection('变更', d.changed, scheme),
                  _diffSection('删除', d.deleted, scheme),
                  const SizedBox(height: AppSpacing.s),
                  Text('冲突时保留本地修改：${_keepLocal ? '开' : '关'}',
                      style: const TextStyle(fontSize: 11)),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('取消')),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('按策略导入'),
              ),
            ],
          );
        },
      );
      if (ok != true || !mounted) return;
      final count = await _importByType(sub.type, body,
          keepLocalOnConflict: _keepLocal, silent: _silent);
      sub.lastUpdate = DateTime.now().millisecondsSinceEpoch;
      await _save();
      if (mounted) setState(() {});
      messenger.showSnackBar(SnackBar(content: Text('导入 $count 条')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('预览失败: $e')));
    }
  }

  Widget _diffSection(String label, List<String> ids, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label ${ids.length}',
              style: TextStyle(
                  fontSize: 12, color: label == '删除' ? cs.error : cs.primary)),
          if (ids.isNotEmpty)
            Text(
              ids.take(8).join('\n') + (ids.length > 8 ? '\n…' : ''),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace'),
            ),
        ],
      ),
    );
  }

  /// 更新策略设置：静默更新 + 冲突时保留本地修改。
  Future<void> _showSettings() async {
    var silent = _silent;
    var keepLocal = _keepLocal;
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('更新策略'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('静默更新'),
              subtitle:
                  const Text('自动更新不弹提示、不写更新日志', style: TextStyle(fontSize: 11)),
              value: silent,
              onChanged: (v) => setD(() => silent = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('冲突时保留本地修改'),
              subtitle: const Text('订阅内容与本地有差异时不覆盖本地条目',
                  style: TextStyle(fontSize: 11)),
              value: keepLocal,
              onChanged: (v) => setD(() => keepLocal = v),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                await RuleSubAutoUpdate.setSilentUpdate(silent);
                await RuleSubAutoUpdate.setKeepLocalOnConflict(keepLocal);
                if (mounted) {
                  setState(() {
                    _silent = silent;
                    _keepLocal = keepLocal;
                  });
                }
                if (c.mounted) Navigator.pop(c);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateAll() async {
    for (final s in _subs) {
      await _update(s);
    }
  }

  /// 「立即检查自动更新」：调用共享服务的启动期调度逻辑（runDue）。
  Future<void> _runAutoUpdate() async {
    final messenger = ScaffoldMessenger.of(context);
    final count = await runWithBusyDialog<int>(
      context,
      message: '正在检查自动更新…',
      task: RuleSubAutoUpdate.runDue(),
    );
    await _load();
    messenger.showSnackBar(SnackBar(content: Text('已自动更新 $count 条订阅')));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('规则订阅'),
        actions: [
          IconButton(
            tooltip: '更新策略',
            icon: const Icon(Icons.tune_outlined),
            onPressed: _showSettings,
          ),
          IconButton(
            tooltip: '立即检查自动更新',
            icon: const Icon(Icons.update_outlined),
            onPressed: _runAutoUpdate,
          ),
          if (_subs.isNotEmpty)
            TextButton.icon(
              onPressed: _updateAll,
              icon: const Icon(Icons.sync, size: 18),
              label: const Text('全部更新'),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: '添加订阅',
        onPressed: () => _edit(),
        child: const Icon(Icons.add),
      ),
      body: _subs.isEmpty
          ? AppEmptyState(
              icon: Icons.dynamic_feed_outlined,
              title: '暂无规则订阅',
              message: '订阅远程规则链接，可一键更新书源、RSS源、替换规则',
              action: FilledButton.icon(
                onPressed: () => _edit(),
                icon: const Icon(Icons.add),
                label: const Text('添加订阅'),
              ),
            )
          : ListView.separated(
              itemCount: _subs.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final s = _subs[i];
                final autoLabel = s.autoUpdate == 1
                    ? ' · 自动更新${s.updateInterval > 0 ? ' ${s.updateInterval}h' : ''}'
                    : '';
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: cs.secondaryContainer,
                    child: Text(_typeNames[s.type].substring(0, 1),
                        style: TextStyle(color: cs.onSecondaryContainer)),
                  ),
                  title: Text(s.name),
                  subtitle: Text('${s.url}$autoLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11)),
                  trailing: PopupMenuButton<String>(
                    tooltip: '订阅操作',
                    onSelected: (v) async {
                      if (v == 'update') _update(s);
                      if (v == 'preview') _preview(s);
                      if (v == 'edit') _edit(s);
                      if (v == 'delete') {
                        setState(() => _subs.removeAt(i));
                        await _save();
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'update', child: Text('更新')),
                      PopupMenuItem(value: 'preview', child: Text('对比预览后导入')),
                      PopupMenuItem(value: 'edit', child: Text('编辑')),
                      PopupMenuItem(value: 'delete', child: Text('删除')),
                    ],
                  ),
                  onTap: () => _update(s),
                );
              },
            ),
    );
  }
}
