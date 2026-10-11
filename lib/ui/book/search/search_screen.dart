import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/data/model/search_book.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/ui/book/detail/change_source_screen.dart';
import 'package:legado_md3/di/book_provider.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/help/source/source_engine.dart';
import 'package:legado_md3/ui/book/detail/book_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final DatabaseService _db = DatabaseService();
  final BookSourceEngine _engine = BookSourceEngine();
  List<SearchBook> _results = [];
  List<String> _searchHistory = [];
  bool _isSearching = false;
  String? _searchKeyword;
  int _searchedSources = 0;
  int _totalSources = 0;
  Set<String> _selectedSources = {};
  bool _groupBySource = false;

  static const List<String> _hotKeywords = ['斗破苍穹', '凡人修仙传', '诡秘之主', '大奉打更人', '夜的命名术', '灵境行者'];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _searchHistory = prefs.getStringList('search_history') ?? []);
  }

  Future<void> _saveHistory(String keyword) async {
    final prefs = await SharedPreferences.getInstance();
    _searchHistory.remove(keyword);
    _searchHistory.insert(0, keyword);
    if (_searchHistory.length > 20) _searchHistory = _searchHistory.sublist(0, 20);
    await prefs.setStringList('search_history', _searchHistory);
    setState(() {});
  }

  Future<void> _clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('search_history');
    setState(() => _searchHistory = []);
  }

  Future<void> _search(String keyword) async {
    if (keyword.trim().isEmpty) return;
    _controller.text = keyword;
    _searchKeyword = keyword;
    _saveHistory(keyword);
    setState(() {
      _isSearching = true;
      _results = [];
      _searchedSources = 0;
    });

    final sources = await _db.getAllSources(enabled: true);
    if (sources.isEmpty) {
      if (mounted) {
        setState(() => _isSearching = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('没有启用的书源，请先在「书源管理」中导入并启用书源')));
      }
      return;
    }
    _totalSources = sources.length;
    final selectedSources = _selectedSources.isEmpty
        ? sources
        : sources.where((s) => _selectedSources.contains(s.bookSourceUrl)).toList();

    // 并发池搜索所有启用书源（限制同时 8 个，避免源过多时连接耗尽），结果到达即刷新
    const concurrency = 8;
    int cursor = 0;
    Future<void> worker() async {
      while (true) {
        final i = cursor++;
        if (i >= selectedSources.length) return;
        final source = selectedSources[i];
        try {
          final results = await _engine.search(source, keyword).timeout(const Duration(seconds: 15), onTimeout: () => []);
          if (mounted && results.isNotEmpty) {
            setState(() => _results.addAll(results));
          }
        } catch (_) {}
        if (mounted) setState(() => _searchedSources++);
      }
    }
    await Future.wait(List.generate(concurrency.clamp(1, selectedSources.isEmpty ? 1 : selectedSources.length), (_) => worker()));

    if (mounted) setState(() => _isSearching = false);
  }

  Future<void> _addToShelf(SearchBook book) async {
    final provider = Provider.of<BookProvider>(context, listen: false);
    final newBook = Book(
      name: book.name,
      author: book.author,
      coverUrl: book.coverUrl,
      intro: book.intro,
      kind: book.kind,
      origin: book.origin,
      originName: book.originName,
      noteUrl: book.noteUrl,
      bookUrl: book.bookUrl,
      lastChapter: book.lastChapter,
      local: false,
      lastCheckTime: DateTime.now().millisecondsSinceEpoch,
    );
    await _db.insertBook(newBook);
    await provider.loadBooks();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已添加《${book.name}》到书架')));
  }

  void _showSourceFilter() {
    showModalBottomSheet(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(padding: EdgeInsets.all(16), child: Text('选择书源', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
              Expanded(
                child: FutureBuilder(
                  future: _db.getAllSources(enabled: true),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                    final sources = snapshot.data!;
                    return ListView.builder(
                      itemCount: sources.length,
                      itemBuilder: (context, index) {
                        final source = sources[index];
                        final selected = _selectedSources.contains(source.bookSourceUrl);
                        return CheckboxListTile(
                          title: Text(source.bookSourceName, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(source.bookSourceGroup ?? '默认', style: const TextStyle(fontSize: 11)),
                          value: selected,
                          onChanged: (v) => setSheetState(() {
                            if (v == true) _selectedSources.add(source.bookSourceUrl);
                            else _selectedSources.remove(source.bookSourceUrl);
                          }),
                        );
                      },
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    TextButton(onPressed: () async {
                      final all = await _db.getAllSources(enabled: true);
                      setSheetState(() {
                        _selectedSources.addAll(all.map((s) => s.bookSourceUrl));
                      });
                    }, child: const Text('全选')),
                    TextButton(onPressed: () => setSheetState(() => _selectedSources.clear()), child: const Text('重置')),
                    const Spacer(),
                    FilledButton(onPressed: () => Navigator.pop(context), child: Text(_selectedSources.isEmpty ? '确定(全部源)' : '确定(${_selectedSources.length})')),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: '搜索书籍...',
            border: InputBorder.none,
            suffixIcon: _controller.text.isNotEmpty
                ? IconButton(icon: const Icon(Icons.clear), onPressed: () { _controller.clear(); setState(() { _results = []; _searchKeyword = null; }); })
                : null,
          ),
          onSubmitted: _search,
        ),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: () => _search(_controller.text)),
          IconButton(icon: const Icon(Icons.filter_list), onPressed: _showSourceFilter),
        ],
      ),
      body: _searchKeyword == null
          ? _buildSearchHistory()
          : _buildSearchResults(),
    );
  }

  Widget _buildSearchHistory() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_searchHistory.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('搜索历史', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              TextButton(onPressed: _clearHistory, child: const Text('清空')),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _searchHistory.map((kw) => ActionChip(label: Text(kw), onPressed: () => _search(kw))).toList(),
          ),
          const SizedBox(height: 24),
        ],
        const Text('热门搜索', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _hotKeywords.asMap().entries.map((e) => ActionChip(
            label: Text('${e.key + 1}. ${e.value}'),
            onPressed: () => _search(e.value),
          )).toList(),
        ),
      ],
    );
  }

  Widget _buildSearchResults() {
    if (_isSearching && _results.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text('正在搜索 ($_searchedSources/$_totalSources)...'),
      ]));
    }
    if (_results.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
        const SizedBox(height: 16),
        Text('未找到"$_searchKeyword"相关结果', style: TextStyle(color: Colors.grey[600])),
      ]));
    }
    return Column(
      children: [
        if (_isSearching) LinearProgressIndicator(value: _totalSources > 0 ? _searchedSources / _totalSources : 0),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text('共找到 ${_results.length} 条', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const Spacer(),
              Text('$_searchedSources/$_totalSources 源', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                padding: EdgeInsets.zero,
                icon: Icon(_groupBySource ? Icons.view_agenda : Icons.sort, color: Theme.of(context).colorScheme.primary),
                tooltip: _groupBySource ? '按时间排序' : '按书源分组',
                onPressed: () => setState(() => _groupBySource = !_groupBySource),
              ),
            ],
          ),
        ),
        Expanded(child: _groupBySource ? _buildGroupedList() : _buildFlatList()),
      ],
    );
  }

  Widget _buildFlatList() => ListView.separated(
    itemCount: _results.length,
    separatorBuilder: (_, __) => const Divider(height: 1),
    itemBuilder: (c, i) => _buildResultTile(_results[i]),
  );

  Widget _buildGroupedList() {
    final groups = groupBy(_results, (SearchBook b) => b.originName ?? b.origin ?? '未知来源');
    final entries = groups.entries.toList();
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (c, gi) {
        final e = entries[gi];
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: double.infinity, color: Theme.of(c).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text('${e.key} (${e.value.length})', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Theme.of(c).colorScheme.primary)),
          ),
          ...e.value.map(_buildResultTile),
          const Divider(height: 1),
        ]);
      },
    );
  }

  Widget _buildResultTile(SearchBook book) => ListTile(
    leading: book.coverUrl != null && book.coverUrl!.isNotEmpty
        ? ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.network(book.coverUrl!, width: 50, height: 70, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _buildDefaultCover(book.name)))
        : _buildDefaultCover(book.name),
    title: Text(book.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500)),
    subtitle: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${book.author} · ${book.kind ?? ''}', maxLines: 1, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 2),
        Text(book.lastChapter ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.primary)),
        if ((book.originName ?? '').isNotEmpty) Text('来源: ${book.originName}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    ),
    trailing: IconButton(icon: const Icon(Icons.add), onPressed: () => _addToShelf(book), tooltip: '加入书架'),
    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BookDetailScreen(book: Book(name: book.name, author: book.author, coverUrl: book.coverUrl, intro: book.intro, kind: book.kind, origin: book.origin, bookUrl: book.bookUrl, noteUrl: book.noteUrl, lastChapter: book.lastChapter, local: false)))),
    onLongPress: () => _showResultMenu(book),
  );

  Widget _buildDefaultCover(String name) {
    final colors = [Colors.blueGrey, Colors.brown, Colors.teal, Colors.indigo, Colors.deepOrange, Colors.purple];
    final color = colors[name.hashCode.abs() % colors.length];
    return Container(width: 50, height: 70, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)), child: Center(child: Padding(padding: const EdgeInsets.all(4), child: Text(name, maxLines: 3, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)))));
  }

  void _showResultMenu(SearchBook book) {
    showModalBottomSheet(context: context, builder: (context) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(
        leading: const Icon(Icons.info_outline),
        title: const Text('查看详情'),
        onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => BookDetailScreen(book: Book(name: book.name, author: book.author, coverUrl: book.coverUrl, intro: book.intro, kind: book.kind, origin: book.origin, bookUrl: book.bookUrl, noteUrl: book.noteUrl, lastChapter: book.lastChapter, local: false)))); },
      ),
      ListTile(
        leading: const Icon(Icons.add),
        title: const Text('加入书架'),
        onTap: () { Navigator.pop(context); _addToShelf(book); },
      ),
      ListTile(
        leading: const Icon(Icons.swap_horiz),
        title: const Text('换源'),
        onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => ChangeSourceScreen(book: Book(name: book.name, author: book.author, coverUrl: book.coverUrl, intro: book.intro, kind: book.kind, origin: book.origin, bookUrl: book.bookUrl, noteUrl: book.noteUrl, lastChapter: book.lastChapter, local: false)))); },
      ),
      ListTile(
        leading: const Icon(Icons.content_copy),
        title: const Text('复制书名'),
        onTap: () async { Navigator.pop(context); await Clipboard.setData(ClipboardData(text: book.name)); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制'))); },
      ),
      ListTile(
        leading: const Icon(Icons.share),
        title: const Text('分享'),
        onTap: () { Navigator.pop(context); Share.share('《${book.name}》 - ${book.author}'); },
      ),
    ])));
  }
}
