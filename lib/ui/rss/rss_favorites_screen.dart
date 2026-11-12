import 'package:flutter/material.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/rss_article.dart';
import 'package:legado_md3/ui/rss/rss_read_screen.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';

/// RSS收藏文章页面 - RssFavoritesScreen
class RssFavoritesScreen extends StatefulWidget {
  const RssFavoritesScreen({super.key});

  @override
  State<RssFavoritesScreen> createState() => _RssFavoritesScreenState();
}

class _RssFavoritesScreenState extends State<RssFavoritesScreen> {
  final _db = DatabaseService();
  List<RssArticle> _articles = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    setState(() => _loading = true);
    final maps = await _db.getStarredRssArticles();
    setState(() {
      _articles = maps.map((m) => RssArticle.fromMap(m)).toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('收藏文章'),
        actions: [
          if (_articles.isNotEmpty)
            PopupMenuButton<String>(
              tooltip: '更多',
              onSelected: (v) {
                if (v == 'clear') _showClearDialog();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'clear', child: Text('清空收藏')),
              ],
            ),
        ],
      ),
      body: _loading
          ? const AppLoadingIndicator()
          : _articles.isEmpty
              ? const AppEmptyState(
                  icon: Icons.star_border,
                  title: '暂无收藏文章',
                )
              : RefreshIndicator(
                  onRefresh: _loadFavorites,
                  child: ListView.builder(
                    itemCount: _articles.length,
                    itemBuilder: (context, index) {
                      final article = _articles[index];
                      return Dismissible(
                        key: ValueKey(article.id ?? index),
                        direction: DismissDirection.endToStart,
                        background: Container(
                            color: cs.error,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: AppSpacing.l),
                            child: Icon(Icons.delete, color: cs.onError)),
                        onDismissed: (_) async {
                          if (article.id != null) {
                            await _db.toggleRssFavorite(article.id!, 0);
                          }
                          _loadFavorites();
                        },
                        child: ListTile(
                          title: Text(article.title,
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (article.description != null)
                                  Text(article.description!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12)),
                                const SizedBox(height: AppSpacing.xs),
                                Text(article.sourceName ?? '',
                                    style: TextStyle(
                                        fontSize: 11, color: cs.primary)),
                              ]),
                          trailing: IconButton(
                            tooltip: '取消收藏',
                            icon: Icon(Icons.star, color: cs.primary),
                            onPressed: () async {
                              if (article.id != null) {
                                await _db.toggleRssFavorite(article.id!, 0);
                              }
                              _loadFavorites();
                            },
                          ),
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      RssReadScreen(article: article))),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  Future<void> _showClearDialog() async {
    final ok = await showAppConfirmDialog(
      context,
      title: '清空收藏',
      content: '确定清空所有收藏文章吗？',
      confirmText: '清空',
      danger: true,
    );
    if (!ok) return;
    for (final a in _articles) {
      if (a.id != null) await _db.toggleRssFavorite(a.id!, 0);
    }
    if (mounted) _loadFavorites();
  }
}
