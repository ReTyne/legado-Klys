import 'package:flutter/material.dart';
import 'package:legado_md3/data/model/homepage_module.dart';
import 'package:legado_md3/data/local/app_database.dart';

class HomepageManageScreen extends StatefulWidget {
  const HomepageManageScreen({super.key});
  @override
  State<HomepageManageScreen> createState() => _HomepageManageScreenState();
}

class _HomepageManageScreenState extends State<HomepageManageScreen> {
  final DatabaseService _db = DatabaseService();
  List<HomepageModule> _modules = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadModules();
  }

  Future<void> _loadModules() async {
    setState(() => _isLoading = true);
    final modules = await _db.getHomepageModules();
    setState(() { _modules = modules; _isLoading = false; });
  }

  Future<void> _showAddModuleDialog() async {
    final nameController = TextEditingController();
    HomepageModuleType selectedType = HomepageModuleType.banner;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加模块'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameController, decoration: const InputDecoration(labelText: '模块名称')),
          const SizedBox(height: 16),
          DropdownButtonFormField<HomepageModuleType>(
            value: selectedType,
            decoration: const InputDecoration(labelText: '模块类型'),
            items: HomepageModuleType.values.map((t) => DropdownMenuItem(value: t, child: Text(_getTypeName(t)))).toList(),
            onChanged: (v) => selectedType = v ?? selectedType,
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: () async {
            if (nameController.text.isEmpty) return;
            await _db.insertHomepageModule(HomepageModule(name: nameController.text, type: selectedType, customOrder: _modules.length));
            Navigator.pop(context);
            _loadModules();
          }, child: const Text('添加')),
        ],
      ),
    );
  }

  String _getTypeName(HomepageModuleType type) {
    switch (type) {
      case HomepageModuleType.banner: return '横幅';
      case HomepageModuleType.buttonGroup: return '按钮组';
      case HomepageModuleType.card: return '卡片';
      case HomepageModuleType.grid: return '网格';
      case HomepageModuleType.gridRanking: return '网格排行';
      case HomepageModuleType.ranking: return '排行榜';
      case HomepageModuleType.waterfall: return '瀑布流';
      case HomepageModuleType.custom: return '自定义';
    }
  }

  IconData _getTypeIcon(HomepageModuleType type) {
    switch (type) {
      case HomepageModuleType.banner: return Icons.image;
      case HomepageModuleType.buttonGroup: return Icons.smart_button;
      case HomepageModuleType.card: return Icons.credit_card;
      case HomepageModuleType.grid: return Icons.grid_view;
      case HomepageModuleType.gridRanking: return Icons.grid_on;
      case HomepageModuleType.ranking: return Icons.emoji_events;
      case HomepageModuleType.waterfall: return Icons.view_stream;
      case HomepageModuleType.custom: return Icons.settings;
    }
  }

  /// 配置模块关联的发现书源（首页模块点击后据此打开发现书籍列表）
  Future<void> _configureModule(HomepageModule module) async {
    final sources = await _db.getAllSources(enabled: true);
    final exploreSources = sources.where((s) => (s.exploreUrl ?? '').trim().isNotEmpty).toList();
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('关联书源 · ${module.name}'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('选择该模块在首页展示哪个书源的发现内容', style: TextStyle(fontSize: 12, color: Colors.grey)),
              ),
              if (exploreSources.isEmpty)
                const Padding(padding: EdgeInsets.all(16), child: Text('暂无含发现地址的启用书源'))
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: exploreSources.map((s) => RadioListTile<String>(
                      dense: true,
                      value: s.bookSourceUrl,
                      groupValue: module.sourceUrl,
                      title: Text(s.bookSourceName, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(s.bookSourceUrl, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10)),
                      onChanged: (v) async {
                        module.sourceUrl = v;
                        module.exploreUrl = null; // 留空则首页取该书源第一个发现分类
                        await _db.updateHomepageModule(module);
                        setDialogState(() {});
                        setState(() {});
                      },
                    )).toList(),
                  ),
                ),
            ]),
          ),
          actions: [
            if (module.sourceUrl != null)
              TextButton(onPressed: () async {
                module.sourceUrl = null;
                module.exploreUrl = null;
                await _db.updateHomepageModule(module);
                if (mounted) { Navigator.pop(context); setState(() {}); }
              }, child: const Text('清除关联')),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('首页模块管理'), actions: [IconButton(icon: const Icon(Icons.add), onPressed: _showAddModuleDialog)]),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : _modules.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.dashboard_customize, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16), const Text('暂无模块', style: TextStyle(fontSize: 16)),
              const SizedBox(height: 8), const Text('点击右上角添加首页模块', style: TextStyle(color: Colors.grey)),
            ]))
          : ReorderableListView.builder(
              itemCount: _modules.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex--;
                  final module = _modules.removeAt(oldIndex);
                  _modules.insert(newIndex, module);
                  for (var i = 0; i < _modules.length; i++) { _modules[i].customOrder = i; _db.updateHomepageModule(_modules[i]); }
                });
              },
              itemBuilder: (context, index) {
                final module = _modules[index];
                return Card(key: ValueKey(module.id ?? index), margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: ListTile(
                    leading: Icon(_getTypeIcon(module.type)),
                    title: Text(module.name),
                    subtitle: Text(module.sourceUrl == null
                        ? '${_getTypeName(module.type)} · 未关联书源（点击配置）'
                        : '${_getTypeName(module.type)} · 已关联'),
                    onTap: () => _configureModule(module),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Switch(value: module.enabled, onChanged: (v) { setState(() => module.enabled = v); _db.updateHomepageModule(module); }),
                      IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () async { if (module.id != null) { await _db.deleteHomepageModule(module.id!); _loadModules(); } }),
                    ]),
                  ),
                );
              },
            ),
    );
  }
}
