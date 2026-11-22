import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/search_book.dart';
import 'package:legado_md3/data/entities/search_book_table.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/di/book_provider.dart';
import 'package:legado_md3/help/source/source_engine.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';

/// 换封面：
/// 支持自定义 URL，以及「按书名从已启用书源搜索封面」的网格选择。
/// 搜索结果按书名/作者校验并落库缓存，二次进入可直接展示已缓存封面；
/// 搜索按钮为「搜索 / 停止 / 继续」三态，可随时中断并发检索。
class ChangeCoverScreen extends StatefulWidget {
  final Book book;
  const ChangeCoverScreen({super.key, required this.book});

  @override
  State<ChangeCoverScreen> createState() => _ChangeCoverScreenState();
}

class _ChangeCoverScreenState extends State<ChangeCoverScreen> {
  final DatabaseService _db = DatabaseService();
  final TextEditingController _urlController = TextEditingController();
  String? _previewUrl;
  final List<String> _sourceCovers = [];
  bool _coverSearched = false;
  /// 0=搜索 1=停止 2=继续
  int _coverSearchState = 0;
  bool _coverCancelled = false;
  int _coverGeneration = 0;

  @override
  void initState() {
    super.initState();
    final cur = widget.book.customCoverUrl ?? widget.book.coverUrl ?? '';
    _urlController.text = cur;
    _previewUrl = cur.isEmpty ? null : cur;
    _loadCachedCovers();
  }

  @override
  void dispose() {
    _coverCancelled = true;
    _coverGeneration++;
    _urlController.dispose();
    super.dispose();
  }

  /// 只接受 http(s) 图片，排除占位图服务返回的随机假图与内联 data URI。
  bool _isValidCoverUrl(String url) {
    final u = url.trim().toLowerCase();
    if (!u.startsWith('http://') && !u.startsWith('https://')) return false;
    const fakeHosts = <String>[
      'picsum.photos',
      'placehold.co',
      'via.placeholder.com',
      'placeholder.com',
      'dummyimage.com',
      'fakeimg.pl',
    ];
    for (final host in fakeHosts) {
      if (u.contains(host)) return false;
    }
    return true;
  }

  /// 封面结果必须与当前书的书名一致；来源省略作者时按书名匹配即可。
  bool _matchesBook(SearchBook b) {
    if (b.name.trim() != widget.book.name.trim()) return false;
    final author = b.author.trim();
    return author.isEmpty || author == widget.book.author.trim();
  }

  Future<void> _cacheCover(SearchBook b) async {
    try {
      await _db.insertSearchBook(SearchBookTable(
        bookUrl: b.bookUrl ??
            '${widget.book.name}|${b.author}|${b.origin ?? ''}',
        name: b.name,
        author: b.author,
        origin: b.origin ?? '',
        originName: b.originName,
        coverUrl: b.coverUrl,
        intro: b.intro,
        latestChapterTitle: b.lastChapter,
        tocUrl: b.noteUrl ?? '',
        originOrder: b.originOrder ?? 0,
      ));
    } catch (_) {}
  }

  Future<void> _loadCachedCovers() async {
    try {
      final cached = await _db.getSearchBooks(
          name: widget.book.name, author: widget.book.author);
      final urls = <String>{};
      for (final s in cached) {
        final url = s.coverUrl ?? '';
        if (_isValidCoverUrl(url)) urls.add(url);
      }
      if (!mounted) return;
      setState(() {
        _sourceCovers
          ..clear()
          ..addAll(urls);
        _coverSearched = urls.isNotEmpty;
      });
    } catch (_) {}
  }

  /// 并发在已启用书源中按书名检索封面，校验后去重、落库缓存（当前源优先）。
  Future<List<String>> _searchCovers(int gen) async {
    try {
      final sources = await _db.getAllSources(enabled: true);
      sources.sort((a, b) {
        final ac = a.bookSourceUrl == widget.book.origin ? 0 : 1;
        final bc = b.bookSourceUrl == widget.book.origin ? 0 : 1;
        return ac - bc;
      });
      final use = sources.take(8).toList();
      final engine = BookSourceEngine();
      final covers = <String>{};
      await Future.wait(use.map((source) async {
        try {
          final list = await engine.search(source, widget.book.name).timeout(
                const Duration(seconds: 10),
                onTimeout: () => <SearchBook>[],
              );
          if (_coverCancelled || gen != _coverGeneration) return;
          for (final b in list) {
            if (_coverCancelled || gen != _coverGeneration) return;
            final url = b.coverUrl ?? '';
            if (!_isValidCoverUrl(url) || !_matchesBook(b)) continue;
            covers.add(url);
            await _cacheCover(b);
          }
        } catch (_) {}
      }));
      // 合入已缓存封面，保证「继续搜索」不会丢失先前结果。
      final cached = await _db.getSearchBooks(
          name: widget.book.name, author: widget.book.author);
      for (final s in cached) {
        final url = s.coverUrl ?? '';
        if (_isValidCoverUrl(url)) covers.add(url);
      }
      return covers.toList();
    } catch (_) {
      return <String>[];
    }
  }

