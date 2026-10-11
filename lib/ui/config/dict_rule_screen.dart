import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DictRuleScreen extends StatefulWidget {
  const DictRuleScreen({super.key});

  @override
  State<DictRuleScreen> createState() => _DictRuleScreenState();
}

class _DictRuleScreenState extends State<DictRuleScreen> {
  final TextEditingController _ruleController = TextEditingController();
  final TextEditingController _replacementController = TextEditingController();
  List<Map<String, String>> _rules = [];
  bool _enabled = true;

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  Future<void> _loadRules() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool('dict_rule_enabled') ?? true;
    final rulesStr = prefs.getStringList('dict_rules') ?? [];
    setState(() {
      _rules = rulesStr.map((s) {
        final parts = s.split('|||');
        return {'rule': parts[0], 'replacement': parts.length > 1 ? parts[1] : ''};
      }).toList();
    });
  }

  Future<void> _saveRules() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dict_rule_enabled', _enabled);
    await prefs.setStringList('dict_rules', _rules.map((r) => '${r['rule']}|||${r['replacement']}').toList());
  }

  Future<void> _importNetwork() async {
    final ctl = TextEditingController();
    final url = await showDialog<String>(context: context, builder: (c) => AlertDialog(
      title: const Text('网络导入字典规则'),
      content: TextField(controller: ctl, decoration: const InputDecoration(hintText: '规则URL')),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(c, ctl.text), child: const Text('导入'))],
    ));
    if (url == null || url.isEmpty) return;
    try {
      final res = await Dio(BaseOptions(responseType: ResponseType.plain)).get<String>(url);
      final data = jsonDecode(res.data ?? '[]');
      final list = data is List ? data : [data];
      for (final m in list) {
        if (m is Map) {
          final rule = (m['rule'] ?? m['showRule'] ?? m['url'] ?? '').toString();
          final rep = (m['replacement'] ?? m['name'] ?? '').toString();
          if (rule.isNotEmpty) _rules.add({'rule': rule, 'replacement': rep});
        }
      }
      _saveRules();
      setState(() {});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入 ${list.length} 条')));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('失败: $e'))); }
  }

  void _addRule() {
    if (_ruleController.text.trim().isEmpty) return;
    setState(() {
      _rules.add({'rule': _ruleController.text.trim(), 'replacement': _replacementController.text.trim()});
      _ruleController.clear();
      _replacementController.clear();
    });
    _saveRules();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('字典规则'), actions: [
        PopupMenuButton<String>(onSelected: (v) => v == 'net' ? _importNetwork() : null, itemBuilder: (_) => const [
          PopupMenuItem(value: 'net', child: Text('网络导入')),
        ]),
      ]),
      body: Column(
        children: [
          SwitchListTile(
            title: const Text('启用字典规则'),
            value: _enabled,
            onChanged: (v) => setState(() { _enabled = v; _saveRules(); }),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              TextField(controller: _ruleController, decoration: const InputDecoration(labelText: '查找内容(正则)', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(controller: _replacementController, decoration: const InputDecoration(labelText: '替换为', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity, child: FilledButton(onPressed: _addRule, child: const Text('添加规则'))),
            ]),
          ),
          const Divider(),
          Expanded(
            child: _rules.isEmpty
                ? const Center(child: Text('暂无字典规则'))
                : ListView.builder(
                    itemCount: _rules.length,
                    itemBuilder: (context, index) {
                      final rule = _rules[index];
                      return ListTile(
                        title: Text(rule['rule']!, style: const TextStyle(fontFamily: 'monospace')),
                        subtitle: Text('→ ${rule['replacement']}', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                        trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => setState(() { _rules.removeAt(index); _saveRules(); })),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
