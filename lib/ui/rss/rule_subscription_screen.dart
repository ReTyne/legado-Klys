import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/help/storage/rule_sub_auto_update.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';

/// 规则订阅页面 - 对齐原版RuleSubScreen
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
  /// 是否自动更新（对齐 RuleSubAutoUpdate.runDue 读取的 autoUpdate 键）
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(RuleSubAutoUpdate.prefsKey) ?? [];
    if (!mounted) return;
    setState(() => _subs = list
        .map((s) => _RuleSub.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList());
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
              TextField(controller: nameCtl,
                  decoration: const InputDecoration(labelText: '名称')),
              const SizedBox(height: 12),
              TextField(controller: urlCtl, maxLines: 2,
                  decoration: const InputDecoration(labelText: '订阅URL')),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: type,
                decoration: const InputDecoration(labelText: '规则类型'),
                items: List.generate(4,
                    (i) => DropdownMenuItem(value: i, child: Text(_typeNames[i]))),
                onChanged: (v) => setD(() => type = v ?? 3),
              ),
              const SizedBox(height: 8),
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
                decoration: const InputDecoration(
                    labelText: '更新间隔（小时，0=每次检查都更新）'),
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
      final count = await _importByType(sub.type, resp.data ?? '');
      sub.lastUpdate = DateTime.now().millisecondsSinceEpoch;
      await _save();
      if (mounted) {
        setState(() {});
        messenger.showSnackBar(
            SnackBar(content: Text('${sub.name} 更新完成，导入 $count 条')));
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
            SnackBar(content: Text('${sub.name} 更新失败: $e')));
      }
    }
  }

  /// 按类型解析并入库：直接复用共享服务 [RuleSubAutoUpdate.importByType]，
  /// 消除订阅页与自动更新的两处解析分叉（type=3 自动检测）。
  Future<int> _importByType(int type, String body) =>
      RuleSubAutoUpdate.importByType(type, body);

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
                      if (v == 'edit') _edit(s);
                      if (v == 'delete') {
                        setState(() => _subs.removeAt(i));
                        await _save();
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'update', child: Text('更新')),
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
