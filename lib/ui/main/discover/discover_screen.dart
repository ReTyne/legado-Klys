import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/data/model/search_book.dart';
import 'package:legado_md3/help/source/source_engine.dart';
import 'package:legado_md3/di/book_provider.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/ui/book/detail/book_detail_screen.dart';

/// 发现分类（名称 + 发现地址）
class _ExploreCategory {
  final String name;
  final String url;
  const _ExploreCategory(this.name, this.url);
}

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final DatabaseService _db = DatabaseService();
  final BookSourceEngine _engine = BookSourceEngine();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<BookSource> _sources = [];
  BookSource? _currentSource;

  /// 视图层级：选源 -> 选分类 -> 书籍列表
  /// 'source' | 'category' | 'books'
  String _view = 'source';
  List<_ExploreCategory> _categories = [];
  _ExploreCategory? _currentCategory;
  Set<String> _hiddenCategories = {};

  final List<SearchBook> _exploreBooks = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 1;
  String? _error;

  String _searchQuery = '';
  // 0 默认 1 名称 2 作者 3 最新章节
  int _sortMode = 0;
  // 搜索/过滤匹配的字段
  final Set<String> _filterFields = {'name', 'author'};

  @override
  void initState() {
    super.initState();
    _loadSources();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  Future<void> _loadSources() async {
    try {
      final sources = await _db.getAllSources(enabled: true);
      // 与发现页实际可用口径一致：只要配置了发现地址即纳入（enabledExplore 仅作偏好，不作为硬过滤）
      final exploreSources = sources.where((s) => (s.exploreUrl ?? '').trim().isNotEmpty).toList();
      if (!mounted) return;
      setState(() => _sources = exploreSources);
      // 仅一个发现源时直接进入
      if (_view == 'source' && _sources.length == 1) {
        await _selectSource(_sources.first);
      }
    } catch (_) {
      // 数据库尚未就绪等情况下保持空态，不使页面崩溃
      if (mounted) setState(() {});
    }
  }

  List<_ExploreCategory> _parseCategories(BookSource source) {
    final result = <_ExploreCategory>[];
    final lines = (source.exploreUrl ?? '').split('\n').where((l) => l.trim().isNotEmpty);
    for (final line in lines) {
      final parts = line.split(':::');
      if (parts.length == 2) {
        final name = parts[0].trim();
        // 同一分类下的多选用 &&& 分隔，发现列表默认取第一个地址
        final firstUrl = parts[1].split('&&&').first.trim();
        if (firstUrl.isNotEmpty) result.add(_ExploreCategory(name, firstUrl));
      } else if (line.trim().isNotEmpty) {
        result.add(_ExploreCategory('发现', line.trim()));
      }
    }
    return result;
  }

  Future<Set<String>> _loadHidden(BookSource source) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList('explore_hidden_${source.bookSourceUrl}') ?? const []).toSet();
  }

  Future<void> _saveHidden(BookSource source, Set<String> hidden) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('explore_hidden_${source.bookSourceUrl}', hidden.toList());
  }

  Future<void> _selectSource(BookSource source) async {
    final cats = _parseCategories(source);
    final hidden = await _loadHidden(source);
    if (!mounted) return;
    setState(() {
      _currentSource = source;
      _categories = cats;
      _hiddenCategories = hidden;
      _searchQuery = '';
      _searchController.clear();
    });
    if (cats.isEmpty) {
      setState(() => _view = 'source');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('「${source.bookSourceName}」未配置发现地址')));
      return;
    }
    final visible = cats.where((c) => !hidden.contains(c.name)).toList();
    if (visible.length == 1) {
      _openCategory(visible.first);
    } else {
      setState(() => _view = 'category');
    }
  }

  void _back() {
    setState(() {
      if (_view == 'books') {
        // 单分类源没有分类选择层，直接回到选源
        _view = _categories.where((c) => !_hiddenCategories.contains(c.name)).length <= 1 ? 'source' : 'category';
      } else if (_view == 'category') {
        _view = 'source';
      }
    });
  }

  Future<void> _openCategory(_ExploreCategory cat) async {
    setState(() {
      _currentCategory = cat;
      _view = 'books';
      _exploreBooks.clear();
      _isLoading = true;
      _hasMore = true;
      _currentPage = 1;
      _error = null;
      _searchQuery = '';
      _searchController.clear();
    });
    await _loadExploreBooks();
  }

  String _applyPage(String url, int page) {
    var u = url.replaceAll('{{page-1}}', '${page - 1}');
    u = u.replaceAll('{{ page - 1 }}', '${page - 1}');
    u = u.replaceAll('{{page}}', '$page');
    u = u.replaceAll('{{ page }}', '$page');
    return u;
  }

  Future<void> _loadExploreBooks() async {
    final source = _currentSource;
    final cat = _currentCategory;
    if (source == null || cat == null) return;
    try {
      final url = _applyPage(cat.url, _currentPage);
      final books = await _engine.exploreByUrl(source, url);
      if (!mounted) return;
      setState(() {
        _exploreBooks.addAll(books);
        _isLoading = false;
        _isLoadingMore = false;
        if (books.isEmpty) _hasMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        _error = '$e';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasMore || _view != 'books') return;
    final cat = _currentCategory;
    if (cat == null || !cat.url.contains('{{page')) {
      _hasMore = false;
      return;
    }
    setState(() {
      _isLoadingMore = true;
      _currentPage++;
    });
    await _loadExploreBooks();
  }

  Future<void> _refresh() async {
    if (_view == 'books') {
      setState(() {
        _exploreBooks.clear();
        _isLoading = true;
        _hasMore = true;
        _currentPage = 1;
        _error = null;
      });
      await _loadExploreBooks();
    } else {
      await _loadSources();
    }
  }

  // 过滤 + 排序后的展示列表
  List<SearchBook> get _visibleBooks {
    var list = List<SearchBook>.from(_exploreBooks);
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((b) {
        if (_filterFields.contains('name') && b.name.toLowerCase().contains(q)) return true;
        if (_filterFields.contains('author') && b.author.toLowerCase().contains(q)) return true;
        if (_filterFields.contains('intro') && (b.intro ?? '').toLowerCase().contains(q)) return true;
        if (_filterFields.contains('kind') && (b.kind ?? '').toLowerCase().contains(q)) return true;
        return false;
      }).toList();
    }
    switch (_sortMode) {
      case 1:
        list.sort((a, b) => a.name.compareTo(b.name));
        break;
      case 2:
        list.sort((a, b) => a.author.compareTo(b.author));
        break;
      case 3:
        list.sort((a, b) => (b.lastChapter ?? '').compareTo(a.lastChapter ?? ''));
        break;
    }
    return list;
  }

  void _showSourceSwitcher() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(padding: EdgeInsets.all(16), child: Text('选择发现书源', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
            if (_sources.isEmpty)
              const Padding(padding: EdgeInsets.all(24), child: Text('暂无配置发现地址的书源'))
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: _sources.map((source) => ListTile(
                    leading: const Icon(Icons.rss_feed),
                    title: Text(source.bookSourceName),
                    subtitle: Text(source.bookSourceUrl, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                    trailing: _currentSource?.bookSourceUrl == source.bookSourceUrl ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary) : null,
                    onTap: () {
                      Navigator.pop(context);
                      _selectSource(source);
                    },
                  )).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 分类管理：显示/隐藏当前书源的发现分类（持久化）
  void _showCategoryManager() {
    final source = _currentSource;
    if (source == null) {
      _showSourceSwitcher();
      return;
    }
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('分类管理 · ${source.bookSourceName}'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('勾选要在发现页显示的分类，取消勾选则隐藏', style: TextStyle(fontSize: 12, color: Colors.grey)),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: _categories.map((c) {
                    final hidden = _hiddenCategories.contains(c.name);
                    return CheckboxListTile(
                      dense: true,
                      value: !hidden,
                      title: Text(c.name),
                      onChanged: (v) {
                        setDialogState(() {
                          if (v == true) {
                            _hiddenCategories.remove(c.name);
                          } else {
                            // 至少保留一个可见分类
                            if (_categories.length - _hiddenCategories.length <= 1) return;
                            _hiddenCategories.add(c.name);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
            FilledButton(onPressed: () async {
              await _saveHidden(source, _hiddenCategories);
              if (!mounted) return;
              Navigator.pop(context);
              // 重新进入以应用显隐
              await _selectSource(source);
            }, child: const Text('保存')),
          ],
        ),
      ),
    );
  }

  /// 过滤字段选择
  void _showFilterDialog() {
    final labels = {'name': '书名', 'author': '作者', 'intro': '简介', 'kind': '分类'};
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('搜索过滤字段'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: labels.entries.map((e) => CheckboxListTile(
              dense: true,
              title: Text(e.value),
              value: _filterFields.contains(e.key),
              onChanged: (v) => setDialogState(() {
                if (v == true) {
                  _filterFields.add(e.key);
                } else if (_filterFields.length > 1) {
                  _filterFields.remove(e.key);
                }
              }),
            )).toList(),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
          ],
        ),
      ),
    );
  }

  void _showSortDialog() {
    const names = ['默认排序', '按名称', '按作者', '按最新章节'];
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('排序方式'),
        children: List.generate(names.length, (i) => SimpleDialogOption(
          child: Row(children: [
            Icon(i == _sortMode ? Icons.radio_button_checked : Icons.radio_button_off, size: 18,
                color: i == _sortMode ? Theme.of(context).colorScheme.primary : Colors.grey),
            const SizedBox(width: 12),
            Text(names[i]),
          ]),
          onPressed: () {
            setState(() => _sortMode = i);
            Navigator.pop(context);
          },
        )),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: _view == 'source'
            ? null
            : IconButton(icon: const Icon(Icons.arrow_back), onPressed: _back),
        title: Text(_titleText(), maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (_view == 'books') ...[
            IconButton(icon: const Icon(Icons.category_outlined), tooltip: '分类', onPressed: _backToCategory),
            IconButton(icon: const Icon(Icons.filter_list), tooltip: '过滤', onPressed: _showFilterDialog),
            IconButton(icon: const Icon(Icons.sort), tooltip: '排序', onPressed: _showSortDialog),
            IconButton(icon: const Icon(Icons.refresh), tooltip: '刷新', onPressed: _refresh),
          ],
          if (_view == 'category')
            IconButton(icon: const Icon(Icons.tune), tooltip: '分类管理', onPressed: _showCategoryManager),
          IconButton(icon: const Icon(Icons.source_outlined), tooltip: '切换书源', onPressed: _showSourceSwitcher),
        ],
      ),
      body: _buildBody(),
    );
  }

  void _backToCategory() {
    final visibleCount = _categories.where((c) => !_hiddenCategories.contains(c.name)).length;
    setState(() => _view = visibleCount > 1 ? 'category' : 'source');
  }

  String _titleText() {
    if (_view == 'source') return '发现';
    final name = _currentSource?.bookSourceName ?? '发现';
    if (_view == 'books' && _currentCategory != null) return '${_currentCategory!.name} · $name';
    return name;
  }

  Widget _buildBody() {
    if (_view == 'source') return _buildSourceChips();
    if (_view == 'category') return _buildCategoryList();
    return _buildBooksList();
  }

  Widget _buildSourceChips() {
    if (_sources.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.explore_off, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text('暂无发现书源', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            const Text('请在「书源管理」中导入含发现地址的书源并启用', style: TextStyle(color: Colors.grey), textAlign: TextAlign.center),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadSources,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('发现书源', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _sources.map((source) => ActionChip(
              avatar: const Icon(Icons.rss_feed, size: 16),
              label: Text(source.bookSourceName),
              onPressed: () => _selectSource(source),
            )).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryList() {
    final visible = _categories.where((c) => !_hiddenCategories.contains(c.name)).toList();
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(children: [
              Expanded(child: Text('${_currentSource?.bookSourceName ?? ''} 的发现分类', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
              TextButton.icon(onPressed: _showCategoryManager, icon: const Icon(Icons.tune, size: 16), label: const Text('管理')),
            ]),
          ),
          ...visible.map((c) => Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(c.name),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openCategory(c),
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildBooksList() {
    if (_isLoading && _exploreBooks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _exploreBooks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text('加载失败: $_error', style: const TextStyle(color: Colors.grey), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: _refresh, child: const Text('重试')),
          ],
        ),
      );
    }
    final books = _visibleBooks;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: '过滤当前分类书籍...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchController.clear(); setState(() => _searchQuery = ''); })
                  : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: books.isEmpty
                ? ListView(children: const [SizedBox(height: 200), Center(child: Text('没有匹配的书籍'))])
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: books.length + (_isLoadingMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= books.length) {
                        return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
                      }
                      return _buildBookItem(books[index]);
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildBookItem(SearchBook book) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: _buildCover(book),
        title: Text(book.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(book.author, style: const TextStyle(fontSize: 12)),
            if (book.lastChapter != null && book.lastChapter!.isNotEmpty)
              Text('最新: ${book.lastChapter}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.primary)),
            if (book.intro != null && book.intro!.isNotEmpty)
              Text(book.intro!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.add),
          tooltip: '加入书架',
          onPressed: () async {
            await context.read<BookProvider>().addBook(book.toBook());
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已添加《${book.name}》到书架')));
          },
        ),
        onTap: () {
          final b = book.toBook();
          Navigator.push(context, MaterialPageRoute(builder: (_) => BookDetailScreen(book: b)));
        },
      ),
    );
  }

  Widget _buildCover(SearchBook book) {
    if (book.coverUrl != null && book.coverUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.network(book.coverUrl!, width: 48, height: 66, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _defaultCover(book.name)),
      );
    }
    return _defaultCover(book.name);
  }

  Widget _defaultCover(String name) {
    const colors = [Colors.blueGrey, Colors.brown, Colors.teal, Colors.indigo, Colors.deepOrange, Colors.purple];
    final color = colors[name.hashCode.abs() % colors.length];
    return Container(
      width: 48, height: 66,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
      child: Center(child: Padding(padding: const EdgeInsets.all(4), child: Text(name, maxLines: 3, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)))),
    );
  }
}
