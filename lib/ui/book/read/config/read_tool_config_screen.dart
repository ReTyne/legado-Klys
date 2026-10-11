import 'package:flutter/material.dart';
import 'package:legado_md3/help/config/read_menu_config.dart';

/// 阅读界面菜单/按钮配置：控制显示与排序（对齐原版三个 ConfigSheet）
class ReadToolConfigScreen extends StatefulWidget {
  const ReadToolConfigScreen({super.key});

  @override
  State<ReadToolConfigScreen> createState() => _ReadToolConfigScreenState();
}

class _Group {
  final String title;
  final String prefsKey;
  final Map<String, String> all;
  final List<String> defaults;
  List<String> order; // 可见且有序
  _Group(this.title, this.prefsKey, this.all, this.defaults, this.order);
}

class _ReadToolConfigScreenState extends State<ReadToolConfigScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final List<_Group> _groups = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _load();
  }

  Future<void> _load() async {
    final tb = await ReadMenuConfig.load(ReadMenuConfig.kToolBar, ReadMenuConfig.defaultToolBar);
    final mm = await ReadMenuConfig.load(ReadMenuConfig.kMoreMenu, ReadMenuConfig.defaultMoreMenu);
    final sm = await ReadMenuConfig.load(ReadMenuConfig.kSelectMenu, ReadMenuConfig.defaultSelectMenu);
    final fb = await ReadMenuConfig.load(ReadMenuConfig.kFloatingBar, ReadMenuConfig.defaultFloatingBar);
    _groups
      ..add(_Group('底部工具栏', ReadMenuConfig.kToolBar, ReadMenuConfig.toolBarItems, ReadMenuConfig.defaultToolBar, tb))
      ..add(_Group('更多菜单', ReadMenuConfig.kMoreMenu, ReadMenuConfig.moreMenuItems, ReadMenuConfig.defaultMoreMenu, mm))
      ..add(_Group('文本选择菜单', ReadMenuConfig.kSelectMenu, ReadMenuConfig.selectMenuItems, ReadMenuConfig.defaultSelectMenu, sm))
      ..add(_Group('悬浮快捷栏', ReadMenuConfig.kFloatingBar, ReadMenuConfig.floatingBarItems, ReadMenuConfig.defaultFloatingBar, fb));
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save(_Group g) => ReadMenuConfig.save(g.prefsKey, g.order);

  void _toggle(_Group g, String key, bool on) {
    setState(() {
      if (on) {
        if (!g.order.contains(key)) g.order.add(key);
      } else {
        g.order.remove(key);
      }
    });
    _save(g);
  }

  void _move(_Group g, int i, int dir) {
    final j = i + dir;
    if (j < 0 || j >= g.order.length) return;
    setState(() {
      final t = g.order[i]; g.order[i] = g.order[j]; g.order[j] = t;
    });
    _save(g);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(
        title: const Text('阅读菜单配置'),
        bottom: TabBar(controller: _tab, isScrollable: true, tabs: const [Tab(text: '底部工具栏'), Tab(text: '更多菜单'), Tab(text: '选择菜单'), Tab(text: '悬浮栏')]),
        actions: [
          IconButton(tooltip: '恢复默认', icon: const Icon(Icons.restart_alt), onPressed: _resetAll),
        ],
      ),
      body: TabBarView(
        controller: _tab,
        children: _groups.map(_buildGroup).toList(),
      ),
    );
  }

  Future<void> _resetAll() async {
    for (final g in _groups) {
      g.order = List.of(g.defaults);
      await _save(g);
    }
    if (mounted) setState(() {});
  }

  Widget _buildGroup(_Group g) {
    // 已显示项按 order 排在前，其余隐藏项排在后
    final hidden = g.all.keys.where((k) => !g.order.contains(k)).toList();
    return ListView(
      children: [
        Padding(padding: const EdgeInsets.all(12), child: Text('勾选显示，拖动箭头调整顺序（已显示 ${g.order.length}/${g.all.length}）', style: Theme.of(context).textTheme.bodySmall)),
        for (var i = 0; i < g.order.length; i++)
          _tile(g, g.order[i], true, i),
        if (hidden.isNotEmpty) const Divider(),
        for (final k in hidden) _tile(g, k, false, -1),
      ],
    );
  }

  Widget _tile(_Group g, String key, bool shown, int index) {
    return ListTile(
      dense: true,
      leading: Checkbox(value: shown, onChanged: (v) => _toggle(g, key, v ?? false)),
      title: Text(g.all[key] ?? key),
      trailing: shown
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: const Icon(Icons.arrow_upward, size: 20), onPressed: index > 0 ? () => _move(g, index, -1) : null),
              IconButton(icon: const Icon(Icons.arrow_downward, size: 20), onPressed: index < g.order.length - 1 ? () => _move(g, index, 1) : null),
            ])
          : null,
    );
  }
}
