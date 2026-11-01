import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/rss_source.dart';
import 'package:legado_md3/ui/rss/rss_source_edit_screen.dart';

/// 订阅源管理 —— 对齐 legado-E `ui/rss/source/RssSourceActivity`。
///
/// 功能位置与 E 一致：
/// - 列表项：启用开关 + 名称/地址 + 编辑 + 更多菜单（对齐 item_rss_source.xml）
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除订阅源'),
        content: Text('确定删除「${source.sourceName}」吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && source.id != null) {
      await _db.deleteRssSource(source.id!);
      _load();
    }
  }

  void _showSourceMenu(RssSource source) {
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('编辑'),
              onTap: () {
                Navigator.pop(c);
                _editSource(source);
              },
            ),
            ListTile(
              leading: const Icon(Icons.content_copy),
              title: const Text('复制源JSON'),
              onTap: () async {
                Navigator.pop(c);
                await Clipboard.setData(ClipboardData(text: _encode(source)));
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('订阅源JSON已复制')));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('分享'),
              onTap: () {
                Navigator.pop(c);
                Share.share(_encode(source));
              },
            ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error),
              title: Text('删除',
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
              onTap: () {
                Navigator.pop(c);
                _deleteSource(source);
              },
            ),
          ]),
        ),
      ),
    );
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
            itemBuilder: (context) =>
                _groups.map((g) => PopupMenuItem(value: g, child: Text(g))).toList(),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新增订阅源',
            onPressed: _addSource,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _visible.isEmpty
              ? Center(
                  child: Text('暂无订阅源',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _visible.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final source = _visible[i];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            Theme.of(context).colorScheme.secondaryContainer,
                        child: Text(
                          source.sourceName.isNotEmpty ? source.sourceName[0] : '?',
                          style: TextStyle(
                              color:
                                  Theme.of(context).colorScheme.onSecondaryContainer),
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
