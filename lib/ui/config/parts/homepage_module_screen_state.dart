/// 由 homepage_module_screen.dart 按「一类一文件」拆出的 _HomepageModuleScreenState。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../homepage_module_screen.dart';


class _HomepageModuleScreenState extends State<HomepageModuleScreen> {
  final DatabaseService _db = DatabaseService();
  List<HomepageModule> _modules = [];
  List<HomepageCustomSet> _sets = [];
  int? _activeSetId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final modules = await _db.getHomepageModules();
    final sets = await _db.getHomepageCustomSets();
    final activeId = await HomepageSetStore.loadActiveSetId();
    if (!mounted) return;
    setState(() {
      _modules = modules;
      _sets = sets;
      _activeSetId = activeId;
      _loading = false;
    });
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    final item = _modules.removeAt(oldIndex);
    _modules.insert(newIndex, item);
    setState(() {});
    for (var i = 0; i < _modules.length; i++) {
      _modules[i].customOrder = i;
      await _db.updateHomepageModule(_modules[i]);
    }
  }

  Future<void> _edit([HomepageModule? module]) async {
    final result = await showDialog<HomepageModule>(
      context: context,
      builder: (_) => _HomepageModuleEditDialog(
        module: module,
        defaultOrder: _modules.length,
      ),
    );
    if (result == null) return;
    if (result.id == null) {
      await _db.insertHomepageModule(result);
    } else {
      await _db.updateHomepageModule(result);
    }
    await _load();
  }

  Future<void> _toggle(HomepageModule m, bool v) async {
    m.enabled = v;
    await _db.updateHomepageModule(m);
    await _load();
  }

  Future<void> _delete(HomepageModule m) async {
    if (m.id == null) return;
    final ok = await showAppConfirmDialog(
      context,
      title: '删除模块',
      content: '确定删除「${m.name}」吗？',
      confirmText: '删除',
      danger: true,
    );
    if (!ok) return;
    await _db.deleteHomepageModule(m.id!);
    await _load();
  }

  Future<void> _showSetManager() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _HomepageSetSheet(
        db: _db,
        onChanged: _load,
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    String activeLabel = '全部模块';
    for (final s in _sets) {
      if (s.id != null && s.id == _activeSetId) {
        activeLabel = s.name;
        break;
      }
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('首页模块'),
        actions: [
          IconButton(
            tooltip: '模块集管理',
            icon: const Icon(Icons.layers_outlined),
            onPressed: _showSetManager,
          ),
          IconButton(
            tooltip: '新增模块',
            icon: const Icon(Icons.add),
            onPressed: () => _edit(),
          ),
        ],
      ),
      body: Column(
        children: [
          ListTile(
            dense: true,
            leading: Icon(Icons.layers_outlined, color: cs.primary),
            title: Text('当前模块集：$activeLabel'),
            subtitle: const Text('模块集决定首页 Feed 展示哪些模块及顺序',
                style: TextStyle(fontSize: 11)),
            trailing: TextButton(
              onPressed: _showSetManager,
              child: const Text('切换/管理'),
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildModuleList(context)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: '新增模块',
        onPressed: () => _edit(),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildModuleList(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_loading) return const AppLoadingIndicator();
    if (_modules.isEmpty) {
      return AppEmptyState(
        icon: Icons.dashboard_customize_outlined,
        title: '暂无首页模块',
        message: '新增模块后可启停、拖拽排序并选择类型；默认发现页会实时渲染这些模块',
        action: FilledButton.icon(
          onPressed: () => _edit(),
          icon: const Icon(Icons.add),
          label: const Text('新增模块'),
        ),
      );
    }
    return ReorderableListView.builder(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      itemCount: _modules.length,
      onReorder: _reorder,
      itemBuilder: (context, i) {
        final m = _modules[i];
        return Card(
          key: ValueKey('homepage_module_${m.id ?? i}'),
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.m, vertical: AppSpacing.xs),
          child: ListTile(
            leading: Icon(
              m.enabled ? Icons.widgets : Icons.widgets_outlined,
              color: m.enabled ? cs.primary : cs.onSurfaceVariant,
            ),
            title: Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
                '${homepageModuleTypeLabel(m.type)}${m.enabled ? '' : ' · 已停用'}',
                style: const TextStyle(fontSize: 12)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: m.enabled,
                  onChanged: (v) => _toggle(m, v),
                ),
                IconButton(
                  tooltip: '编辑',
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: () => _edit(m),
                ),
                IconButton(
                  tooltip: '删除',
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () => _delete(m),
                ),
                ReorderableDragStartListener(
                  index: i,
                  child: const Icon(Icons.drag_handle),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
