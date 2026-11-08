import 'package:flutter/material.dart';

import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/homepage_module.dart';
import 'package:legado_md3/ui/main/discover/homepage_module_widgets.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';

/// 首页模块管理（fork 特性：卡片式模块化首页）。
///
/// 模块：增删改 / 启停 / 拖拽排序 / 类型选择，全部走
/// getHomepageModules / insertHomepageModule / updateHomepageModule /
/// deleteHomepageModule；默认发现页的 HomepageFeed 直接消费本表渲染。
/// 模块集（HomepageCustomSet）：新建 / 编辑 / 删除 / 切换，走
/// getHomepageCustomSets / insertHomepageCustomSet / deleteHomepageCustomSet，
/// 当前启用的模块集 id 由 HomepageSetStore 持久化，Feed 按其 moduleIds 过滤排序。
class HomepageModuleScreen extends StatefulWidget {
  const HomepageModuleScreen({super.key});

  @override
  State<HomepageModuleScreen> createState() => _HomepageModuleScreenState();
}

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
    if (_loading) return const Center(child: CircularProgressIndicator());
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
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: _modules.length,
      onReorder: _reorder,
      itemBuilder: (context, i) {
        final m = _modules[i];
        return Card(
          key: ValueKey('homepage_module_${m.id ?? i}'),
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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

/// 模块新增 / 编辑：名称、类型（单选）、可选书源/发现/JSON 配置、启用。
/// config 为 Feed 卡片数据（HomepageModuleData 解析）：
/// `{"title":"...","items":[{"title":"...","subtitle":"...","cover":"...",`
/// `"action":"search|book|explore|url","keyword":"...","sourceUrl":"...",`
/// `"exploreUrl":"...","url":"...","bookUrl":"..."}]}`；留空则 Feed 用
/// 关联书源 + 发现地址拉取真实书籍填充。
class _HomepageModuleEditDialog extends StatefulWidget {
  final HomepageModule? module;
  final int defaultOrder;
  const _HomepageModuleEditDialog({this.module, this.defaultOrder = 0});

  @override
  State<_HomepageModuleEditDialog> createState() =>
      _HomepageModuleEditDialogState();
}

class _HomepageModuleEditDialogState
    extends State<_HomepageModuleEditDialog> {
  late final TextEditingController _name;
  late final TextEditingController _sourceUrl;
  late final TextEditingController _exploreUrl;
  late final TextEditingController _config;
  late HomepageModuleType _type;
  late bool _enabled;

  static const String _sampleConfig = '{\n'
      '  "title": "示例模块",\n'
      '  "items": [\n'
      '    {"title": "搜索", "subtitle": "点击搜索书籍", "action": "search", "keyword": "斗破苍穹"},\n'
      '    {"title": "发现", "subtitle": "打开书源发现", "action": "explore", "sourceUrl": "", "exploreUrl": ""},\n'
      '    {"title": "书籍", "subtitle": "打开书籍详情", "action": "book", "bookName": "示例书名", "bookAuthor": "作者"}\n'
      '  ]\n'
      '}';

  @override
  void initState() {
    super.initState();
    final m = widget.module;
    _name = TextEditingController(text: m?.name ?? '');
    _sourceUrl = TextEditingController(text: m?.sourceUrl ?? '');
    _exploreUrl = TextEditingController(text: m?.exploreUrl ?? '');
    _config = TextEditingController(text: m?.config ?? '');
    _type = m?.type ?? HomepageModuleType.card;
    _enabled = m?.enabled ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _sourceUrl.dispose();
    _exploreUrl.dispose();
    _config.dispose();
    super.dispose();
  }

  Future<void> _pickType() async {
    final v = await showAppRadioDialog<HomepageModuleType>(
      context,
      title: '模块类型',
      groupValue: _type,
      options: [
        for (final t in HomepageModuleType.values)
          AppRadioOption<HomepageModuleType>(t, homepageModuleTypeLabel(t)),
      ],
    );
    if (v != null) setState(() => _type = v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.module == null ? '新增首页模块' : '编辑首页模块'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: '模块名称'),
            ),
            const SizedBox(height: 8),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('模块类型'),
              subtitle: Text(homepageModuleTypeLabel(_type)),
              trailing: const Icon(Icons.arrow_drop_down),
              onTap: _pickType,
            ),
            TextField(
              controller: _sourceUrl,
              decoration:
                  const InputDecoration(labelText: '关联书源 URL（可选）'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _exploreUrl,
              decoration: const InputDecoration(labelText: '发现 URL（可选）'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _config,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: '卡片配置 JSON（可选）',
                helperText: '留空则用关联书源 + 发现地址拉取真实书籍',
                helperMaxLines: 2,
                border: OutlineInputBorder(),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _config.text = _sampleConfig),
                icon: const Icon(Icons.data_object_outlined, size: 16),
                label: const Text('插入示例卡片配置'),
              ),
            ),
            AppSwitchTile(
              title: '启用模块',
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(
              context,
              HomepageModule(
                id: widget.module?.id,
                name: name,
                type: _type,
                sourceUrl: _sourceUrl.text.trim().isEmpty
                    ? null
                    : _sourceUrl.text.trim(),
                exploreUrl: _exploreUrl.text.trim().isEmpty
                    ? null
                    : _exploreUrl.text.trim(),
                config: _config.text.trim().isEmpty
                    ? null
                    : _config.text.trim(),
                customOrder: widget.module?.customOrder ?? widget.defaultOrder,
                enabled: _enabled,
              ),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

/// 模块集编辑草稿。
class _SetDraft {
  _SetDraft(this.name, this.moduleIds);
  final String name;
  final List<int> moduleIds;
}

/// 模块集管理 sheet：列出 / 切换 / 新建 / 编辑 / 删除模块集。
/// DAO 未提供 updateHomepageCustomSet，故「编辑」= 删除旧行 + 插入新行
/// （真实落库），编辑后若该集为当前集则自动把新行重新设为当前集。
class _HomepageSetSheet extends StatefulWidget {
  const _HomepageSetSheet({required this.db, required this.onChanged});

  final DatabaseService db;
  final Future<void> Function() onChanged;

  @override
  State<_HomepageSetSheet> createState() => _HomepageSetSheetState();
}

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

/// 新建 / 编辑模块集：名称 + 勾选纳入的模块（顺序即 Feed 展示顺序）。
class _HomepageSetEditDialog extends StatefulWidget {
  const _HomepageSetEditDialog({this.set, required this.modules});

  final HomepageCustomSet? set;
  final List<HomepageModule> modules;

  @override
  State<_HomepageSetEditDialog> createState() => _HomepageSetEditDialogState();
}

class _HomepageSetEditDialogState extends State<_HomepageSetEditDialog> {
  late final TextEditingController _name;
  late final List<int> _selected;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.set?.name ?? '');
    final initial = HomepageSetStore.parseModuleIds(widget.set?.moduleIds);
    _selected = List<int>.from(initial);
    // 新建时默认纳入全部模块，便于立即看到效果
    if (widget.set == null) {
      for (final m in widget.modules) {
        if (m.id != null && !_selected.contains(m.id)) _selected.add(m.id!);
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.set == null ? '新建模块集' : '编辑模块集'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: '模块集名称'),
            ),
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('勾选纳入的模块（勾选顺序即首页展示顺序）',
                  style: TextStyle(fontSize: 11)),
            ),
            if (widget.modules.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('暂无可加入的模块', style: TextStyle(fontSize: 12)),
              )
            else
              ...widget.modules.map((m) {
                final id = m.id;
                return CheckboxListTile(
                  dense: true,
                  title: Text(m.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(homepageModuleTypeLabel(m.type),
                      style: const TextStyle(fontSize: 11)),
                  value: id != null && _selected.contains(id),
                  onChanged: id == null
                      ? null
                      : (v) => setState(() {
                            if (v == true) {
                              _selected.add(id);
                            } else {
                              _selected.remove(id);
                            }
                          }),
                );
              }),
          ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(context, _SetDraft(name, List<int>.from(_selected)));
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
