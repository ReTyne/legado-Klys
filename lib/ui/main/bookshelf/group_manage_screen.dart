import 'package:flutter/material.dart';
import 'package:legado_md3/data/model/book_group.dart';
import 'package:legado_md3/data/local/app_database.dart';

class _GroupItem {
  BookGroup meta;
  int count;
  _GroupItem(this.meta, this.count);
}

class GroupManageScreen extends StatefulWidget {
  const GroupManageScreen({super.key});

  @override
  State<GroupManageScreen> createState() => _GroupManageScreenState();
}

class _GroupManageScreenState extends State<GroupManageScreen> {
  final DatabaseService _db = DatabaseService();
  List<_GroupItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _safeLoad();
  }

  Future<void> _loadGroups() async {
    final meta = await _db.getBookGroups();
    final books = await _db.getAllBooks();
    final counts = <String, int>{};
    for (final b in books) {
      final g = b.group;
      if (g != null && g.isNotEmpty) counts[g] = (counts[g] ?? 0) + 1;
    }
    final byName = {for (final m in meta) m.name: m};
    final names = <String>{...byName.keys, ...counts.keys};
    final items = <_GroupItem>[];
    var autoOrder = meta.length;
    for (final name in names) {
      final m = byName[name] ??
          BookGroup(name: name, order: 1000 + autoOrder, show: 1);
      items.add(_GroupItem(m, counts[name] ?? 0));
      autoOrder++;
    }
    items.sort((a, b) => a.meta.order.compareTo(b.meta.order));
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  // 容错包装：DB 异常时不卡死加载态
  Future<void> _safeLoad() async {
    try {
      await _loadGroups();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _persistOrder() async {
    for (var i = 0; i < _items.length; i++) {
      final m = _items[i].meta;
      await _db.insertBookGroup(
          BookGroup(id: m.id, name: m.name, order: i, show: m.show, cover: m.cover));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('分组管理'),
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: _showAddGroup),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(child: Text('暂无分组，点击右上角添加'))
              : ReorderableListView.builder(
                  itemCount: _items.length,
                  onReorder: (oldIndex, newIndex) async {
                    if (newIndex > oldIndex) newIndex--;
                    setState(() {
                      final item = _items.removeAt(oldIndex);
                      _items.insert(newIndex, item);
                    });
                    await _persistOrder();
                  },
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    final group = item.meta;
                    return Card(
                      key: ValueKey('${group.name}-$index'),
                      child: ListTile(
                        leading: const Icon(Icons.folder_outlined),
                        title: Text(group.name),
                        subtitle: Text('${item.count} 本书${group.show == 0 ? ' · 已隐藏' : ''}'),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                            tooltip: '重命名',
                            icon: const Icon(Icons.drive_file_rename_outline, size: 20),
                            onPressed: () => _showRenameGroup(group),
                          ),
                          Switch(
                            value: group.show == 1,
                            onChanged: (v) => _toggleShow(item, v),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () => _deleteGroup(group),
                          ),
                        ]),
                      ),
                    );
                  },
                ),
    );
  }

  Future<void> _showAddGroup() async {
    final controller = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建分组'),
        content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: '分组名称', border: OutlineInputBorder()),
            autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('创建')),
        ],
      ),
    );
    if (created == true && controller.text.trim().isNotEmpty) {
      final name = controller.text.trim();
      if (_items.any((e) => e.meta.name == name)) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('分组「$name」已存在')));
        }
        return;
      }
      await _db.insertBookGroup(
          BookGroup(name: name, order: _items.length, show: 1));
      await _loadGroups();
    }
  }

  Future<void> _showRenameGroup(BookGroup group) async {
    final controller = TextEditingController(text: group.name);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名分组'),
        content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: '新分组名称', border: OutlineInputBorder()),
            autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('确定')),
        ],
      ),
    );
    final newName = controller.text.trim();
    if (confirmed == true && newName.isNotEmpty && newName != group.name) {
      if (_items.any((e) => e.meta.name == newName)) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('已存在同名分组「$newName」')));
        }
        return;
      }
      await _db.renameBookGroup(group.name, newName);
      await _loadGroups();
    }
  }

  Future<void> _toggleShow(_GroupItem item, bool show) async {
    final m = item.meta;
    final updated = BookGroup(
        id: m.id, name: m.name, order: m.order, show: show ? 1 : 0, cover: m.cover);
    await _db.insertBookGroup(updated);
    await _loadGroups();
  }

  Future<void> _deleteGroup(BookGroup group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除分组'),
        content: Text('确定要删除分组「${group.name}」吗？\n该分组下的书籍不会被删除，将回到「未分组」。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (confirmed == true) {
      await _db.dissolveBookGroup(group.name);
      await _loadGroups();
    }
  }
}
