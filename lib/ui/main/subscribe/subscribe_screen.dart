import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:legado_md3/data/model/rss_source.dart';
import 'package:legado_md3/ui/rss/rss_source_edit_screen.dart';
import 'package:legado_md3/ui/rss/rss_favorites_screen.dart';
import 'package:legado_md3/ui/rss/rss_articles_screen.dart';
import 'package:legado_md3/ui/rss/rss_source_screen.dart';
import 'package:legado_md3/ui/rss/rule_subscription_screen.dart';
import 'package:legado_md3/ui/stats/read_record_screen.dart';
import 'package:legado_md3/ui/rss/rss_source_login_screen.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/help/http/rss_service.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';

class SubscribeScreen extends StatefulWidget {
  const SubscribeScreen({super.key});

  @override
  State<SubscribeScreen> createState() => _SubscribeScreenState();
}

class _SubscribeScreenState extends State<SubscribeScreen> {
  final DatabaseService _db = DatabaseService();
  final RssService _rssService = RssService();
  List<RssSource> _sources = [];
  bool _isLoading = true;
  bool _searching = false;
  String _searchQuery = '';
  /// 订阅源分组过滤（对齐 legado-E main_rss.xml 的 menu_group 子菜单）
  String _groupFilter = '';
  final TextEditingController _searchController = TextEditingController();

