/// 由 homepage_module_screen.dart 按「一类一文件」拆出的 _HomepageSetSheetState。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../homepage_module_screen.dart';


class _HomepageSetSheetState extends State<_HomepageSetSheet> {
  List<HomepageCustomSet> _sets = [];
  List<HomepageModule> _modules = [];
  int? _activeId;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final sets = await widget.db.getHomepageCustomSets();
    final modules = await widget.db.getHomepageModules();
    final id = await HomepageSetStore.loadActiveSetId();
    if (mounted) {
      setState(() {
        _sets = sets;
        _modules = modules;
        _activeId = id;
      });
    }
    await widget.onChanged();
  }

  Future<void> _setActive(int? id) async {
    await HomepageSetStore.saveActiveSetId(id);
    await _reload();
  }

  Future<void> _edit([HomepageCustomSet? set]) async {
    final draft = await showDialog<_SetDraft>(
      context: context,
      builder: (_) => _HomepageSetEditDialog(set: set, modules: _modules),
    );
    if (draft == null) return;
    final wasActive = set?.id != null && set!.id == _activeId;
    if (set?.id != null) {
      await widget.db.deleteHomepageCustomSet(set!.id!);
    }
    await widget.db.insertHomepageCustomSet(HomepageCustomSet(
      name: draft.name,
      moduleIds: HomepageSetStore.encodeModuleIds(draft.moduleIds),
      customOrder: set?.customOrder ?? _sets.length,
    ));
    if (wasActive) {
      final sets = await widget.db.getHomepageCustomSets();
      final match = sets.where((s) => s.name == draft.name).toList();
      await HomepageSetStore.saveActiveSetId(
          match.isNotEmpty ? match.last.id : null);
    }
    await _reload();
  }

  Future<void> _delete(HomepageCustomSet set) async {
    if (set.id == null) return;
    final ok = await showAppConfirmDialog(
      context,
      title: '删除模块集',
      content: '确定删除「${set.name}」吗？模块本身不会被删除。',
      confirmText: '删除',
      danger: true,
    );
    if (!ok) return;
    await widget.db.deleteHomepageCustomSet(set.id!);
    if (set.id == _activeId) {
      await HomepageSetStore.saveActiveSetId(null);
    }
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(children: [
                const Expanded(
                  child: Text('模块集',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  tooltip: '新建模块集',
                  icon: const Icon(Icons.add),
                  onPressed: () => _edit(),
                ),
              ]),
            ),
            RadioListTile<int?>(
              title: const Text('全部模块（不使用模块集）'),
              subtitle: const Text('按模块自身排序展示所有启用模块',
                  style: TextStyle(fontSize: 11)),
              value: null,
              groupValue: _activeId,
              onChanged: (_) => _setActive(null),
            ),
            const Divider(height: 1),
            for (final s in _sets)
              ListTile(
                leading: Radio<int?>(
                  value: s.id,
                  groupValue: _activeId,
                  onChanged: (_) => _setActive(s.id),
                ),
                title: Text(s.name),
                subtitle: Text(
                    '${HomepageSetStore.parseModuleIds(s.moduleIds).length} 个模块',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    tooltip: '编辑',
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    onPressed: () => _edit(s),
                  ),
                  IconButton(
                    tooltip: '删除',
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () => _delete(s),
                  ),
                ]),
                onTap: () => _setActive(s.id),
              ),
            if (_sets.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: AppEmptyState(
                  icon: Icons.layers_clear_outlined,
                  title: '暂无模块集',
                  message: '点击右上角新建，勾选要纳入首页 Feed 的模块',
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
