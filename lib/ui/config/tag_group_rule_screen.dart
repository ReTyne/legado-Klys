import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/tag_group_rule.dart';

/// 标签分组规则页面 - 对齐原版TagGroupRuleScreen
class TagGroupRuleScreen extends StatefulWidget {
  const TagGroupRuleScreen({super.key});

  @override
  State<TagGroupRuleScreen> createState() => _TagGroupRuleScreenState();
}

class _TagGroupRuleScreenState extends State<TagGroupRuleScreen> {
  final _db = DatabaseService();
  List<TagGroupRule> _rules = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rules = await _db.getTagGroupRules();
    setState(() { _rules = rules; _loading = false; });
  }

  void _edit([TagGroupRule? rule]) {
    final nameCtl = TextEditingController(text: rule?.name ?? '');
    final patternCtl = TextEditingController(text: rule?.pattern ?? '');
    final groupCtl = TextEditingController(text: rule?.group ?? '');
    bool enabled = rule?.enabled == 1;
    showDialog(context: context, builder: (context) => StatefulBuilder(builder: (context, setD) => AlertDialog(
      title: Text(rule == null ? '添加分组规则' : '编辑分组规则'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nameCtl, decoration: const InputDecoration(labelText: '规则名称')),
        const SizedBox(height: 12),
        TextField(controller: patternCtl, maxLines: 2, decoration: const InputDecoration(labelText: '标签正则', hintText: '匹配书籍标签的正则表达式')),
        const SizedBox(height: 12),
        TextField(controller: groupCtl, decoration: const InputDecoration(labelText: '移动到分组', hintText: '匹配后自动归入的分组')),
        SwitchListTile(contentPadding: EdgeInsets.zero, dense: true, title: const Text('启用'), value: enabled, onChanged: (v) => setD(() => enabled = v)),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: () async {
          if (nameCtl.text.isEmpty || patternCtl.text.isEmpty) return;
          final r = TagGroupRule(
            id: rule?.id, name: nameCtl.text, pattern: patternCtl.text,
            group: groupCtl.text, enabled: enabled ? 1 : 0, order: rule?.order,
          );
          if (rule == null) { await _db.insertTagGroupRule(r); } else { await _db.updateTagGroupRule(r); }
          if (mounted) { Navigator.pop(context); _load(); }
        }, child: const Text('保存')),
      ],
    )));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('标签分组规则'), actions: [
        PopupMenuButton<String>(onSelected: (v) {
          if (v == 'help') showDialog(context: context, builder: (c) => const AlertDialog(title: Text('说明'), content: Text('标签分组规则可根据书籍标签自动将书籍归入指定分组。使用正则表达式匹配标签内容。')));
        }, itemBuilder: (_) => const [PopupMenuItem(value: 'help', child: Text('帮助'))]),
      ]),
      floatingActionButton: FloatingActionButton(onPressed: () => _edit(), child: const Icon(Icons.add)),
      body: _loading ? const Center(child: CircularProgressIndicator()) : _rules.isEmpty
        ? const Center(child: Text('暂无标签分组规则', style: TextStyle(color: Colors.grey)))
        : ListView.separated(
            itemCount: _rules.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final r = _rules[i];
              return ListTile(
                title: Text(r.name),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('正则: ${r.pattern}', style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (r.group != null) Text('→ ${r.group}', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.primary)),
                ]),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Switch(value: r.enabled == 1, onChanged: (v) async { r.enabled = v ? 1 : 0; await _db.updateTagGroupRule(r); _load(); }),
                  IconButton(icon: const Icon(Icons.copy, size: 20), onPressed: () { Clipboard.setData(ClipboardData(text: r.pattern)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制'))); }),
                  IconButton(icon: const Icon(Icons.delete_outline, size: 20), onPressed: () async { if (r.id != null) await _db.deleteTagGroupRule(r.id!); _load(); }),
                ]),
                onTap: () => _edit(r),
              );
            },
          ),
    );
  }
}
