import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/data/model/search_book.dart';
import 'package:legado_md3/help/source/source_engine.dart';
import 'package:legado_md3/di/book_provider.dart';
import 'package:legado_md3/ui/book/detail/book_detail_screen.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';

/// 发现书籍列表页：给定书源与发现 URL，拉取并分页展示书籍。
/// 首页模块卡片、分类入口等都可跳转到这里。
class ExploreBooksScreen extends StatefulWidget {
  final BookSource source;
  final String exploreUrl;
  final String title;

  const ExploreBooksScreen({
    super.key,
    required this.source,
    required this.exploreUrl,
    this.title = '发现',
  });

  @override
  State<ExploreBooksScreen> createState() => _ExploreBooksScreenState();
}

class _ExploreBooksScreenState extends State<ExploreBooksScreen> {
  final BookSourceEngine _engine = BookSourceEngine();
  final ScrollController _scroll = ScrollController();
  final TextEditingController _pageCtl = TextEditingController(text: '1');
  final List<SearchBook> _books = [];
  int _page = 1;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  /// 发现 URL 含 {{page}} / {{page-1}} 才支持分页。
  bool get _paginatable => widget.exploreUrl.contains('{{page');

  String _applyPage(String url, int page) {
    var u = url.replaceAll('{{page-1}}', '${page - 1}');
    u = u.replaceAll('{{ page - 1 }}', '${page - 1}');
    u = u.replaceAll('{{page}}', '$page');
    u = u.replaceAll('{{ page }}', '$page');
    return u;
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 300) {
        _loadMore();
      }
    });
    _fetch(append: false);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _pageCtl.dispose();
    super.dispose();
  }

  Future<void> _fetch({required bool append}) async {
    if (append) {
      setState(() => _loadingMore = true);
    } else {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final list = await _engine.exploreByUrl(
          widget.source, _applyPage(widget.exploreUrl, _page));
      if (!mounted) return;
      setState(() {
        if (append) {
          _books.addAll(list);
          if (list.isEmpty) {
            _hasMore = false;
            _page--;
          }
        } else {
          _books
            ..clear()
            ..addAll(list);
        }
        _loading = false;
        _loadingMore = false;
        _pageCtl.text = '$_page';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = '$e';
        if (append) {
          _hasMore = false;
          _page--;
        }
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    if (!_paginatable) {
      _hasMore = false;
      return;
    }
    _page++;
    await _fetch(append: true);
  }

  /// 页码跳转：替换当前列表为指定页（append:false），并同步输入框。
  Future<void> _jumpToPage(int page) async {
    if (!_paginatable) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('该发现分类 URL 未包含 {{page}}，不支持分页')));
      }
      return;
    }
    if (_loading || _loadingMore) return;
    final target = page < 1 ? 1 : page;
    setState(() {
      _page = target;
      _pageCtl.text = '$target';
      _hasMore = true;
    });
    await _fetch(append: false);
  }

  Widget _buildPageBar() {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.m, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: '上一页',
            onPressed: (_page > 1 && _paginatable)
                ? () => _jumpToPage(_page - 1)
                : null,
          ),
          Text('第 $_page 页', style: const TextStyle(fontSize: 12)),
          const SizedBox(width: AppSpacing.s),
          SizedBox(
            width: 56,
            height: 34,
            child: TextField(
              controller: _pageCtl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.all(AppSpacing.xs),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s),
          FilledButton.tonal(
            onPressed: () =>
                _jumpToPage(int.tryParse(_pageCtl.text.trim()) ?? _page),
            child: const Text('跳转', style: TextStyle(fontSize: 12)),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: '下一页',
            onPressed: _paginatable ? () => _jumpToPage(_page + 1) : null,
          ),
          if (!_paginatable)
            const Expanded(
              child: Text('该分类不支持分页',
                  textAlign: TextAlign.end, style: TextStyle(fontSize: 11)),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh_outlined),
              tooltip: '刷新',
              onPressed: () {
                _page = 1;
                _pageCtl.text = '1';
                _fetch(append: false);
              }),
        ],
      ),
      body: Column(
        children: [
          _buildPageBar(),
          Expanded(
            child: _loading
                ? const AppLoadingIndicator()
                : _error != null && _books.isEmpty
                    ? AppErrorState(
                        message: '$_error',
                        onRetry: () {
                          _page = 1;
                          _fetch(append: false);
                        },
                      )
                    : _books.isEmpty
                        ? const AppEmptyState(
                            icon: Icons.menu_book_outlined,
                            title: '暂无书籍',
                            message: '该发现分类暂时没有内容，可下拉刷新或返回换一个分类',
                          )
                        : ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.all(AppSpacing.m),
                            itemCount: _books.length + (_loadingMore ? 1 : 0),
                            itemBuilder: (context, i) {
                              if (i >= _books.length) {
                                return const Padding(
                                    padding: EdgeInsets.all(AppSpacing.l),
                                    child: AppLoadingIndicator());
                              }
                              final book = _books[i];
                              return ListTile(
                                leading: const Icon(Icons.menu_book),
                                title: Text(book.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                subtitle: Text(book.author,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                trailing: FilledButton.tonal(
                                  onPressed: () async {
                                    await context
                                        .read<BookProvider>()
                                        .addBook(book.toBook());
                                    if (mounted && context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                              content:
                                                  Text('已添加《${book.name}》')));
                                    }
                                  },
                                  child: const Text('加入'),
                                ),
                                onTap: () {
                                  // 点击进详情；是否加入书架由详情或「加入」按钮决定，
                                  // 避免误触直接改书架并打开阅读器。
                                  final detailBook = book.toBook();
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          BookDetailScreen(book: detailBook),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
