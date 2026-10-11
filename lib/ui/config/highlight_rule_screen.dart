import 'package:flutter/material.dart';
import 'package:legado_md3/data/model/highlight_rule.dart';
import 'package:legado_md3/data/local/app_database.dart';

class HighlightRuleScreen extends StatefulWidget {
  const HighlightRuleScreen({super.key});

  @override
  State<HighlightRuleScreen> createState() => _HighlightRuleScreenState();
}

class _HighlightRuleScreenState extends State<HighlightRuleScreen> {
  final DatabaseService _db = DatabaseService();
  List<HighlightRule> _rules = [];
  bool _loading = true;

  final List<int> _colors = [0xFFFF0000, 0xFFFF9800, 0xFFFFEB3B, 0xFF4CAF50, 0xFF2196F3, 0xFF9C27B0, 0xFF795548, 0xFF607D8B];

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  Future<void> _loadRules() async {
    final rules = await _db.getHighlightRules();
    setState(() {
      _rules = rules;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('高亮规则'), actions: [IconButton(icon: const Icon(Icons.add), onPressed: _showAddRule)]),
      body: _loading ? const Center(child: CircularProgressIndicator()) : _rules.isEmpty ? const Center(child: Text('暂无高亮规则')) : ListView.builder(
        itemCount: _rules.length,
        itemBuilder: (context, index) {
          final rule = _rules[index];
          return Card(child: ListTile(
            leading: Container(width: 24, height: 24, decoration: BoxDecoration(color: Color(rule.color ?? 0xFFFF0000), borderRadius: BorderRadius.circular(4))),
            title: Text(rule.name),
            subtitle: Text(rule.pattern, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Switch(value: rule.enabled == 1, onChanged: (v) => _toggleRule(rule, v)),
            onLongPress: () => _deleteRule(rule),
          ));
        },
      ),
    );
  }

  void _showAddRule() {
    final nameController = TextEditingController();
    final patternController = TextEditingController();
    int selectedColor = 0xFFFF0000;
    showDialog(context: context, builder: (context) => StatefulBuilder(builder: (context, setState) => AlertDialog(
      title: const Text('添加高亮规则'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nameController, decoration: const InputDecoration(labelText: '名称', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: patternController, decoration: const InputDecoration(labelText: '正则表达式', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        Wrap(spacing: 8, children: _colors.map((c) => GestureDetector(onTap: () => setState(() => selectedColor = c), child: Container(width: 32, height: 32, decoration: BoxDecoration(color: Color(c), shape: BoxShape.circle, border: selectedColor == c ? Border.all(color: Colors.black, width: 2) : null)))).toList()),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')), FilledButton(onPressed: () async {
        if (nameController.text.isNotEmpty && patternController.text.isNotEmpty) {
          await _db.insertHighlightRule(HighlightRule(name: nameController.text, pattern: patternController.text, color: selectedColor, order: _rules.length));
          Navigator.pop(context);
          _loadRules();
        }
      }, child: const Text('添加'))],
    )));
  }

  Future<void> _toggleRule(HighlightRule rule, bool enabled) async {
    final updated = HighlightRule(id: rule.id, name: rule.name, pattern: rule.pattern, color: rule.color, enabled: enabled ? 1 : 0, order: rule.order);
    await _db.insertHighlightRule(updated);
    _loadRules();
  }

  Future<void> _deleteRule(HighlightRule rule) async {
    if (rule.id != null) {
      await _db.deleteHighlightRule(rule.id!);
      _loadRules();
    }
  }
}
