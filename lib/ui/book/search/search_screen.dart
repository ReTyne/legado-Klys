import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/constant/app_theme.dart';
import 'package:legado_md3/data/model/search_book.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/ui/book/detail/change_source_screen.dart';
import 'package:legado_md3/di/book_provider.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/help/config/app_config.dart';
import 'package:legado_md3/help/net/network_monitor.dart';
import 'package:legado_md3/help/source/search_scope.dart';
import 'package:legado_md3/help/source/source_engine.dart';
import 'package:legado_md3/ui/book/detail/book_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  /// 外部入口预设关键词（书源 JS java.searchBook(key) 跳转时携带，进入即搜索）
  final String? initialKeyword;

  /// 初始搜索范围（单书源 `名称::url`，来自书源编辑页的「保存并搜索」等入口；
  /// 对齐 legado searchScope：「分组::书源Url」或书源 Url，命中后仅搜索该书源）
  final String? searchScope;

  const SearchScreen({super.key, this.initialKeyword, this.searchScope});

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
  bool _groupBySource = false;

  /// 搜索范围（对齐 legado-E SearchScope：全部 / 分组多选 / 单书源）
  late final SearchScope _scope = SearchScope(
      widget.searchScope ?? AppPrefs.searchScope);

  /// 搜索范围：0=全部 1=书名 2=作者（对齐 legado-E SearchScope）
  int _searchScope = 0;

  /// 精准搜索：结果的书名或作者需完整包含关键词
  bool _precision = false;

  static const List<String> _hotKeywords = ['斗破苍穹', '凡人修仙传', '诡秘之主', '大奉打更人', '夜的命名术', '灵境行者'];

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _loadScope();
    _initFromIntent();
  }

  /// 处理外部入口（java.searchBook）：范围已由 [_scope] 构造时解析
  /// （`名称::url` 单书源形态），此处仅负责携带关键词进入即搜索。
  Future<void> _initFromIntent() async {
    final kw = widget.initialKeyword?.trim() ?? '';
    if (kw.isNotEmpty) {
      await _search(kw);
    }
  }

  Future<void> _loadScope() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt('search_scope') ?? 0;
    if (mounted) setState(() => _searchScope = v >= 0 && v <= 2 ? v : 0);
  }

  Future<void> _setScope(int scope) async {
    setState(() => _searchScope = scope);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('search_scope', scope);
  }

  /// 应用范围 + 精准过滤后的结果（原始结果保留在 [_results]，切换时无需重新搜索）
  List<SearchBook> get _displayResults {
    if (_searchScope == 0 && !_precision) return _results;
    final kw = (_searchKeyword ?? '').trim();
    return _results.where((b) {
      if (_precision && kw.isNotEmpty) {
        final hitName = b.name.contains(kw);
        final hitAuthor = b.author.contains(kw);
        if (!hitName && !hitAuthor) return false;
        // 范围再叠加
        if (_searchScope == 1) return hitName;
        if (_searchScope == 2) return hitAuthor;
        return true;
      }
      switch (_searchScope) {
        case 1:
          return kw.isEmpty || b.name.contains(kw);
        case 2:
          return kw.isEmpty || b.author.contains(kw);
        default:
          return true;
      }
    }).toList();
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
    // 离线快速失败（E: NetworkUtils.isAvailable 守卫），避免逐源干等超时
    if (!await NetworkMonitor.instance.isOnline) {
      if (mounted) {
        setState(() => _isSearching = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('网络不可用，请检查网络后重试')));
      }
      return;
    }
    _controller.text = keyword;
    _searchKeyword = keyword;
    _saveHistory(keyword);
    setState(() {
      _isSearching = true;
      _results = [];
      _searchedSources = 0;
    });

    final sources = await _scope.getBookSourceParts(_db);
    if (sources.isEmpty) {
      if (mounted) {
        setState(() => _isSearching = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('搜索范围内没有启用的书源，请调整「搜索范围」或到「书源管理」启用书源')));
      }
      return;
    }
    _totalSources = sources.length;
    final selectedSources = sources;

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
    // 根据书源类型设置书籍类型
    int bookType = 0;
    try {
      final src = await _db.getSource(book.origin ?? '');
      if (src != null) {
        if (src.bookSourceType == 1) bookType = 2; // 音频
        else if (src.bookSourceType == 2) bookType = 3; // 图片/漫画
        else if (src.bookSourceType == 4) bookType = 4; // 视频（legado 标准：3=文件，4=视频）
      }
    } catch (_) {}
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
      type: bookType,
      lastCheckTime: DateTime.now().millisecondsSinceEpoch,
    );
    await _db.insertBook(newBook);
    await provider.loadBooks();
    // 加入书架提示（oc_showAddShelfTip）
    if (mounted) {
      final showTip = (await SharedPreferences.getInstance()).getBool('oc_showAddShelfTip') ?? true;
      if (showTip) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已添加《${book.name}》到书架')));
    }
  }

  /// 搜索范围对话框（对齐 legado-E ui/book/search/SearchScopeDialog.kt）
  ///  - 全部书源
  ///  - 按分组（多选，来自启用书源的分组）
  ///  - 按书源（单选，名称::url，不缓存）
  void _showSearchScopeDialog() {
    // 0=按分组 1=按书源
    var mode = _scope.isSource ? 1 : 0;
    final selectedGroups = <String>{};
    if (!_scope.isSource && !_scope.isAll) {
      selectedGroups.addAll(_scope.scope
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty));
    }
    String? selectedSourceUrl =
        _scope.isSource ? _scope.scope.substring(_scope.scope.indexOf('::') + 2) : null;
    var filterText = '';

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, setS) {
        Future<List<BookSource>> loadSources() async {
          final all = await _db.getAllSources();
          final kw = filterText.trim().toLowerCase();
          if (kw.isEmpty) return all;
          return all
              .where((s) =>
                  s.bookSourceName.toLowerCase().contains(kw) ||
                  s.bookSourceUrl.toLowerCase().contains(kw))
              .toList();
        }

        return AlertDialog(
          title: const Text('搜索范围'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text('按分组')),
                    ButtonSegment(value: 1, label: Text('按书源')),
                  ],
                  selected: {mode},
                  onSelectionChanged: (v) => setS(() => mode = v.first),
                ),
                const SizedBox(height: 8),
                if (mode == 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: '过滤书源名称/网址',
                        isDense: true,
                      ),
                      onChanged: (v) => setS(() => filterText = v),
                    ),
                  ),
                Flexible(
                  child: mode == 0
                      ? FutureBuilder<List<String>>(
                          future: _db
                              .getAllSources(enabled: true)
                              .then((list) => list
                                  .map((s) => s.bookSourceGroup ?? '')
                                  .where((g) => g.isNotEmpty)
                                  .toSet()
                                  .toList()
                                ..sort()),
                          builder: (c, snapshot) {
                            if (!snapshot.hasData) {
                              return const Center(child: CircularProgressIndicator());
                            }
                            final groups = snapshot.data!;
                            if (groups.isEmpty) {
                              return const Center(child: Text('启用书源均未分组'));
                            }
                            return ListView.builder(
                              itemCount: groups.length,
                              itemBuilder: (c, i) {
                                final g = groups[i];
                                return CheckboxListTile(
                                  dense: true,
                                  title: Text(g),
                                  value: selectedGroups.contains(g),
                                  onChanged: (v) => setS(() {
                                    if (v == true) {
                                      selectedGroups.add(g);
                                    } else {
                                      selectedGroups.remove(g);
                                    }
                                  }),
                                );
                              },
                            );
                          },
                        )
                      : FutureBuilder<List<BookSource>>(
                          future: loadSources(),
                          builder: (c, snapshot) {
                            if (!snapshot.hasData) {
                              return const Center(child: CircularProgressIndicator());
                            }
                            final sources = snapshot.data!;
                            return ListView.builder(
                              itemCount: sources.length,
                              itemBuilder: (c, i) {
                                final s = sources[i];
                                return RadioListTile<String>(
                                  dense: true,
                                  title: Text(s.bookSourceName,
                                      maxLines: 1, overflow: TextOverflow.ellipsis),
                                  subtitle: Text(s.bookSourceGroup ?? '默认',
                                      style: const TextStyle(fontSize: 11)),
                                  value: s.bookSourceUrl,
                                  groupValue: selectedSourceUrl,
                                  onChanged: (v) => setS(() => selectedSourceUrl = v),
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _scope.update(''); // 全部书源
                Navigator.pop(c);
                setState(() {});
              },
              child: const Text('全部书源'),
            ),
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
            TextButton(
              onPressed: () async {
                if (mode == 0) {
                  if (selectedGroups.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('请至少选择一个分组')));
                    return;
                  }
                  _scope.updateGroups(selectedGroups.toList());
                } else {
                  if (selectedSourceUrl == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('请选择一个书源')));
                    return;
                  }
                  final src = await _db.getSource(selectedSourceUrl!);
                  if (src == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('书源不存在')));
                    return;
                  }
                  // 单书源范围（名称::url），不缓存
                  _scope.update(SearchScope.fromSource(src).scope, save: false);
                }
                if (c.mounted) Navigator.pop(c);
                setState(() {});
              },
              child: const Text('确定'),
            ),
          ],
        );
      }),
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
          IconButton(
            icon: const Icon(Icons.filter_list),
            tooltip: '搜索范围：${_scope.display}',
            onPressed: _showSearchScopeDialog,
          ),
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
      final cs = Theme.of(context).colorScheme;
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        // 装饰性大图标保留 grey，弱化视觉权重
        Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
        const SizedBox(height: 16),
        Text('未找到"$_searchKeyword"相关结果', style: TextStyle(color: cs.onSurfaceVariant)),
      ]));
    }
    final display = _displayResults;
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        if (_isSearching) LinearProgressIndicator(value: _totalSources > 0 ? _searchedSources / _totalSources : 0),
        // 搜索范围 + 精准搜索
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              for (final e in const [(0, '全部'), (1, '书名'), (2, '作者')])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(e.$2),
                    selected: _searchScope == e.$1,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => _setScope(e.$1),
                  ),
                ),
              const Spacer(),
              FilterChip(
                label: const Text('精准'),
                visualDensity: VisualDensity.compact,
                selected: _precision,
                onSelected: (v) => setState(() => _precision = v),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text('共找到 ${display.length} 条', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              TextButton.icon(
                style: ButtonStyle(visualDensity: VisualDensity.compact),
                icon: const Icon(Icons.filter_list, size: 14),
                label: Text(_scope.display, style: const TextStyle(fontSize: 12)),
                onPressed: _showSearchScopeDialog,
              ),
              Text('$_searchedSources/$_totalSources 源', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                padding: EdgeInsets.zero,
                icon: Icon(_groupBySource ? Icons.view_agenda : Icons.sort, color: cs.primary),
                tooltip: _groupBySource ? '按时间排序' : '按书源分组',
                onPressed: () => setState(() => _groupBySource = !_groupBySource),
              ),
            ],
          ),
        ),
        Expanded(child: display.isEmpty
            ? Center(child: Text('当前范围/精准条件下无结果', style: TextStyle(color: cs.onSurfaceVariant)))
            : (_groupBySource ? _buildGroupedList(display) : _buildFlatList(display))),
      ],
    );
  }

  Widget _buildFlatList(List<SearchBook> items) => ListView.separated(
    itemCount: items.length,
    separatorBuilder: (_, __) => const Divider(height: 1),
    itemBuilder: (c, i) => _buildResultTile(items[i]),
  );

  Widget _buildGroupedList(List<SearchBook> items) {
    final groups = groupBy(items, (SearchBook b) => b.originName ?? b.origin ?? '未知来源');
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
        if ((book.originName ?? '').isNotEmpty) Text('来源: ${book.originName}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    ),
    trailing: IconButton(icon: const Icon(Icons.add), onPressed: () => _addToShelf(book), tooltip: '加入书架'),
    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BookDetailScreen(book: Book(name: book.name, author: book.author, coverUrl: book.coverUrl, intro: book.intro, kind: book.kind, origin: book.origin, bookUrl: book.bookUrl, noteUrl: book.noteUrl, lastChapter: book.lastChapter, local: false)))),
    onLongPress: () => _showResultMenu(book),
  );

  Widget _buildDefaultCover(String name) {
    final color = defaultCoverPalette[name.hashCode.abs() % defaultCoverPalette.length];
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
