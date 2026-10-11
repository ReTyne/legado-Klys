import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/data/model/search_book.dart';
import 'package:legado_md3/help/source/source_engine.dart';
import 'package:legado_md3/di/book_provider.dart';
import 'package:legado_md3/ui/book/read/reading_screen.dart';

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
  final List<SearchBook> _books = [];
  int _page = 1;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

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
    super.dispose();
  }

  Future<void> _fetch({required bool append}) async {
    if (append) {
      setState(() => _loadingMore = true);
    } else {
      setState(() { _loading = true; _error = null; });
    }
    try {
      final list = await _engine.exploreByUrl(widget.source, _applyPage(widget.exploreUrl, _page));
      if (!mounted) return;
      setState(() {
        if (append) {
          _books.addAll(list);
          if (list.isEmpty) { _hasMore = false; _page--; }
        } else {
          _books
            ..clear()
            ..addAll(list);
        }
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _loadingMore = false; _error = '$e'; if (append) { _hasMore = false; _page--; } });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    if (!widget.exploreUrl.contains('{{page')) { _hasMore = false; return; }
    _page++;
    await _fetch(append: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: () { _page = 1; _fetch(append: false); })],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _books.isEmpty
              ? Center(child: Text('加载失败：$_error'))
              : _books.isEmpty
                  ? const Center(child: Text('暂无书籍'))
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(12),
                      itemCount: _books.length + (_loadingMore ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (i >= _books.length) {
                          return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
                        }
                        final book = _books[i];
                        return ListTile(
                          leading: const Icon(Icons.menu_book),
                          title: Text(book.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(book.author, maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: FilledButton.tonal(
                            onPressed: () async {
                              await context.read<BookProvider>().addBook(book.toBook());
                              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已添加《${book.name}》')));
                            },
                            child: const Text('加入'),
                          ),
                          onTap: () async {
                            await context.read<BookProvider>().addBook(book.toBook());
                            if (mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => ReadingScreen(book: book.toBook())));
                          },
                        );
                      },
                    ),
    );
  }
}
