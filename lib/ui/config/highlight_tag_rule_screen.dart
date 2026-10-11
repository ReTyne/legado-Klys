import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HighlightTagRuleScreen extends StatefulWidget {
  const HighlightTagRuleScreen({super.key});

  @override
  State<HighlightTagRuleScreen> createState() => _HighlightTagRuleScreenState();
}

class _HighlightTagRuleScreenState extends State<HighlightTagRuleScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _ruleController = TextEditingController();
  Color _selectedColor = Colors.yellow;
  List<Map<String, dynamic>> _rules = [];

  static const List<Color> _colors = [Colors.yellow, Colors.green, Colors.blue, Colors.pink, Colors.orange, Colors.purple, Colors.teal, Colors.red];

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  Future<void> _loadRules() async {
    final prefs = await SharedPreferences.getInstance();
    final rulesStr = prefs.getStringList('highlight_rules') ?? [];
    setState(() {
      _rules = rulesStr.map((s) {
        final parts = s.split('|||');
        return {
          'name': parts[0],
          'rule': parts.length > 1 ? parts[1] : '',
          'color': int.parse(parts.length > 2 ? parts[2] : Colors.yellow.value.toString()),
        };
      }).toList();
    });
  }

  Future<void> _saveRules() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('highlight_rules', _rules.map((r) => '${r['name']}|||${r['rule']}|||${r['color']}').toList());
  }

  void _addRule() {
    if (_nameController.text.trim().isEmpty || _ruleController.text.trim().isEmpty) return;
    setState(() {
      _rules.add({'name': _nameController.text.trim(), 'rule': _ruleController.text.trim(), 'color': _selectedColor.value});
      _nameController.clear();
      _ruleController.clear();
    });
    _saveRules();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('高亮标签规则')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              TextField(controller: _nameController, decoration: const InputDecoration(labelText: '标签名称', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(controller: _ruleController, decoration: const InputDecoration(labelText: '匹配规则(正则)', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              SizedBox(height: 40, child: ListView(scrollDirection: Axis.horizontal, children: _colors.map((c) => GestureDetector(onTap: () => setState(() => _selectedColor = c), child: Container(width: 32, height: 32, margin: const EdgeInsets.symmetric(horizontal: 4), decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: _selectedColor == c ? Border.all(color: Colors.black, width: 2) : null)))).toList())),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity, child: FilledButton(onPressed: _addRule, child: const Text('添加规则'))),
            ]),
          ),
          const Divider(),
          Expanded(
            child: _rules.isEmpty
                ? const Center(child: Text('暂无高亮规则'))
                : ListView.builder(
                    itemCount: _rules.length,
                    itemBuilder: (context, index) {
                      final rule = _rules[index];
                      return ListTile(
                        leading: Container(width: 16, height: 16, color: Color(rule['color'])),
                        title: Text(rule['name']),
                        subtitle: Text(rule['rule'], style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
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
