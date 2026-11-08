import 'package:flutter/material.dart';

import 'package:legado_md3/data/model/rss_article.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';

/// RSS 文章内搜索（对齐 legado `rss_articles.xml` 的 `menu_search`）。
///
/// 对当前订阅源已加载的文章按关键词做本地过滤（标题 / 简介 / 作者 / 来源），
/// 结果可点击直接打开文章；这是真实作用于文章列表的检索，而非占位入口。
Future<void> showRssArticleSearchSheet(
  BuildContext context, {
  required List<RssArticle> articles,
  required ValueChanged<RssArticle> onOpen,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _RssArticleSearchSheet(articles: articles, onOpen: onOpen),
  );
}

class _RssArticleSearchSheet extends StatefulWidget {
  const _RssArticleSearchSheet({required this.articles, required this.onOpen});

  final List<RssArticle> articles;
  final ValueChanged<RssArticle> onOpen;

  @override
  State<_RssArticleSearchSheet> createState() => _RssArticleSearchSheetState();
}

class _RssArticleSearchSheetState extends State<_RssArticleSearchSheet> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<RssArticle> get _results {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return const <RssArticle>[];
    return widget.articles.where((a) {
      return a.title.toLowerCase().contains(q) ||
          (a.description ?? '').toLowerCase().contains(q) ||
          (a.author ?? '').toLowerCase().contains(q) ||
          (a.sourceName ?? '').toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final results = _results;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: '搜索标题 / 简介 / 作者 / 来源',
                    prefixIcon: const Icon(Icons.search_outlined),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '清除',
                            icon: const Icon(Icons.clear_outlined),
                            onPressed: () {
                              _controller.clear();
                              setState(() => _query = '');
                            },
                          ),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text('匹配 ${results.length} 篇',
                        style: TextStyle(fontSize: 12, color: cs.primary)),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: _query.trim().isEmpty
                    ? const AppEmptyState(
                        icon: Icons.search_outlined,
                        title: '输入关键词搜索当前文章',
                      )
                    : results.isEmpty
                        ? const AppEmptyState(
                            icon: Icons.search_off_outlined,
                            title: '没有匹配的文章',
                          )
                        : ListView.separated(
                            itemCount: results.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final a = results[i];
                              return ListTile(
                                leading: const Icon(Icons.article_outlined),
                                title: Text(a.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                subtitle: Text(
                                  (a.description ?? a.sourceName ?? '')
                                      .replaceAll('\n', ' '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11),
                                ),
                                onTap: () {
                                  Navigator.pop(context);
                                  widget.onOpen(a);
                                },
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
