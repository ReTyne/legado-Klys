import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/rss_source.dart';
import 'package:legado_md3/ui/rss/rss_source_edit_screen.dart';
import 'package:legado_md3/ui/rss/rss_source_debug_screen.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';

/// 订阅源管理 ——  `ui/rss/source/RssSourceActivity`。
///
/// 功能分区：
/// - 列表项：启用开关 + 名称/地址 + 编辑 + 更多菜单
/// - 更多菜单：登录 / 刷新 / 复制JSON / 分享 / 删除
/// - 顶栏：新增订阅源 + 分组过滤（全部/启用/禁用/未分组/各分组）
class RssSourceScreen extends StatefulWidget {
  const RssSourceScreen({super.key});

  @override
  State<RssSourceScreen> createState() => _RssSourceScreenState();
}

class _RssSourceScreenState extends State<RssSourceScreen> {
  final DatabaseService _db = DatabaseService();
  List<RssSource> _sources = [];
  List<RssSource> _visible = [];
  String _groupFilter = '全部';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sources = await _db.getRssSources();
    if (!mounted) return;
    // customOrder 非空时按手工顺序展示（置顶/置底），否则保留 DAO 顺序
    sources.sort((a, b) {
      final oa = a.customOrder;
      final ob = b.customOrder;
      if (oa == null && ob == null) return 0;
      if (oa == null) return 1;
      if (ob == null) return -1;
      return oa.compareTo(ob);
    });
    setState(() {
      _sources = sources;
      _loading = false;
    });
    _applyFilter();
  }

  void _applyFilter() {
    setState(() {
      _visible = _sources.where((s) {
        switch (_groupFilter) {
          case '启用':
            return s.enabled == true;
          case '禁用':
            return s.enabled != true;
          case '未分组':
            final g = s.sourceGroup;
            return g == null || g.trim().isEmpty;
          case '全部':
            return true;
          default:
            return s.sourceGroup == _groupFilter;
        }
      }).toList();
    });
  }

  List<String> get _groups {
    final set = <String>{};
    for (final s in _sources) {
      final g = s.sourceGroup;
      if (g != null && g.trim().isNotEmpty) set.add(g);
    }
    final list = set.toList()..sort();
    return ['全部', '启用', '禁用', '未分组', ...list];
  }

  Future<void> _addSource() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RssSourceEditScreen()),
    );
    _load();
  }

  Future<void> _editSource(RssSource source) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RssSourceEditScreen(source: source)),
    );
    _load();
  }

  Future<void> _toggleEnabled(RssSource source, bool value) async {
    source.enabled = value;
    await _db.updateRssSource(source);
    setState(() {});
  }

  Future<void> _deleteSource(RssSource source) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: '删除订阅源',
      content: '确定删除「${source.sourceName}」吗？',
      confirmText: '删除',
      danger: true,
    );
    if (confirmed && source.id != null) {
      await _db.deleteRssSource(source.id!);
      _load();
    }
  }

  /// 置顶/置底：移动该项后把当前顺序写回 customOrder（与 E 端 upOrder 一致）。
  Future<void> _reorder(RssSource source, {required bool toTop}) async {
    final list = List<RssSource>.of(_sources);
    list.removeWhere((s) => s.id == source.id);
    if (toTop) {
      list.insert(0, source);
    } else {
      list.add(source);
    }
    for (var i = 0; i < list.length; i++) {
      list[i].customOrder = i;
      await _db.updateRssSource(list[i]);
    }
    await _load();
  }

  void _showSourceMenu(RssSource source) {
    showAppMenuSheet(context, title: source.sourceName, items: [
      AppMenuSheetItem(
          title: '置顶',
          icon: Icons.vertical_align_top,
          onTap: () => _reorder(source, toTop: true)),
      AppMenuSheetItem(
          title: '置底',
          icon: Icons.vertical_align_bottom,
          onTap: () => _reorder(source, toTop: false)),
      AppMenuSheetItem(
          title: '编辑',
          icon: Icons.edit_outlined,
          onTap: () => _editSource(source)),
      AppMenuSheetItem(
          title: '调试订阅源',
          icon: Icons.bug_report_outlined,
          subtitle: '分类 / 列表 / 正文三段调试',
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => RssSourceDebugScreen(source: source)))),
      AppMenuSheetItem(
          title: '复制源JSON',
          icon: Icons.content_copy,
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: _encode(source)));
            if (mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('订阅源JSON已复制')));
            }
          }),
      AppMenuSheetItem(
          title: '分享',
          icon: Icons.share,
          onTap: () => Share.share(_encode(source))),
      AppMenuSheetItem(
          title: '删除',
          icon: Icons.delete_outline,
          onTap: () => _deleteSource(source)),
    ]);
  }

  String _encode(RssSource source) => jsonEncode(source.toJson());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('订阅源管理'),
        actions: [
          PopupMenuButton<String>(
            tooltip: '分组',
            icon: const Icon(Icons.filter_list),
            initialValue: _groupFilter,
            onSelected: (v) {
              setState(() => _groupFilter = v);
              _applyFilter();
            },
            itemBuilder: (context) => _groups
                .map((g) => PopupMenuItem(value: g, child: Text(g)))
                .toList(),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新增订阅源',
            onPressed: _addSource,
          ),
        ],
      ),
      body: _loading
          ? const AppLoadingIndicator()
          : _visible.isEmpty
              ? const AppEmptyState(
                  icon: Icons.rss_feed_outlined,
                  title: '暂无订阅源',
                  message: '点击右上角新增订阅源',
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
                  itemCount: _visible.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final source = _visible[i];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            Theme.of(context).colorScheme.secondaryContainer,
                        child: Text(
                          source.sourceName.isNotEmpty
                              ? source.sourceName[0]
                              : '?',
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSecondaryContainer),
                        ),
                      ),
                      title: Text(source.sourceName,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                          '${source.sourceUrl}${(source.sourceGroup ?? '').trim().isNotEmpty ? ' · ${source.sourceGroup}' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12)),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        Switch(
                          value: source.enabled == true,
                          onChanged: (v) => _toggleEnabled(source, v),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: '编辑',
                          onPressed: () => _editSource(source),
                        ),
                        IconButton(
                          icon: const Icon(Icons.more_vert),
                          tooltip: '更多',
                          onPressed: () => _showSourceMenu(source),
                        ),
                      ]),
                    );
                  },
                ),
    );
  }
}
