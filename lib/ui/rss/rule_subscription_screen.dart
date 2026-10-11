import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/data/model/rss_source.dart';
import 'package:legado_md3/data/model/replace_rule.dart';

/// 规则订阅页面 - 对齐原版RuleSubScreen
/// 订阅远程规则URL，可定时更新书源/RSS源/替换规则
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
  _RuleSub({required this.name, required this.url, this.type = 3, this.lastUpdate});
  Map<String, dynamic> toJson() => {'name': name, 'url': url, 'type': type, 'lastUpdate': lastUpdate};
  factory _RuleSub.fromJson(Map<String, dynamic> j) => _RuleSub(name: j['name'] ?? '', url: j['url'] ?? '', type: j['type'] ?? 3, lastUpdate: j['lastUpdate'] as int?);
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
    final list = p.getStringList('rule_subscriptions') ?? [];
    setState(() => _subs = list.map((s) => _RuleSub.fromJson(jsonDecode(s))).toList());
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList('rule_subscriptions', _subs.map((e) => jsonEncode(e.toJson())).toList());
  }

  void _edit([_RuleSub? sub]) {
    final nameCtl = TextEditingController(text: sub?.name ?? '');
    final urlCtl = TextEditingController(text: sub?.url ?? '');
    int type = sub?.type ?? 3;
    showDialog(context: context, builder: (context) => StatefulBuilder(builder: (context, setD) => AlertDialog(
      title: Text(sub == null ? '添加订阅' : '编辑订阅'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nameCtl, decoration: const InputDecoration(labelText: '名称')),
        const SizedBox(height: 12),
        TextField(controller: urlCtl, maxLines: 2, decoration: const InputDecoration(labelText: '订阅URL')),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          value: type,
          decoration: const InputDecoration(labelText: '规则类型'),
          items: List.generate(4, (i) => DropdownMenuItem(value: i, child: Text(_typeNames[i]))),
          onChanged: (v) => setD(() => type = v ?? 3),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: () async {
          if (urlCtl.text.isEmpty) return;
          final s = _RuleSub(name: nameCtl.text.isEmpty ? urlCtl.text : nameCtl.text, url: urlCtl.text, type: type);
          setState(() {
            if (sub == null) { _subs.add(s); } else { final i = _subs.indexOf(sub); if (i >= 0) _subs[i] = s; }
          });
          await _save();
          if (mounted) Navigator.pop(context);
        }, child: const Text('保存')),
      ],
    )));
  }

  Future<void> _update(_RuleSub sub) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text('正在更新订阅: ${sub.name}')));
    try {
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 15), receiveTimeout: const Duration(seconds: 30),
        headers: {'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Mobile'}));
      final resp = await dio.get<String>(sub.url);
      final body = resp.data ?? '';
      final count = await _importByType(sub.type, body);
      sub.lastUpdate = DateTime.now().millisecondsSinceEpoch;
      await _save();
      if (mounted) messenger.showSnackBar(SnackBar(content: Text('${sub.name} 更新完成，导入 $count 条')));
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text('${sub.name} 更新失败: $e')));
    }
  }

  /// 按类型解析并入库，返回导入条数；type=3 自动检测
  Future<int> _importByType(int type, String body) async {
    final text = body.trim();
    if (text.isEmpty) return 0;
    dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      // JSONL 兼容
      final lines = text.split(RegExp(r'[\r\n]+')).where((l) => l.trim().startsWith('{')).toList();
      if (lines.isEmpty) return 0;
      decoded = [for (final l in lines) jsonDecode(l)];
    }
    // 解包常见外层
    dynamic data = decoded;
    if (data is Map && !(data.containsKey('bookSourceUrl') || data.containsKey('sourceUrl') || data.containsKey('regex'))) {
      for (final k in ['data', 'bookSources', 'rssSources', 'replaceRules', 'sources', 'result', 'list']) {
        if (data[k] is List) { data = data[k]; break; }
      }
    }
    final list = data is List ? data : [data];
    final db = DatabaseService();
    int count = 0;
    // 自动检测：根据首个对象的特征字段判断类型
    int realType = type;
    if (realType == 3 && list.isNotEmpty && list.first is Map) {
      final m = Map<String, dynamic>.from(list.first);
      if (m.containsKey('bookSourceUrl')) { realType = 0; }
      else if (m.containsKey('sourceUrl') || m.containsKey('sourceName') && m.containsKey('articleStyle')) { realType = 1; }
      else if (m.containsKey('regex') || m.containsKey('replacement')) { realType = 2; }
    }
    for (final item in list) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      try {
        if (realType == 0 && (m['bookSourceUrl'] ?? '').toString().isNotEmpty) {
          await db.insertSource(BookSource.fromJson(m)); count++;
        } else if (realType == 1 && (m['sourceUrl'] ?? '').toString().isNotEmpty) {
          await db.insertRssSource(RssSource.fromJson(m)); count++;
        } else if (realType == 2 && (m['regex'] ?? m['pattern'] ?? '').toString().isNotEmpty) {
          await db.insertReplaceRule(ReplaceRule.fromMap(m)); count++;
        }
      } catch (_) {}
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('规则订阅'), actions: [
        if (_subs.isNotEmpty) TextButton.icon(
          onPressed: () async {
            for (final s in _subs) { await _update(s); }
          },
          icon: const Icon(Icons.sync, size: 18), label: const Text('全部更新'),
        ),
      ]),
      floatingActionButton: FloatingActionButton(onPressed: () => _edit(), child: const Icon(Icons.add)),
      body: _subs.isEmpty
        ? const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('暂无规则订阅\n\n订阅远程规则链接，可一键更新书源、RSS源、替换规则', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey))))
        : ListView.separated(
            itemCount: _subs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final s = _subs[i];
              return ListTile(
                leading: CircleAvatar(child: Text(_typeNames[s.type].substring(0, 1))),
                title: Text(s.name),
                subtitle: Text(s.url, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                trailing: PopupMenuButton<String>(onSelected: (v) async {
                  if (v == 'update') _update(s);
                  if (v == 'edit') _edit(s);
                  if (v == 'delete') { setState(() => _subs.removeAt(i)); await _save(); }
                }, itemBuilder: (_) => const [
                  PopupMenuItem(value: 'update', child: Text('更新')),
                  PopupMenuItem(value: 'edit', child: Text('编辑')),
                  PopupMenuItem(value: 'delete', child: Text('删除')),
                ]),
                onTap: () => _update(s),
              );
            },
          ),
    );
  }
}
