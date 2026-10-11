import 'package:flutter/material.dart';
import 'package:legado_md3/data/model/txt_toc_rule.dart';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:legado_md3/data/local/app_database.dart';

class TxtTocRuleScreen extends StatefulWidget {
  const TxtTocRuleScreen({super.key});

  @override
  State<TxtTocRuleScreen> createState() => _TxtTocRuleScreenState();
}

class _TxtTocRuleScreenState extends State<TxtTocRuleScreen> {
  final DatabaseService _db = DatabaseService();
  List<TxtTocRule> _rules = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  Future<void> _onMenu(String v) async {
    if (v == 'import') _importNetwork();
    else if (v == 'local') _importLocal();
    else if (v == 'export') _export();
  }

  Future<void> _importNetwork() async {
    final ctl = TextEditingController();
    final url = await showDialog<String>(context: context, builder: (c) => AlertDialog(
      title: const Text('网络导入TXT目录规则'),
      content: TextField(controller: ctl, decoration: const InputDecoration(hintText: '规则URL')),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(c, ctl.text), child: const Text('导入'))],
    ));
    if (url == null || url.isEmpty) return;
    try {
      final res = await Dio(BaseOptions(responseType: ResponseType.plain)).get<String>(url);
      final n = await _parseAndSave(res.data ?? '');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入 $n 条')));
      _loadRules();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入失败: $e')));
    }
  }

  Future<void> _importLocal() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json', 'txt']);
    if (r == null) return;
    final text = await File(r.files.first.path!).readAsString();
    final n = await _parseAndSave(text);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入 $n 条')));
    _loadRules();
  }

  Future<int> _parseAndSave(String raw) async {
    final data = jsonDecode(raw);
    final list = data is List ? data : [data];
    int n = 0;
    for (final m in list) {
      if (m is Map) {
        try { await _db.insertTxtTocRule(TxtTocRule.fromJson(Map<String, dynamic>.from(m))); n++; } catch (_) {}
      }
    }
    return n;
  }

  Future<void> _export() async {
    final all = await _db.getTxtTocRules();
    final list = all.isEmpty ? _rules : all;
    final file = File('${Directory.systemTemp.path}/txt_toc_rules.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(list.map((e) => e.toJson()).toList()));
    await Share.shareXFiles([XFile(file.path)], text: 'TXT目录规则导出');
  }

  Future<void> _loadRules() async {
    final builtin = [
      TxtTocRule(id: 1, name: '默认规则', chapterRule: r'^第[0-9零一二三四五六七八九十百千万]+[章节回卷集部篇].*', enable: true),
      TxtTocRule(id: 2, name: '简单章节', chapterRule: r'^第\d+章.*', enable: false),
      TxtTocRule(id: 3, name: '中文数字', chapterRule: r'^第[零一二三四五六七八九十百千万]+章.*', enable: false),
    ];
    final dbRules = await _db.getTxtTocRules();
    setState(() {
      _rules = [...dbRules, ...builtin.where((b) => dbRules.every((d) => d.name != b.name))];
      _isLoading = false;
    });
  }

  void _showEditDialog({TxtTocRule? rule}) {
    final nameController = TextEditingController(text: rule?.name ?? '');
    final ruleController = TextEditingController(text: rule?.chapterRule ?? '');
    final volumeController = TextEditingController(text: rule?.volumeRule ?? '');
    final exampleController = TextEditingController(text: rule?.example ?? '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(rule == null ? '添加规则' : '编辑规则'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameController, decoration: const InputDecoration(labelText: '规则名称', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: ruleController, maxLines: 3, decoration: const InputDecoration(labelText: '章节规则(正则)', border: OutlineInputBorder(), hintText: '例如: ^第\\d+章.*')),
          const SizedBox(height: 12),
          TextField(controller: volumeController, maxLines: 2, decoration: const InputDecoration(labelText: '卷规则(正则)', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: exampleController, maxLines: 2, decoration: const InputDecoration(labelText: '示例', border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: () {
            setState(() {
              if (rule == null) {
                _rules.add(TxtTocRule(id: DateTime.now().millisecondsSinceEpoch, name: nameController.text, chapterRule: ruleController.text, volumeRule: volumeController.text, example: exampleController.text, enable: true));
              } else {
                final index = _rules.indexWhere((r) => r.id == rule.id);
                if (index >= 0) _rules[index] = TxtTocRule(id: rule.id, name: nameController.text, chapterRule: ruleController.text, volumeRule: volumeController.text, example: exampleController.text, enable: rule.enable);
              }
            });
            Navigator.pop(context);
          }, child: const Text('保存')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('TXT目录规则'), actions: [
        IconButton(icon: const Icon(Icons.add), onPressed: () => _showEditDialog()),
        PopupMenuButton<String>(onSelected: _onMenu, itemBuilder: (_) => const [
          PopupMenuItem(value: 'import', child: Text('网络导入')),
          PopupMenuItem(value: 'local', child: Text('本地导入')),
          PopupMenuItem(value: 'export', child: Text('导出')),
        ]),
      ]),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _rules.isEmpty
              ? const Center(child: Text('暂无规则'))
              : ListView.builder(
                  itemCount: _rules.length,
                  itemBuilder: (context, index) {
                    final rule = _rules[index];
                    return ListTile(
                      title: Text(rule.name),
                      subtitle: Text(rule.chapterRule, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                      trailing: Switch(
                        value: rule.enable,
                        onChanged: (v) => setState(() => _rules[index] = TxtTocRule(id: rule.id, name: rule.name, chapterRule: rule.chapterRule, enable: v)),
                      ),
                      onTap: () => _showEditDialog(rule: rule),
                      onLongPress: () => showDialog(
                        context: context,
                        builder: (context) => AlertDialog(title: const Text('删除规则'), content: Text('确定删除"${rule.name}"吗？'), actions: [
                          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
                          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () { setState(() => _rules.removeAt(index)); Navigator.pop(context); }, child: const Text('删除')),
                        ]),
                      ),
                    );
                  },
                ),
    );
  }
}
