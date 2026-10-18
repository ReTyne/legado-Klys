import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:legado_md3/data/model/rss_source.dart';
import 'package:legado_md3/data/model/rss_article.dart';
import 'package:legado_md3/ui/rss/rss_read_screen.dart';
import 'package:legado_md3/ui/rss/rss_source_edit_screen.dart';
import 'package:legado_md3/ui/rss/rss_favorites_screen.dart';
import 'package:legado_md3/ui/rss/rss_articles_screen.dart';
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
  List<RssArticle> _articles = [];
  bool _isLoading = true;
  bool _showSources = true;
  String? _filterSourceUrl; // 非空时文章列表仅显示该订阅源

  @override
  void initState() {
    super.initState();
    _loadData();
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
    _sources = await _db.getRssSources();
    _articles = await _db.getRssArticles(_filterSourceUrl);
    if (mounted) setState(() => _isLoading = false);
  }

  /// 返回全部文章
  Future<void> _showAllArticles() async {
    setState(() {
      _filterSourceUrl = null;
      _isLoading = true;
    });
    _articles = await _db.getRssArticles();
    if (mounted) setState(() => _isLoading = false);
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
        title: const Text('订阅'),
        actions: [
          IconButton(
            icon: const Icon(Icons.star_border),
            tooltip: '收藏文章',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RssFavoritesScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshAll,
          ),
          IconButton(icon: const Icon(Icons.file_download_outlined), tooltip: '导入订阅源', onPressed: _showImportMenu),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'sources') {
                setState(() => _showSources = true);
              } else if (value == 'articles') {
                _filterSourceUrl = null;
                setState(() => _showSources = false);
                _loadData();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'sources', child: Text('订阅源 (${_sources.length})')),
              PopupMenuItem(value: 'articles', child: Text('文章 (${_articles.length})')),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _showSources
              ? _buildSourcesList()
              : _buildArticlesList(),
      floatingActionButton: FloatingActionButton(
        onPressed: _addSource,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildSourcesList() {
    if (_sources.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.subscriptions_outlined, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('暂无订阅源', style: TextStyle(fontSize: 18, color: Colors.grey[600])),
            const SizedBox(height: 8),
            const Text('点击右下角添加订阅源'),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _sources.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final source = _sources[index];
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              child: Text(source.name.isNotEmpty ? source.name[0] : '?'),
            ),
            title: Text(source.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(source.url, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: source.enabled == true,
                  onChanged: (v) {
                    source.enabled = v;
                    _db.updateRssSource(source);
                    setState(() {});
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => _refreshSource(source),
                ),
              ],
            ),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => RssArticlesScreen(source: source))),
            onLongPress: () => _showSourceOptions(source),
          ),
        );
      },
    );
  }

  Widget _buildArticlesList() {
    final filterName = _filterSourceUrl == null
        ? null
        : _sources.where((s) => s.sourceUrl == _filterSourceUrl).map((s) => s.name).cast<String?>().firstWhere((_) => true, orElse: () => '该订阅源');
    return Column(
      children: [
        if (_filterSourceUrl != null)
          Material(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(children: [
                const Icon(Icons.filter_alt, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text('仅显示「$filterName」的文章', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
                TextButton.icon(
                  onPressed: _showAllArticles,
                  icon: const Icon(Icons.clear, size: 16),
                  label: const Text('全部'),
                ),
              ]),
            ),
          ),
        Expanded(child: _articles.isEmpty ? _buildEmptyArticles() : _buildArticleItems()),
      ],
    );
  }

  Widget _buildEmptyArticles() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.article_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Text('暂无文章'),
        ],
      ),
    );
  }

  Widget _buildArticleItems() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _articles.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final article = _articles[index];
        return ListTile(
          leading: article.read == true ? const Icon(Icons.check_circle_outline, color: Colors.grey) : const Icon(Icons.fiber_new, color: Colors.red),
          title: Text(article.title, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: article.read == true ? FontWeight.normal : FontWeight.bold)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (article.description != null)
                Text(article.description!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 4),
              Text('${article.sourceName ?? ''} ${article.pubDate != null ? DateTime.fromMillisecondsSinceEpoch(article.pubDate!).toString().substring(0, 16) : ''}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
          onTap: () async {
            if (article.id != null) await _db.markRssArticleRead(article.id!);
            if (mounted) {
              final src = _sources
                  .where((s) => s.sourceUrl == article.sourceUrl)
                  .cast<RssSource?>()
                  .firstWhere((_) => true, orElse: () => null);
              await Navigator.push(context, MaterialPageRoute(
                  builder: (_) => RssReadScreen(article: article, source: src)));
            }
            _loadData();
          },
          onLongPress: () => _showArticleOptions(article),
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
