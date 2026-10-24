import 'package:flutter/material.dart';

import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/db_models.dart';

/// 键盘助手配置页：管理规则输入时快速插入的片段（名称 + 触发词/插入文本）。
///
/// 数据落 keyboard_assists 表：get/insert 用 DatabaseService 现有 DAO，
/// update/delete 经公开 database getter 直接执行 SQL。
/// 书源编辑页的规则输入工具条复用本表数据（enabled 且 rule 非空的条目）。
class KeyboardAssistScreen extends StatefulWidget {
  const KeyboardAssistScreen({super.key});

  @override
  State<KeyboardAssistScreen> createState() => _KeyboardAssistScreenState();
}

class _KeyboardAssistScreenState extends State<KeyboardAssistScreen> {
  final DatabaseService _db = DatabaseService();
  List<KeyboardAssist> _assists = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    _assists = await _db.getKeyboardAssists();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _toggle(KeyboardAssist a, bool enabled) async {
    a.enabled = enabled ? 1 : 0;
    await _update(a);
    if (mounted) setState(() {});
  }

  Future<void> _update(KeyboardAssist a) async {
    if (a.id == null) return;
    final db = await _db.database;
    await db.update(
      'keyboard_assists',
      {'name': a.name, 'rule': a.rule, 'enabled': a.enabled, 'order': a.order},
      where: 'id = ?',
      whereArgs: [a.id],
    );
  }

  Future<void> _delete(KeyboardAssist a) async {
    if (a.id == null) return;
    final db = await _db.database;
    await db.delete('keyboard_assists', where: 'id = ?', whereArgs: [a.id]);
    await _load();
  }

  void _showEditDialog({KeyboardAssist? assist}) {
    final nameController = TextEditingController(text: assist?.name ?? '');
    final ruleController = TextEditingController(text: assist?.rule ?? '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(assist == null ? '新建键盘助手' : '编辑键盘助手'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: '名称'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ruleController,
              decoration: const InputDecoration(labelText: '触发词 / 插入文本'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final name = nameController.text.trim();
              final rule = ruleController.text;
              if (name.isEmpty || rule.isEmpty) return;
              if (assist == null) {
                await _db.insertKeyboardAssist(
                    KeyboardAssist(name: name, rule: rule));
              } else {
                assist.name = name;
                assist.rule = rule;
                await _update(assist);
              }
              if (context.mounted) Navigator.pop(context);
              await _load();
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirm(KeyboardAssist a) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除键盘助手'),
        content: Text('确定要删除"${a.name}"吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () {
              Navigator.pop(context);
              _delete(a);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('键盘助手 (${_assists.length})')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _assists.isEmpty
              ? _buildEmptyState()
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _assists.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final a = _assists[index];
                    return Card(
                      child: ListTile(
                        title: Text(a.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(a.rule,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, fontFamily: 'monospace')),
                        trailing: Switch(
                          value: a.enabled == 1,
                          onChanged: (v) => _toggle(a, v),
                        ),
                        onTap: () => _showEditDialog(assist: a),
                        onLongPress: () => _showDeleteConfirm(a),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showEditDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.keyboard_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text('暂无键盘助手',
              style: TextStyle(fontSize: 18, color: Colors.grey[600])),
          const SizedBox(height: 8),
          Text('点击右下角添加规则',
              style: TextStyle(color: Colors.grey[500])),
        ],
      ),
    );
  }
}
