import 'dart:async';

import 'package:flutter/material.dart';

import 'package:legado_md3/data/model/rss_article.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';

/// RSS 文章搜索。
///
/// 本地模式：对当前源已加载的文章按关键词过滤（标题 / 简介 / 作者 / 来源）。
/// 网络模式：源配置了 searchUrl 时按 {{key}}/{{page}} 发起真实网络检索并分页，
/// 两种模式的结果都可点击直接打开文章。
Future<void> showRssArticleSearchSheet(
  BuildContext context, {
  required List<RssArticle> articles,
  required ValueChanged<RssArticle> onOpen,
  Future<List<RssArticle>> Function(String key, int page)? networkSearch,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _RssArticleSearchSheet(
      articles: articles,
      onOpen: onOpen,
      networkSearch: networkSearch,
    ),
  );
}

class _RssArticleSearchSheet extends StatefulWidget {
  const _RssArticleSearchSheet({
    required this.articles,
    required this.onOpen,
    this.networkSearch,
  });

  final List<RssArticle> articles;
  final ValueChanged<RssArticle> onOpen;
  final Future<List<RssArticle>> Function(String key, int page)? networkSearch;

  @override
  State<_RssArticleSearchSheet> createState() => _RssArticleSearchSheetState();
}

class _RssArticleSearchSheetState extends State<_RssArticleSearchSheet> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';
  Timer? _debounce;
  bool _network = false;
  int _page = 1;
  List<RssArticle> _netResults = [];
  bool _netLoading = false;
  String? _netError;

  @override
  void initState() {
    super.initState();
    _network = widget.networkSearch != null;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  List<RssArticle> get _localResults {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return const <RssArticle>[];
    return widget.articles.where((a) {
      return a.title.toLowerCase().contains(q) ||
          (a.description ?? '').toLowerCase().contains(q) ||
          (a.author ?? '').toLowerCase().contains(q) ||
          (a.sourceName ?? '').toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _runNetwork({required int page}) async {
    final q = _query.trim();
    final search = widget.networkSearch;
    if (q.isEmpty || search == null) return;
    setState(() {
      _netLoading = true;
      _netError = null;
    });
    try {
      final list = await search(q, page);
      if (!mounted) return;
      setState(() {
        _page = page;
        if (page == 1) {
          _netResults = list;
        } else {
          final seen = _netResults.map((e) => e.link).toSet();
          _netResults = [
            ..._netResults,
            ...list.where((e) => !seen.contains(e.link)),
          ];
        }
        _netLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _netError = '$e';
        _netLoading = false;
      });
    }
  }

  void _onQueryChanged(String v) {
    setState(() => _query = v);
    _debounce?.cancel();
    if (!_network || v.trim().isEmpty) return;
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _runNetwork(page: 1);
    });
  }

  void _switchMode(bool network) {
    setState(() {
      _network = network;
      _netResults = [];
      _netError = null;
      _page = 1;
    });
    if (network && _query.trim().isNotEmpty) _runNetwork(page: 1);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final results = _network ? _netResults : _localResults;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.l, AppSpacing.xs,
                    AppSpacing.l, AppSpacing.s),
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: _network ? '输入关键词网络搜索' : '搜索标题 / 简介 / 作者 / 来源',
                    prefixIcon: const Icon(Icons.search_outlined),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '清除',
                            icon: const Icon(Icons.clear_outlined),
                            onPressed: () {
                              _controller.clear();
                              setState(() {
                                _query = '';
                                _netResults = [];
                                _netError = null;
                              });
                            },
                          ),
                    border: const OutlineInputBorder(
                        borderRadius: AppRadius.mAll),
                    isDense: true,
                  ),
                  onChanged: _onQueryChanged,
                ),
              ),
              if (widget.networkSearch != null)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.l),
                  child: Row(children: [
                    ChoiceChip(
                      label: const Text('本地'),
                      selected: !_network,
                      onSelected: (_) => _switchMode(false),
                    ),
                    const SizedBox(width: AppSpacing.s),
                    ChoiceChip(
                      label: const Text('网络'),
                      selected: _network,
                      onSelected: (_) => _switchMode(true),
                    ),
                  ]),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
                child: Row(
                  children: [
                    Text('匹配 ${results.length} 篇',
                        style: TextStyle(fontSize: 12, color: cs.primary)),
                    if (_netLoading) ...[
                      const SizedBox(width: AppSpacing.s),
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                  ],
                ),
              ),
              if (_netError != null)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.l),
                  child: Text('搜索失败: $_netError',
                      style: TextStyle(fontSize: 11, color: cs.error)),
                ),
              const SizedBox(height: AppSpacing.xs),
              Expanded(
                child: _query.trim().isEmpty
                    ? const AppEmptyState(
                        icon: Icons.search_outlined,
                        title: '输入关键词搜索',
                      )
                    : results.isEmpty && !_netLoading
                        ? const AppEmptyState(
                            icon: Icons.search_off_outlined,
                            title: '没有匹配的文章',
                          )
                        : ListView.separated(
                            itemCount: results.length + (_network ? 1 : 0),
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, i) {
                              if (_network && i == results.length) {
                                return Padding(
                                  padding: const EdgeInsets.all(AppSpacing.m),
                                  child: OutlinedButton.icon(
                                    onPressed: _netLoading
                                        ? null
                                        : () => _runNetwork(page: _page + 1),
                                    icon: const Icon(Icons.expand_more),
                                    label: const Text('加载更多'),
                                  ),
                                );
                              }
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
