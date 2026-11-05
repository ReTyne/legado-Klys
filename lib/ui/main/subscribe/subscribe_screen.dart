import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:legado_md3/data/model/rss_source.dart';
import 'package:legado_md3/data/model/rss_article.dart';
import 'package:legado_md3/ui/rss/rss_source_edit_screen.dart';
import 'package:legado_md3/ui/rss/rss_favorites_screen.dart';
import 'package:legado_md3/ui/rss/rss_articles_screen.dart';
import 'package:legado_md3/ui/rss/rss_source_screen.dart';
import 'package:legado_md3/ui/rss/rule_subscription_screen.dart';
import 'package:legado_md3/ui/stats/read_record_screen.dart';
import 'package:legado_md3/ui/rss/rss_source_login_screen.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/help/http/rss_service.dart';

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

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showImportMenu() {
    showModalBottomSheet(context: context, builder: (c) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: const Icon(Icons.cloud_outlined), title: const Text('网络导入'), onTap: () { Navigator.pop(c); _importNetwork(); }),
      ListTile(leading: const Icon(Icons.content_paste), title: const Text('剪贴板导入'), onTap: () async { Navigator.pop(c); final t = (await Clipboard.getData('text/plain'))?.text ?? ''; _parseAndSave(t); }),
    ])));
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
                ? const Center(child: CircularProgressIndicator())
                : _buildSourcesGrid(),
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
                padding: EdgeInsets.symmetric(horizontal: 12),
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
        ],
      ),
    );
  }

  /// 订阅源网格 —— 对齐 legado-E `fragment_rss.xml`（spanCount=4）
  /// 与 `item_rss.xml`（50dp 圆角图标 + 两行 13sp 名称）。
  Widget _buildSourcesGrid() {
    final q = _searchQuery.toLowerCase();
    // 对齐 legado-E RssFragment：分组过滤（menu_group）与搜索框（关键字/分组）叠加生效
    final groups = _sources
        .where((s) =>
            (_groupFilter.isEmpty ||
                (s.sourceGroup ?? '').trim() == _groupFilter) &&
            (q.isEmpty ||
                s.sourceName.toLowerCase().contains(q) ||
                (s.sourceGroup ?? '').toLowerCase().contains(q)))
        .toList();
    if (groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.subscriptions_outlined, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(_searchQuery.isEmpty && _groupFilter.isEmpty
                    ? '暂无订阅源'
                    : '没有匹配的订阅源',
                style: TextStyle(fontSize: 18, color: Colors.grey[600])),
            const SizedBox(height: 8),
            if (_searchQuery.isEmpty && _groupFilter.isEmpty)
              const Text('点击右下角添加订阅源'),
          ],
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
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
          borderRadius: BorderRadius.circular(12),
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
                  borderRadius: BorderRadius.circular(12),
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
            const SizedBox(height: 8),
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



  void _showSourceOptions(RssSource source) {
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
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('订阅源JSON已复制')));
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
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已全部标为已读')));
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('删除', style: TextStyle(color: Colors.red)),
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

  void _showArticleOptions(RssArticle article) {
    showModalBottomSheet(context: context, builder: (context) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(
        leading: Icon(article.read == true ? Icons.mark_email_unread : Icons.mark_email_read),
        title: Text(article.read == true ? '标为未读' : '标为已读'),
        onTap: () async { Navigator.pop(context); if (article.id != null) { final r = !(article.read == true); await _db.setRssArticleRead(article.id!, r); _loadData(); } },
      ),
      ListTile(
        leading: Icon(article.starred == true ? Icons.star : Icons.star_border),
        title: Text(article.starred == true ? '取消收藏' : '收藏'),
        onTap: () async {
          Navigator.pop(context);
          if (article.id != null) {
            final s = !(article.starred == true);
            await _db.setRssArticleStar(article.id!, s);
            await _loadData();
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s ? '已收藏' : '已取消收藏')));
          }
        },
      ),
      ListTile(
        leading: const Icon(Icons.open_in_browser),
        title: const Text('在浏览器打开'),
        onTap: () async { Navigator.pop(context); if (article.link.isNotEmpty) await launchUrl(Uri.parse(article.link), mode: LaunchMode.externalApplication); },
      ),
      ListTile(
        leading: const Icon(Icons.content_copy),
        title: const Text('复制链接'),
        onTap: () async { Navigator.pop(context); await Clipboard.setData(ClipboardData(text: article.link)); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制'))); },
      ),
      ListTile(
        leading: const Icon(Icons.share),
        title: const Text('分享'),
        onTap: () { Navigator.pop(context); Share.share('${article.title}\n${article.link}'); },
      ),
    ])));
  }

  void _editSource(RssSource source) async {
    final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => RssSourceEditScreen(source: source)));
    if (result == true) _loadData();
  }
}
