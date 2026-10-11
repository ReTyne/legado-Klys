import 'package:flutter/material.dart';

import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/rss_source.dart';
import 'package:legado_md3/data/model/rss_article.dart';
import 'package:legado_md3/help/http/rss_service.dart';
import 'package:legado_md3/ui/rss/rss_read_screen.dart';

/// 订阅源文章列表页：对齐 legado RssArticlesScreen。
/// 支持 sortUrl 分类切换、进入即拉取、缩略图、刷新；结果落库。
class RssArticlesScreen extends StatefulWidget {
  const RssArticlesScreen({super.key, required this.source});
  final RssSource source;

  @override
  State<RssArticlesScreen> createState() => _RssArticlesScreenState();
}

class _RssArticlesScreenState extends State<RssArticlesScreen> {
  final DatabaseService _db = DatabaseService();
  final RssService _service = RssService();
  late RssSource source;
  late List<RssCategory> _categories;
  RssCategory? _category;
  List<RssArticle> _articles = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    source = widget.source;
    _categories = _service.parseCategories(source);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = _category == null
          ? await _service.fetchRss(source)
          : await _service.fetchCategory(source, _category!);
      for (final a in list) {
        await _db.saveRssArticles([a]);
      }
      if (mounted) {
        setState(() {
          _articles = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  void _switchCategory() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: const Text('全部（默认）'),
            trailing: _category == null ? const Icon(Icons.check) : null,
            onTap: () {
              Navigator.pop(ctx);
              if (_category != null) {
                setState(() => _category = null);
                _load();
              }
            },
          ),
          for (final c in _categories)
            ListTile(
              title: Text(c.name),
              trailing: _category?.name == c.name
                  ? const Icon(Icons.check)
                  : null,
              onTap: () {
                Navigator.pop(ctx);
                if (_category?.name != c.name) {
                  setState(() => _category = c);
                  _load();
                }
              },
            ),
        ]),
      ),
    );
  }

  Future<void> _openArticle(RssArticle article) async {
    if (article.id != null) {
      await _db.markRssArticleRead(article.id!);
    }
    if (mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              RssReadScreen(article: article, source: source),
        ),
      );
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _category?.name ?? source.sourceName;
    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (_categories.isNotEmpty)
            IconButton(
              tooltip: '分类',
              icon: const Icon(Icons.category_outlined),
              onPressed: _switchCategory,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(message: _error!, onRetry: _load)
              : _articles.isEmpty
                  ? _empty()
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        itemCount: _articles.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (c, i) => _tile(_articles[i]),
                      ),
                    ),
    );
  }

  Widget _tile(RssArticle article) {
    final read = article.read == true;
    return ListTile(
      leading: _thumb(article),
      title: Text(
        article.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: read ? FontWeight.normal : FontWeight.bold,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ((article.description ?? '').isNotEmpty)
            Text(article.description!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 2),
          Text(
            '${article.sourceName ?? ''} ${article.pubDate != null ? DateTime.fromMillisecondsSinceEpoch(article.pubDate!).toString().substring(0, 16) : ''}',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
      trailing: read
          ? const Icon(Icons.check_circle_outline,
              size: 18, color: Colors.grey)
          : Icon(Icons.fiber_new, size: 18, color: Colors.red[400]),
      onTap: () => _openArticle(article),
    );
  }

  Widget _thumb(RssArticle article) {
    if ((article.image ?? '').isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.network(
          article.image!,
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _iconBox(article),
        ),
      );
    }
    return _iconBox(article);
  }

  Widget _iconBox(RssArticle article) => Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Icon(Icons.article_outlined, size: 24),
      );

  Widget _empty() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined,
                size: 72, color: Colors.grey[400]),
            const SizedBox(height: 12),
            const Text('暂无文章'),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('重新加载'),
            ),
          ],
        ),
      );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.grey),
            const SizedBox(height: 12),
            Text('加载失败',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(message,
                textAlign: TextAlign.center,
                maxLines: 3,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
