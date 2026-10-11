import 'package:flutter/material.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/rss_article.dart';
import 'package:legado_md3/ui/rss/rss_read_screen.dart';

/// RSS收藏文章页面 - 对齐原版RssFavoritesScreen
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('收藏文章'),
        actions: [
          if (_articles.isNotEmpty)
            PopupMenuButton<String>(
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
          ? const Center(child: CircularProgressIndicator())
          : _articles.isEmpty
              ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.star_border, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('暂无收藏文章', style: TextStyle(fontSize: 16, color: Colors.grey)),
                ]))
              : RefreshIndicator(
                  onRefresh: _loadFavorites,
                  child: ListView.builder(
                    itemCount: _articles.length,
                    itemBuilder: (context, index) {
                      final article = _articles[index];
                      return Dismissible(
                        key: ValueKey(article.id ?? index),
                        direction: DismissDirection.endToStart,
                        background: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 16), child: const Icon(Icons.delete, color: Colors.white)),
                        onDismissed: (_) async {
                          if (article.id != null) await _db.toggleRssFavorite(article.id!, 0);
                          _loadFavorites();
                        },
                        child: ListTile(
                          title: Text(article.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            if (article.description != null)
                              Text(article.description!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                            const SizedBox(height: 4),
                            Text(article.sourceName ?? '', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.primary)),
                          ]),
                          trailing: IconButton(
                            icon: const Icon(Icons.star, color: Colors.amber),
                            onPressed: () async {
                              if (article.id != null) await _db.toggleRssFavorite(article.id!, 0);
                              _loadFavorites();
                            },
                          ),
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RssReadScreen(article: article))),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  void _showClearDialog() {
    showDialog(context: context, builder: (context) => AlertDialog(
      title: const Text('清空收藏'),
      content: const Text('确定清空所有收藏文章吗？'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: () async {
          for (final a in _articles) {
            if (a.id != null) await _db.toggleRssFavorite(a.id!, 0);
          }
          if (mounted) { Navigator.pop(context); _loadFavorites(); }
        }, child: const Text('确定')),
      ],
    ));
  }
}