  /// 视图模式：0 网格 / 1 列表（真实持久化）。
  int _viewMode = 0;
  /// 排序：0 默认 / 1 名称 / 2 分组（分区） / 3 最近更新（真实持久化）。
  int _sortMode = 0;
  static const _viewModeKey = 'subscribe_view_mode';
  static const _sortModeKey = 'subscribe_sort_mode';

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadViewConfig();
  }

  Future<void> _loadViewConfig() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _viewMode = p.getInt(_viewModeKey) ?? 0;
          _sortMode = p.getInt(_sortModeKey) ?? 0;
        });
      }
    } catch (_) {}
  }

  Future<void> _setViewMode(int v) async {
    setState(() => _viewMode = v);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_viewModeKey, v);
    } catch (_) {}
  }

  Future<void> _setSortMode(int v) async {
    setState(() => _sortMode = v);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_sortModeKey, v);
    } catch (_) {}
  }

  /// 按当前排序方式对已过滤的订阅源排序。
  List<RssSource> _sortedSources(List<RssSource> src) {
    final list = List<RssSource>.of(src);
    switch (_sortMode) {
      case 1:
        list.sort((a, b) => a.sourceName.compareTo(b.sourceName));
        break;
      case 2:
        list.sort((a, b) {
          final ga = (a.sourceGroup ?? '').trim();
          final gb = (b.sourceGroup ?? '').trim();
          final c = ga.compareTo(gb);
          return c != 0 ? c : a.sourceName.compareTo(b.sourceName);
        });
        break;
      case 3:
        list.sort((a, b) =>
            (b.lastUpdateTime ?? 0).compareTo(a.lastUpdateTime ?? 0));
        break;
      default:
        break; // DAO 已按 lastUpdateTime DESC
    }
    return list;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showImportMenu() {
    showAppMenuSheet(context, title: '导入订阅源', items: [
      AppMenuSheetItem(
          title: '网络导入',
          icon: Icons.cloud_outlined,
          onTap: _importNetwork),
      AppMenuSheetItem(
          title: '剪贴板导入',
          icon: Icons.content_paste,
          onTap: () async {
            final t =
                (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
            _parseAndSave(t);
          }),
    ]);
  }

  Future<void> _importNetwork() async {
    final ctl = TextEditingController();
    final url = await showDialog<String>(context: context, builder: (c) => AlertDialog(
      title: const Text('网络导入订阅源'),
      content: TextField(controller: ctl, decoration: const InputDecoration(hintText: '订阅源URL')),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(c, ctl.text), child: const Text('导入'))],
    ));
    if (url == null || url.isEmpty) return;
    try {
      final res = await Dio(BaseOptions(responseType: ResponseType.plain)).get<String>(url);
      await _parseAndSave(res.data ?? '');
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('失败: $e'))); }
  }

  Future<void> _parseAndSave(String raw) async {
    if (raw.trim().isEmpty) return;
    try {
      final data = jsonDecode(raw);
      final list = data is List ? data : [data];
      int n = 0;
      for (final m in list) {
        if (m is Map) {
          try { await _db.insertRssSource(RssSource.fromJson(Map<String, dynamic>.from(m))); n++; } catch (_) {}
        }
      }
      await _loadData();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入 $n 个订阅源')));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('解析失败: $e'))); }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      _sources = await _db.getRssSources();
    } catch (_) {
      // 数据库尚未就绪等情况下保持空态，不使页面崩溃
    }
    if (mounted) setState(() => _isLoading = false);
  }

  /// 订阅源可用分组（对齐 legado-E RssFragment 的 flowEnabledGroups + menu_group）。
  /// 首位为「全部」；当前过滤值在数据变化后仍保留，避免 PopupMenuButton.initialValue 失配。
  List<String> get _rssGroups {
    final set = <String>{};
    for (final s in _sources) {
      final g = s.sourceGroup?.trim();
      if (g != null && g.isNotEmpty) set.add(g);
    }
    final list = <String>['全部', ...(set.toList()..sort())];
    if (_groupFilter.isNotEmpty && !list.contains(_groupFilter)) {
      list.add(_groupFilter);
    }
    return list;
  }

  Future<void> _addSource() async {
    final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => const RssSourceEditScreen()));
    if (result == true) _loadData();
  }

  Future<void> _refreshSource(RssSource source) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('正在刷新: ${source.name}')),
    );
    final articles = await _rssService.fetchRss(source);
    for (final article in articles) {
      await _db.saveRssArticles([article]);
    }
    source.lastUpdateTime = DateTime.now().millisecondsSinceEpoch;
    await _db.updateRssSource(source);
    _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('刷新完成: ${articles.length} 篇文章')),
      );
    }
  }

  Future<void> _refreshAll() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('正在刷新所有订阅...')),
    );
    int total = 0;
    for (final source in _sources) {
      if (source.enabled != true) continue;
      final articles = await _rssService.fetchRss(source);
      for (final article in articles) {
        await _db.saveRssArticles([article]);
      }
      source.lastUpdateTime = DateTime.now().millisecondsSinceEpoch;
      await _db.updateRssSource(source);
      total += articles.length;
    }
    _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('刷新完成: 共抓取 $total 篇文章')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                    hintText: '搜索订阅源/分组...', border: InputBorder.none),
                onChanged: (v) => setState(() => _searchQuery = v),
              )
            : const Text('订阅'),
        actions: [
          if (_searching)
            IconButton(
              icon: const Icon(Icons.clear),
              tooltip: '清除搜索',
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _searching = false;
                  _searchQuery = '';
                });
              },
            )
          else
            IconButton(
                icon: const Icon(Icons.search),
                tooltip: '搜索订阅源',
                onPressed: () => setState(() => _searching = true)),
          IconButton(
            icon: const Icon(Icons.star_border),
            tooltip: '收藏文章',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RssFavoritesScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: '阅读记录',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReadRecordScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '订阅源管理',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RssSourceScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新全部',
            onPressed: _refreshAll,
          ),
          IconButton(icon: const Icon(Icons.file_download_outlined), tooltip: '导入订阅源', onPressed: _showImportMenu),
        ],
      ),
      body: Column(
        children: [
          // 对齐 legado-E RssFragment：RecyclerView 顶部常驻 header「规则订阅」，
          // 以及 main_rss.xml 的 menu_group 分组过滤，二者不随订阅源空态消失。
          _buildRssHeader(),
          const Divider(height: 1),
          Expanded(
            child: _isLoading
                ? const AppLoadingIndicator()
                : _buildSourcesView(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addSource,
        child: const Icon(Icons.add),
      ),
    );
  }

  /// 订阅页顶部入口 —— 对齐 legado-E `RssFragment.initRecyclerView` 的 header 项
  /// （「规则订阅」→ RuleSubActivity）与 `main_rss.xml` 的 menu_group（分组过滤）。
  /// 两个入口都是真实交互：前者跳转规则订阅管理页（增删/更新订阅），
  /// 后者按 sourceGroup 过滤下方订阅源列表。
  Widget _buildRssHeader() {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const RuleSubscriptionScreen()),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.m),
                child: Row(children: [
                  Icon(Icons.dynamic_feed_outlined, size: 20),
                  SizedBox(width: 10),
                  Text('规则订阅',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500)),
                  Icon(Icons.chevron_right, size: 18),
                ]),
              ),
            ),
          ),
          // 对齐 legado-E main_rss.xml 的 menu_group：选中分组后按 group 过滤订阅源
          PopupMenuButton<String>(
            tooltip: '分组',
            icon: const Icon(Icons.filter_list),
            initialValue: _groupFilter.isEmpty ? '全部' : _groupFilter,
            onSelected: (v) =>
                setState(() => _groupFilter = v == '全部' ? '' : v),
            itemBuilder: (context) => _rssGroups
                .map((g) => PopupMenuItem(value: g, child: Text(g)))
                .toList(),
          ),
          _buildViewSortMenu(),
        ],
      ),
    );
  }

  /// 布局切换（网格 / 列表）与排序（默认 / 名称 / 分组分区 / 最近更新）。
  /// 每项选择都真实改变列表并持久化到 SharedPreferences。
  Widget _buildViewSortMenu() {
    return PopupMenuButton<String>(
      tooltip: '布局与排序',
      icon: const Icon(Icons.view_quilt_outlined),
      onSelected: (v) {
        if (v.startsWith('layout_')) {
          _setViewMode(v == 'layout_list' ? 1 : 0);
        } else if (v.startsWith('sort_')) {
          _setSortMode(int.tryParse(v.substring(5)) ?? 0);
        }
      },
      itemBuilder: (context) => [
        _viewSortItem('layout_grid', '网格布局', _viewMode == 0),
        _viewSortItem('layout_list', '列表布局', _viewMode == 1),
        const PopupMenuDivider(),
        _viewSortItem('sort_0', '默认排序', _sortMode == 0),
        _viewSortItem('sort_1', '按名称', _sortMode == 1),
        _viewSortItem('sort_2', '按分组分区', _sortMode == 2),
        _viewSortItem('sort_3', '按最近更新', _sortMode == 3),
      ],
    );
  }

  PopupMenuItem<String> _viewSortItem(
          String value, String label, bool checked) =>
      PopupMenuItem<String>(
        value: value,
        child: Row(
          children: [
            Expanded(child: Text(label)),
            if (checked)
              Icon(Icons.check,
                  size: 18, color: Theme.of(context).colorScheme.primary),
          ],
        ),
      );

  /// 订阅源视图 —— 对齐 legado-E `fragment_rss.xml`：分组过滤 + 搜索叠加，
  /// 再按当前排序输出网格（spanCount=4）或列表（按分组时显示分区标题）。
  Widget _buildSourcesView() {
    final q = _searchQuery.toLowerCase();
    final filtered = _sources
        .where((s) =>
            (_groupFilter.isEmpty ||
                (s.sourceGroup ?? '').trim() == _groupFilter) &&
            (q.isEmpty ||
                s.sourceName.toLowerCase().contains(q) ||
                (s.sourceGroup ?? '').toLowerCase().contains(q)))
        .toList();
    if (filtered.isEmpty) {
      return AppEmptyState(
        icon: Icons.subscriptions_outlined,
        title: _searchQuery.isEmpty && _groupFilter.isEmpty
            ? '暂无订阅源'
            : '没有匹配的订阅源',
        message: _searchQuery.isEmpty && _groupFilter.isEmpty
            ? '点击右下角添加订阅源'
            : null,
      );
    }
    final sorted = _sortedSources(filtered);
    return _viewMode == 1 ? _buildListView(sorted) : _buildGridView(sorted);
  }

  Widget _buildGridView(List<RssSource> groups) {
    return GridView.builder(
      padding: const EdgeInsets.all(AppSpacing.m),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.72,
      ),
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final source = groups[index];
        final enabled = source.enabled == true;
        return InkWell(
          borderRadius: AppRadius.mAll,
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => RssArticlesScreen(source: source))),
          onLongPress: () => _showSourceOptions(source),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Opacity(
              opacity: enabled ? 1 : 0.38,
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: AppRadius.mAll,
                  image: (source.sourceIcon ?? '').isNotEmpty
                      ? DecorationImage(
                          image: NetworkImage(source.sourceIcon!),
                          fit: BoxFit.cover)
                      : null,
                ),
                alignment: Alignment.center,
                child: (source.sourceIcon ?? '').isNotEmpty
                    ? null
                    : Text(
                        source.sourceName.isNotEmpty ? source.sourceName[0] : '?',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSecondaryContainer),
                      ),
              ),
            ),
            const SizedBox(height: AppSpacing.s),
            Text(source.sourceName,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13,
                    color: enabled
                        ? Theme.of(context).colorScheme.onSurface
                        : Theme.of(context).colorScheme.onSurfaceVariant)),
          ]),
        );
      },
    );
  }

  /// 列表布局；按分组排序时插入 AppSectionHeader 形成分区。
  Widget _buildListView(List<RssSource> groups) {
    final children = <Widget>[];
    String? lastGroup;
    for (final source in groups) {
      if (_sortMode == 2) {
        final g = (source.sourceGroup ?? '').trim().isEmpty
            ? '未分组'
            : source.sourceGroup!.trim();
        if (g != lastGroup) {
          children.add(AppSectionHeader(g));
          lastGroup = g;
        }
      }
      children.add(_buildListTile(source));
    }
    return ListView(children: children);
  }

  Widget _buildListTile(RssSource source) {
    final cs = Theme.of(context).colorScheme;
    final enabled = source.enabled == true;
    final group = (source.sourceGroup ?? '').trim().isEmpty
        ? '未分组'
        : source.sourceGroup!.trim();
    final updated = source.lastUpdateTime != null
        ? ' · ${DateTime.fromMillisecondsSinceEpoch(source.lastUpdateTime!).toString().substring(0, 10)}'
        : '';
    return ListTile(
      leading: Opacity(
        opacity: enabled ? 1 : 0.38,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: cs.secondaryContainer,
            borderRadius: AppRadius.mAll,
            image: (source.sourceIcon ?? '').isNotEmpty
                ? DecorationImage(
                    image: NetworkImage(source.sourceIcon!), fit: BoxFit.cover)
                : null,
          ),
          alignment: Alignment.center,
          child: (source.sourceIcon ?? '').isNotEmpty
              ? null
              : Text(
                  source.sourceName.isNotEmpty ? source.sourceName[0] : '?',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: cs.onSecondaryContainer),
                ),
        ),
      ),
      title: Text(source.sourceName,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('$group$updated',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11)),
      trailing: Icon(
          enabled ? Icons.chevron_right : Icons.block_outlined,
          size: 18,
          color: cs.onSurfaceVariant),
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => RssArticlesScreen(source: source))),
      onLongPress: () => _showSourceOptions(source),
    );
  }



  void _showSourceOptions(RssSource source) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.article_outlined),
              title: const Text('查看文章'),
              onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => RssArticlesScreen(source: source))); },
            ),
            if ((source.loginUrl ?? '').trim().isNotEmpty ||
                (source.loginUi ?? '').trim().isNotEmpty)
              ListTile(
                leading: const Icon(Icons.login),
                title: const Text('登录'),
                onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => RssSourceLoginScreen(source: source))); },
              ),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('刷新'),
              onTap: () { Navigator.pop(context); _refreshSource(source); },
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('编辑'),
              onTap: () { Navigator.pop(context); _editSource(source); },
            ),
            ListTile(
              leading: Icon(source.enabled == true ? Icons.toggle_off : Icons.toggle_on),
              title: Text(source.enabled == true ? '禁用' : '启用'),
              onTap: () async { Navigator.pop(context); source.enabled = !(source.enabled == true); await _db.updateRssSource(source); _loadData(); },
            ),
            ListTile(
              leading: const Icon(Icons.content_copy),
              title: const Text('复制源JSON'),
              onTap: () async {
                Navigator.pop(context);
                await Clipboard.setData(ClipboardData(text: jsonEncode(source.toJson())));
                if (mounted && context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('订阅源JSON已复制')));
              },
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('分享'),
              onTap: () { Navigator.pop(context); Share.share(jsonEncode(source.toJson())); },
            ),
            ListTile(
              leading: const Icon(Icons.star_outline),
              title: const Text('查看收藏文章'),
              onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const RssFavoritesScreen())); },
            ),
            ListTile(
              leading: const Icon(Icons.done_all),
              title: const Text('全部标为已读'),
              onTap: () async {
                Navigator.pop(context);
                await _db.markAllRssRead(sourceUrl: source.sourceUrl);
                await _loadData();
                if (mounted && context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已全部标为已读')));
              },
            ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.delete_outline, color: cs.error),
              title: Text('删除', style: TextStyle(color: cs.error)),
              onTap: () async {
                Navigator.pop(context);
                if (source.id != null) await _db.deleteRssSource(source.id!);
                _loadData();
              },
            ),
          ],
        )),
      ),
    );
  }


  void _editSource(RssSource source) async {
    final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => RssSourceEditScreen(source: source)));
    if (result == true) _loadData();
  }
}
