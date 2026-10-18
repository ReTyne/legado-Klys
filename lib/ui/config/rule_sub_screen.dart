import 'package:flutter/material.dart';
import 'package:legado_md3/data/model/rule_sub.dart';
import 'package:legado_md3/data/local/app_database.dart';

class RuleSubScreen extends StatefulWidget {
  const RuleSubScreen({super.key});

  @override
  State<RuleSubScreen> createState() => _RuleSubScreenState();
}

class _RuleSubScreenState extends State<RuleSubScreen> {
  final DatabaseService _db = DatabaseService();
  List<RuleSub> _subs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSubs();
  }

  Future<void> _loadSubs() async {
    final subs = await _db.getRuleSubs();
    setState(() {
      _subs = subs;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('规则订阅'),
        actions: [IconButton(icon: const Icon(Icons.add), onPressed: _showAddSub)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _subs.isEmpty
              ? const Center(child: Text('暂无订阅，点击右上角添加'))
              : ListView.builder(
                  itemCount: _subs.length,
                  itemBuilder: (context, index) {
                    final sub = _subs[index];
                    return Card(
                      child: ListTile(
                        leading: Icon(_getTypeIcon(sub.type)),
                        title: Text(sub.name),
                        subtitle: Text('${sub.type} · ${sub.url}', maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: Switch(value: sub.enabled == 1, onChanged: (v) => _toggleSub(sub, v)),
                        onLongPress: () => _showSubMenu(sub),
                      ),
                    );
                  },
                ),
    );
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'bookSource': return Icons.menu_book;
      case 'rssSource': return Icons.rss_feed;
      case 'replaceRule': return Icons.find_replace;
      case 'dictRule': return Icons.translate;
      case 'txtTocRule': return Icons.list_alt;
      default: return Icons.rule;
    }
  }

  void _showAddSub() {
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    String selectedType = 'bookSource';
    showDialog(context: context, builder: (context) => StatefulBuilder(builder: (context, setState) => AlertDialog(
      title: const Text('添加订阅'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nameController, decoration: const InputDecoration(labelText: '名称', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: urlController, decoration: const InputDecoration(labelText: '订阅URL', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(value: selectedType, decoration: const InputDecoration(labelText: '类型', border: OutlineInputBorder()), items: const [
          DropdownMenuItem(value: 'bookSource', child: Text('书源')),
          DropdownMenuItem(value: 'rssSource', child: Text('RSS源')),
          DropdownMenuItem(value: 'replaceRule', child: Text('替换规则')),
          DropdownMenuItem(value: 'dictRule', child: Text('字典规则')),
          DropdownMenuItem(value: 'txtTocRule', child: Text('TXT目录规则')),
        ], onChanged: (v) => setState(() => selectedType = v ?? 'bookSource')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')), FilledButton(onPressed: () async {
        if (nameController.text.isNotEmpty && urlController.text.isNotEmpty) {
          await _db.insertRuleSub(RuleSub(name: nameController.text, url: urlController.text, type: selectedType, customOrder: _subs.length));
          Navigator.pop(context);
          _loadSubs();
        }
      }, child: const Text('添加'))],
    )));
  }

  Future<void> _toggleSub(RuleSub sub, bool enabled) async {
    final updated = RuleSub(id: sub.id, name: sub.name, url: sub.url, type: sub.type, enabled: enabled ? 1 : 0, lastUpdateTime: sub.lastUpdateTime, customOrder: sub.customOrder);
    await _db.insertRuleSub(updated);
    _loadSubs();
  }

  void _showSubMenu(RuleSub sub) {
    showModalBottomSheet(context: context, builder: (context) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: const Icon(Icons.refresh), title: const Text('立即更新'), onTap: () { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在更新订阅...'))); }),
      ListTile(leading: const Icon(Icons.delete_outline, color: Colors.red), title: const Text('删除订阅', style: TextStyle(color: Colors.red)), onTap: () async {
        Navigator.pop(context);
        if (sub.id != null) { await _db.deleteRuleSub(sub.id!); _loadSubs(); }
      }),
    ])));
  }
}
