import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/db_models.dart';
import 'package:legado_md3/help/source/content_services.dart';

/// 字典面板：两个 Tab 分别管理两套不同语义的「字典规则」。
///
/// 历史问题：两套规则曾经共用一个界面名，但数据源与消费方完全不同，
/// 导致「在词典规则里加的规则阅读页查不到」。现在拆清楚：
///
///  - 词语替换：`rule|||replacement` 存 SharedPreferences `dict_rules`，
///    由 [ContentDictService] 应用到正文（把错别字/自定义写法批量替换）。
///  - 词典规则：存数据库 `dict_rules` 表，由阅读页「划词 → 查词」调用，
///    `url` 中 `{word}` 为被查询词占位符。
class DictRuleScreen extends StatefulWidget {
  const DictRuleScreen({super.key});

  @override
  State<DictRuleScreen> createState() => _DictRuleScreenState();
}

class _DictRuleScreenState extends State<DictRuleScreen> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('字典规则'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '词语替换'),
              Tab(text: '词典查询'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _ReplaceTab(),
            _DictSourceTab(),
          ],
        ),
      ),
    );
  }
}

/* ===================== Tab 1：正文词语替换 ===================== */

class _ReplaceTab extends StatefulWidget {
  const _ReplaceTab();

  @override
  State<_ReplaceTab> createState() => _ReplaceTabState();
}