  Future<void> _startOrStopCoverSearch() async {
    if (_coverSearchState == 1) {
      // 停止：置取消标记，让在途 worker 提前收工，并切到「继续」态。
      _coverCancelled = true;
      _coverGeneration++;
      if (mounted) setState(() => _coverSearchState = 2);
      return;
    }
    _coverGeneration++;
    final gen = _coverGeneration;
    _coverCancelled = false;
    if (mounted) setState(() => _coverSearchState = 1);
    try {
      final covers = await _searchCovers(gen);
      if (!mounted || gen != _coverGeneration) return;
      setState(() {
        _sourceCovers
          ..clear()
          ..addAll(covers);
        _coverSearched = true;
        _coverSearchState = 2;
      });
    } catch (_) {
      if (!mounted || gen != _coverGeneration) return;
      setState(() {
        _sourceCovers.clear();
        _coverSearched = true;
        _coverSearchState = 2;
      });
    }
  }

  Future<void> _saveCover() async {
    // 就地修改，避免重建 Book 丢失阅读进度/目录地址/分组等字段。
    final url = _urlController.text.trim();
    widget.book.customCoverUrl = url.isEmpty ? null : url;
    await _db.updateBook(widget.book);
    if (mounted && context.mounted) await context.read<BookProvider>().loadBooks();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(url.isEmpty ? '已恢复书源默认封面' : '封面已更新')),
      );
      Navigator.pop(context, true);
    }
  }

  void _setUrl(String? url) {
    _urlController.text = url ?? '';
    setState(() => _previewUrl = (url != null && url.isNotEmpty) ? url : null);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('换封面 - ${widget.book.name}')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.l),
        children: [
          Center(
            child: Container(
              width: 150,
              height: 200,
              decoration: BoxDecoration(
                borderRadius: AppRadius.mAll,
                color: cs.surfaceContainerHighest,
              ),
              child: _previewUrl != null && _previewUrl!.isNotEmpty
                  ? ClipRRect(
                      borderRadius: AppRadius.mAll,
                      child: Image.network(_previewUrl!, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(Icons.broken_image,
                              size: 48, color: cs.onSurfaceVariant)))
                  : Icon(Icons.book, size: 48, color: cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: '封面URL',
              hintText: '输入图片URL',
            ),
            onChanged: (v) => setState(() => _previewUrl = v.isEmpty ? null : v),
          ),
          const SizedBox(height: AppSpacing.l),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _setUrl(null),
                child: const Text('恢复默认封面'),
              ),
            ),
            const SizedBox(width: AppSpacing.l),
            Expanded(
              child: FilledButton(onPressed: _saveCover, child: const Text('保存')),
            ),
          ]),
          const SizedBox(height: AppSpacing.l),
          const AppSectionHeader('从书源搜索封面'),
          Row(
            children: [
              Expanded(
                child: Text('按《${widget.book.name}》在已启用书源中检索封面',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ),
              FilledButton.icon(
                onPressed: _startOrStopCoverSearch,
                icon: Icon(
                  _coverSearchState == 1
                      ? Icons.stop
                      : _coverSearchState == 2
                          ? Icons.refresh
                          : Icons.image_search_outlined,
                  size: 18,
                ),
                label: Text(_coverSearchState == 1
                    ? '停止'
                    : _coverSearchState == 2
                        ? '继续搜索'
                        : '搜索'),
              ),
            ],
          ),
          if (_coverSearchState == 1)
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.s),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          const SizedBox(height: AppSpacing.m),
          if (_coverSearched && _sourceCovers.isEmpty)
            const AppEmptyState(
              icon: Icons.image_not_supported_outlined,
              title: '未搜索到封面',
              message: '可尝试手动输入封面 URL',
            )
          else if (_sourceCovers.isNotEmpty)
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 0.7,
              ),
              itemCount: _sourceCovers.length,
              itemBuilder: (_, i) => _buildCoverChoice(_sourceCovers[i]),
            ),
          const SizedBox(height: AppSpacing.l),
        ],
      ),
    );
  }

  Widget _buildCoverChoice(String url) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => _setUrl(url),
      child: Container(
        width: 60,
        height: 80,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: _previewUrl == url ? cs.primary : cs.outlineVariant,
            width: _previewUrl == url ? 2 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.network(url, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  Icon(Icons.broken_image, size: 20, color: cs.onSurfaceVariant)),
        ),
      ),
    );
  }
}