class _ReplaceTabState extends State<_ReplaceTab> {
  final _ruleCtl = TextEditingController();
  final _replacementCtl = TextEditingController();
  List<Map<String, String>> _rules = [];
  bool _enabled = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rules = await ContentDictService.loadRules();
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _rules = rules;
      _enabled = p.getBool('dict_rule_enabled') ?? true;
    });
  }

  Future<void> _save() async {
    await ContentDictService.saveRules(_enabled, _rules);
    await ContentDictService.reload();
    await _load();
  }

  Future<void> _importNetwork() async {
    final ctl = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('网络导入替换规则'),
        content: TextField(controller: ctl, decoration: const InputDecoration(hintText: '规则 URL（JSON 数组）')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, ctl.text.trim()), child: const Text('导入')),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;
    try {
      final res = await Dio(BaseOptions(responseType: ResponseType.plain)).get<String>(url);
      final data = jsonDecode(res.data ?? '[]');
      final list = data is List ? data : [data];
      var added = 0;
      for (final m in list) {
        if (m is! Map) continue;
        final rule = (m['rule'] ?? m['showRule'] ?? m['pattern'] ?? '').toString();
        if (rule.isEmpty) continue;
        _rules.add({
          'rule': rule,
          'replacement': (m['replacement'] ?? m['name'] ?? m['replace'] ?? '').toString(),
        });
        added++;
      }
      await _save();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入 $added 条')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SwitchListTile(
          title: const Text('启用词语替换'),
          subtitle: const Text('替换会作用在阅读正文上'),
          value: _enabled,
          onChanged: (v) async {
            setState(() => _enabled = v);
            await _save();
          },
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: _ruleCtl,
                decoration: const InputDecoration(labelText: '查找内容(正则)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _replacementCtl,
                decoration: const InputDecoration(labelText: '替换为', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('添加规则'),
                  onPressed: () async {
                    if (_ruleCtl.text.trim().isEmpty) return;
                    setState(() {
                      _rules.add({
                        'rule': _ruleCtl.text.trim(),
                        'replacement': _replacementCtl.text.trim(),
                      });
                      _ruleCtl.clear();
                      _replacementCtl.clear();
                    });
                    await _save();
                  },
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _importNetwork,
                  icon: const Icon(Icons.cloud_download_outlined, size: 18),
                  label: const Text('网络导入'),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _rules.isEmpty
              ? const Center(child: Text('暂无替换规则'))
              : ListView.builder(
                  itemCount: _rules.length,
                  itemBuilder: (context, index) {
                    final r = _rules[index];
                    return ListTile(
                      title: Text(r['rule']!, style: const TextStyle(fontFamily: 'monospace')),
                      subtitle: Text('→ ${r['replacement']}', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () async {
                          setState(() => _rules.removeAt(index));
                          await _save();
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/* ===================== Tab 2：词典查询规则 ===================== */

class _DictSourceTab extends StatefulWidget {
  const _DictSourceTab();

  @override
  State<_DictSourceTab> createState() => _DictSourceTabState();
}

class _DictSourceTabState extends State<_DictSourceTab> {
  final _db = DatabaseService();
  List<DictRule> _rules = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _db.getDictRules();
    if (!mounted) return;
    setState(() {
      _rules = list;
      _loading = false;
    });
  }

  Future<void> _save(DictRule rule) async {
    await _db.updateDictRule(rule);
    await _load();
  }

  Future<void> _delete(DictRule rule) async {
    if (rule.id == null) return;
    await _db.deleteDictRule(rule.id!);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已删除')));
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    final item = _rules.removeAt(oldIndex);
    _rules.insert(newIndex, item);
    setState(() {});
    for (var i = 0; i < _rules.length; i++) {
      if (_rules[i].order != i) {
        await _db.updateDictRule(_rules[i].copyWith(order: i));
      }
    }
  }

  Future<void> _importNetwork() async {
    final ctl = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('网络导入词典规则'),
        content: TextField(
          controller: ctl,
          decoration: const InputDecoration(hintText: '规则 URL（返回 JSON 数组）'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, ctl.text.trim()), child: const Text('导入')),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;
    try {
      final res = await Dio(BaseOptions(responseType: ResponseType.plain)).get<String>(url);
      final data = jsonDecode(res.data ?? '[]');
      final list = data is List ? data : [data];
      var added = 0;
      for (final m in list) {
        if (m is! Map) continue;
        final name = (m['name'] ?? m['title'] ?? '').toString();
        final dictUrl = (m['url'] ?? m['link'] ?? '').toString();
        if (name.isEmpty || dictUrl.isEmpty) continue;
        added++;
        await _db.insertDictRule(DictRule(
          name: name,
          summary: (m['summary'] ?? m['desc'] ?? '').toString(),
          url: dictUrl,
          rule: (m['rule'] ?? m['js'] ?? '').toString(),
          order: _rules.length + added,
        ));
      }
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入 $added 条')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('失败: $e')));
    }
  }

  void _editRule([DictRule? rule]) {
    showDialog<void>(
      context: context,
      builder: (_) => _DictRuleEditDialog(
        rule: rule,
        onSave: (r) async {
          await _save(rule == null ? r.copyWith(order: _rules.length) : r);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.info_outline, size: 16, color: Colors.grey),
              const SizedBox(width: 6),
              const Expanded(
                child: Text('阅读页选中文字后点「查词」即可调用', style: TextStyle(fontSize: 12, color: Colors.grey)),
              ),
              TextButton.icon(
                onPressed: _importNetwork,
                icon: const Icon(Icons.cloud_download_outlined, size: 18),
                label: const Text('网络导入'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _rules.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.menu_book_outlined, size: 48, color: Colors.grey),
                          const SizedBox(height: 12),
                          const Text('暂无词典规则'),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _editRule,
                            icon: const Icon(Icons.add),
                            label: const Text('新增规则'),
                          ),
                        ],
                      ),
                    )
                  : ReorderableListView.builder(
                      onReorder: _reorder,
                      itemCount: _rules.length,
                      itemBuilder: (context, index) {
                        final r = _rules[index];
                        return ListTile(
                          key: ValueKey('dict_${r.id ?? index}'),
                          leading: Icon(
                            r.enabled == 1 ? Icons.check_circle : Icons.radio_button_unchecked,
                            color: r.enabled == 1 ? Colors.green : Colors.grey,
                          ),
                          title: Text(r.name),
                          subtitle: Text(
                            r.url.isEmpty ? r.summary : r.url,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Switch(
                                value: r.enabled == 1,
                                onChanged: (v) => _save(r.copyWith(enabled: v ? 1 : 0)),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                onPressed: () => _delete(r),
                              ),
                              const ReorderableDragStartListener(index: 0, child: Icon(Icons.drag_handle)),
                            ],
                          ),
                          onTap: () => _editRule(r),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

/// 新增 / 编辑词典规则对话框
class _DictRuleEditDialog extends StatefulWidget {
  final DictRule? rule;
  final ValueChanged<DictRule> onSave;
  const _DictRuleEditDialog({this.rule, required this.onSave});

  @override
  State<_DictRuleEditDialog> createState() => _DictRuleEditDialogState();
}

class _DictRuleEditDialogState extends State<_DictRuleEditDialog> {
  late final TextEditingController _name;
  late final TextEditingController _url;
  late final TextEditingController _summary;
  late final TextEditingController _rule;

  @override
  void initState() {
    super.initState();
    final r = widget.rule;
    _name = TextEditingController(text: r?.name ?? '');
    _url = TextEditingController(text: r?.url ?? '');
    _summary = TextEditingController(text: r?.summary ?? '');
    _rule = TextEditingController(text: r?.rule ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _summary.dispose();
    _rule.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.rule == null ? '新增词典规则' : '编辑词典规则'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: '名称', hintText: '例如：汉语词典'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _url,
              decoration: const InputDecoration(
                labelText: '查询地址',
                hintText: 'https://www.zdic.net/hans/?q={word}',
                helperText: '用 {word} 作为被查询词占位符',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _summary,
              decoration: const InputDecoration(labelText: '备注（可选）'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _rule,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'JS 规则（可选）',
                helperText: '对返回页面做二次处理，高级用法',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            final url = _url.text.trim();
            if (name.isEmpty || url.isEmpty) return;
            widget.onSave(DictRule(
              id: widget.rule?.id,
              name: name,
              url: url,
              summary: _summary.text.trim(),
              rule: _rule.text.trim(),
              enabled: widget.rule?.enabled ?? 1,
              order: widget.rule?.order ?? 0,
            ));
            Navigator.pop(context);
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
