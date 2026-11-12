import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import 'package:legado_md3/ui/widgets/app_widgets.dart';

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

class _SearchScreenState extends State<SearchScreen>
    with WidgetsBindingObserver {
  final TextEditingController _controller = TextEditingController();
  /// 输入框焦点：对齐 E `SearchActivity.finish()` 先 clearFocus 再退出。
  final FocusNode _searchFocus = FocusNode();
  final DatabaseService _db = DatabaseService();
  final BookSourceEngine _engine = BookSourceEngine();
  List<SearchBook> _results = [];
  List<String> _searchHistory = [];
  bool _isSearching = false;
  /// 搜索取消标记：用户点「停止」后置位，并发池据此提前收工
  bool _searchCancelled = false;
  String? _searchKeyword;
  int _searchedSources = 0;
  int _totalSources = 0;
  bool _groupBySource = false;

  // —— 搜索分页（对齐 E SearchViewModel / SearchModel）——
  /// 当前页码：新搜索置 1，每次续页 `search("")` 自增。
  int _searchPage = 1;
  /// 本页是否至少有一个书源返回了结果（E: `hasMore = hasMore || items.isNotEmpty()`）。
  bool _hasMore = true;
  /// 用户手动停止（E: `isManualStopSearch`）：置位后不再自动续页、FAB 隐藏。
  bool _isManualStop = false;
  /// 页面不可见（E: `viewModel.pause()/resume()`）：暂停取源与自动续页。
  bool _paused = false;
  /// 搜索代数（E: `mSearchId`）：新搜索 / 停止时自增，让在途 worker 提前收工。
  int _searchGeneration = 0;
  /// 当前一轮搜索的书源列表（E: `SearchModel.bookSourceParts`），续页复用。
  List<BookSource> _activeSources = [];
  /// 空结果建议弹窗每轮只弹一次。
  bool _suggestedEmpty = false;

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
    WidgetsBinding.instance.addObserver(this);
    // 输入框焦点变化时刷新 PopScope 的 canPop 判定（用于「先清焦点再退出」）。
    _searchFocus.addListener(() {
      if (mounted) setState(() {});
    });
    _loadHistory();
    _loadScope();
    _loadPrecision();
    _initFromIntent();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 对齐 E `repeatOnLifecycle(RESUMED) { resume(); awaitCancellation(); finally pause() }`：
    // 页面不可见时暂停取源与自动续页，回到前台恢复。
    _paused = state != AppLifecycleState.resumed;
    if (mounted) setState(() {});
  }

  /// 精准搜索是持久化偏好（E: `PreferKey.precisionSearch`），非内存态。
  Future<void> _loadPrecision() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _precision = prefs.getBool('precisionSearch') ?? false);
    }
  }

  Future<void> _setPrecision(bool v) async {
    setState(() => _precision = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('precisionSearch', v);
    // 精准为客户端过滤（E 在引擎侧 filter），切换后 `_displayResults` 立即重算，
    // 无需重置分页；不重跑联网以免误清已翻到的多页结果。
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
    WidgetsBinding.instance.removeObserver(this);
    _searchFocus.dispose();
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

  /// 对齐 E `SearchViewModel.search(key)`：
  ///  - 非空 key：开启新一轮搜索（新 searchId、清结果、page=1、hasMore=true）；
  ///  - 空 key：沿用当前 searchKey / 书源列表，`searchPage++` 续下一页。
  Future<void> _search(String keyword) async {
    if (keyword.trim().isEmpty) {
      await _loadMore();
      return;
    }
    await _startSearch(keyword);
  }

  Future<void> _startSearch(String keyword) async {
    // 离线快速失败（E: NetworkUtils.isAvailable 守卫）
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
    _searchGeneration++;
    final gen = _searchGeneration;
    _searchCancelled = false;
    _isManualStop = false;
    _hasMore = true;
    _searchPage = 1;
    _suggestedEmpty = false;
    setState(() {
      _isSearching = true;
      _results = [];
      _searchedSources = 0;
    });

    final sources = await _scope.getBookSourceParts(_db);
    if (!mounted || gen != _searchGeneration) return;
    if (sources.isEmpty) {
      setState(() => _isSearching = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('搜索范围内没有启用的书源，请调整「搜索范围」或到「书源管理」启用书源')));
      return;
    }
    _activeSources = sources;
    _totalSources = sources.length;
    await _runPage(gen);
  }

  /// 滚到底 / FAB「继续」触发的下一页（对齐 E `search("")` 与
  /// SearchModel `searchId == mSearchId → searchPage++`）。
  Future<void> _loadMore() async {
    if (_isSearching || !_hasMore || _isManualStop || _paused) return;
    final kw = _searchKeyword;
    if (kw == null || kw.isEmpty || _activeSources.isEmpty) return;
    final gen = _searchGeneration;
    _searchCancelled = false;
    _searchPage++;
    setState(() {
      _isSearching = true;
      _searchedSources = 0;
    });
    await _runPage(gen);
  }

  /// 跑当前 `_searchPage`：并发池逐源 `engine.search(source, kw, page: page)`，
  /// 结果累积归并；`hasMore` = 本页是否至少有一个源返回了非空结果
  /// （对齐 E SearchModel `hasMore = hasMore || items.isNotEmpty()`）。
  Future<void> _runPage(int gen) async {
    final kw = _searchKeyword ?? '';
    final page = _searchPage;
    final sources = List<BookSource>.from(_activeSources);
    _totalSources = sources.length;
    const concurrency = 8;
    const perSourceTimeout = Duration(seconds: 30);
    int cursor = 0;
    bool pageHasMore = false;

    Future<void> worker() async {
      while (true) {
        if (_searchCancelled || gen != _searchGeneration) return;
        // 对齐 E SearchModel `workingState.first { it }`：页面不可见时暂停取源。
        while (_paused && !_searchCancelled && gen == _searchGeneration) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        if (_searchCancelled || gen != _searchGeneration) return;
        final i = cursor++;
        if (i >= sources.length) return;
        final source = sources[i];
        try {
          final results = await _engine
              .search(source, kw, page: page)
              .timeout(perSourceTimeout, onTimeout: () => <SearchBook>[]);
          if (results.isNotEmpty) pageHasMore = true;
          if (mounted && results.isNotEmpty && gen == _searchGeneration) {
            setState(() => _mergeResults(results));
          }
        } catch (_) {}
        if (mounted && gen == _searchGeneration) {
          setState(() => _searchedSources++);
        }
      }
    }

    await Future.wait(List.generate(
        concurrency.clamp(1, sources.isEmpty ? 1 : sources.length),
        (_) => worker()));

    if (!mounted || gen != _searchGeneration) return;
    _hasMore = pageHasMore;
    setState(() => _isSearching = false);
    await _maybeSuggestEmpty();
  }

  /// 对齐 E SearchActivity.scrollToBottom()：手动停止 / 搜索中 / 后台暂停时不续页。
  void _scrollToBottom() {
    if (_isManualStop || _isSearching || _paused) return;
    if ((_searchKeyword ?? '').isEmpty || !_hasMore) return;
    _loadMore();
  }

  /// 对齐 E `searchFinishLiveData` + `observeLiveBus`：结果为空且范围非全部时，
  /// 给「关闭精准 / 切换到全部分组」的可操作建议（每轮只弹一次）。
  Future<void> _maybeSuggestEmpty() async {
    if (_suggestedEmpty || _isSearching || _isManualStop) return;
    if (_results.isNotEmpty || _scope.isAll || !mounted) return;
    _suggestedEmpty = true;
    final precision = _precision;
    final scopeName = _scope.display;
    final ok = await showAppConfirmDialog(
      context,
      title: '搜索结果为空',
      content: precision
          ? '$scopeName 分组搜索结果为空，是否关闭精准搜索？'
          : '$scopeName 分组搜索结果为空，是否切换到全部分组？',
      confirmText: '确定',
    );
    if (!ok) return;
    if (precision) {
      await _setPrecision(false);
    } else {
      _scope.update('');
    }
    final kw = _searchKeyword;
    if (kw != null && kw.isNotEmpty) await _search(kw);
  }

  /// 停止当前搜索（对齐 E FAB：搜索中点击 = 手动停止，保留已到达结果）。
  void _stopSearch() {
    _searchCancelled = true;
    _isManualStop = true;
    _searchGeneration++; // 让在途 worker 提前收工
    if (mounted) setState(() => _isSearching = false);
  }

  /// 对齐 E FAB `fbStartStop`：搜索中=停止(stop)，自然结束且 hasMore=继续(play)，
  /// 手动停止后隐藏（searchFinally）。
  Widget? _buildSearchFab() {
    if (_searchKeyword == null) return null;
    if (_isSearching) {
      return FloatingActionButton(
        tooltip: '停止搜索',
        onPressed: _stopSearch,
        child: const Icon(Icons.stop),
      );
    }
    if (_hasMore && !_isManualStop) {
      return FloatingActionButton(
        tooltip: '继续搜索下一页',
        onPressed: _loadMore,
        child: const Icon(Icons.play_arrow),
      );
    }
    return null;
  }

  /// 合并新到达的搜索结果：同名同作者归并为一条并累计来源
  /// （对齐 legado-E SearchModel.mergeItems 的 hasSame/addOrigin 逻辑）
  void _mergeResults(List<SearchBook> incoming) {
    for (final nBook in incoming) {
      if (nBook.origin != null && nBook.origin!.isNotEmpty) {
        nBook.origins.add(nBook.origin!);
      }
      final idx = _results.indexWhere((p) => p.name == nBook.name && p.author == nBook.author);
      if (idx >= 0) {
        final pBook = _results[idx];
        for (final o in nBook.origins) {
          pBook.addOrigin(o);
        }
        // 主条目信息为空时用后到的补齐
        if ((pBook.coverUrl == null || pBook.coverUrl!.isEmpty) && (nBook.coverUrl?.isNotEmpty ?? false)) {
          _results[idx] = SearchBook(
            name: nBook.name, author: nBook.author, coverUrl: nBook.coverUrl, intro: nBook.intro,
            kind: nBook.kind, lastChapter: nBook.lastChapter, origin: pBook.origin,
            originName: pBook.originName, noteUrl: nBook.noteUrl, bookUrl: pBook.bookUrl,
            wordCount: nBook.wordCount,
          )..origins.addAll(pBook.origins);
        }
      } else {
        _results.add(nBook);
      }
    }
  }

  Future<void> _addToShelf(SearchBook book) async {
    final provider = Provider.of<BookProvider>(context, listen: false);
    // 根据书源类型设置书籍类型
    int bookType = 0;
    try {
      final src = await _db.getSource(book.origin ?? '');
      if (src != null) {
        if (src.bookSourceType == 1) {
          bookType = 2; // 音频
        } else if (src.bookSourceType == 2) {
          bookType = 3; // 图片/漫画
        } else if (src.bookSourceType == 4) {
          bookType = 4; // 视频（legado 标准：3=文件，4=视频）
        }
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
      if (showTip && mounted && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已添加《${book.name}》到书架')));
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
                const SizedBox(height: AppSpacing.s),
                if (mode == 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.s),
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
                              return const AppLoadingIndicator();
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
                              return const AppLoadingIndicator();
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
                    if (mounted && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('书源不存在')));
                    }
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
    // 对齐 E SearchActivity.finish()：返回键在输入框有焦点时先 clearFocus
    // 不退出；无焦点才真正出栈。
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_searchFocus.hasFocus) {
          _searchFocus.unfocus();
        } else if (context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: TextField(
            controller: _controller,
            focusNode: _searchFocus,
            autofocus: true,
            decoration: InputDecoration(
              hintText: '搜索书籍...',
              border: InputBorder.none,
              suffixIcon: _controller.text.isNotEmpty
                  ? IconButton(icon: const Icon(Icons.clear_outlined), tooltip: '清除', onPressed: () {
                      _controller.clear();
                      _searchGeneration++;
                      _searchCancelled = true;
                      setState(() {
                        _results = [];
                        _searchKeyword = null;
                        _isSearching = false;
                        _activeSources = [];
                        _hasMore = true;
                        _isManualStop = false;
                        _searchPage = 1;
                      });
                    })
                  : null,
            ),
            // 对齐 E onQueryTextSubmit：提交即清焦点并重置手动停止标记。
            onSubmitted: (v) {
              _searchFocus.unfocus();
              _isManualStop = false;
              _search(v);
            },
          ),
          actions: [
            if (_isSearching)
              IconButton(
                icon: const Icon(Icons.stop_circle_outlined),
                tooltip: '停止搜索',
                onPressed: _stopSearch,
              )
            else
              IconButton(icon: const Icon(Icons.search_outlined), tooltip: '搜索', onPressed: () => _search(_controller.text)),
            IconButton(
              icon: const Icon(Icons.filter_list_outlined),
              tooltip: '搜索范围：${_scope.display}',
              onPressed: _showSearchScopeDialog,
            ),
          ],
        ),
        // 对齐 E fbStartStop：stop / play 两态。
        floatingActionButton: _buildSearchFab(),
        // 对齐 E RecyclerView.OnScrollListener：滚到底自动续页。
        body: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.axis == Axis.vertical && n.metrics.extentAfter <= 200) {
              _scrollToBottom();
            }
            return false;
          },
          child: _searchKeyword == null
              ? _buildSearchHistory()
              : _buildSearchResults(),
        ),
      ),
    );
  }

  Widget _buildSearchHistory() {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.l),
      children: [
        if (_searchHistory.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('搜索历史', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              TextButton(onPressed: _clearHistory, child: const Text('清空')),
            ],
          ),
          const SizedBox(height: AppSpacing.s),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _searchHistory.map((kw) => ActionChip(label: Text(kw), onPressed: () => _search(kw))).toList(),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
        const Text('热门搜索', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: AppSpacing.s),
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
        const SizedBox(height: AppSpacing.l),
        Text('正在搜索 ($_searchedSources/$_totalSources)...'),
        const SizedBox(height: AppSpacing.s),
        TextButton.icon(
          icon: const Icon(Icons.stop, size: 18),
          label: const Text('停止搜索'),
          onPressed: _stopSearch,
        ),
      ]));
    }
    if (_results.isEmpty) {
      return AppEmptyState(
        icon: Icons.find_in_page_outlined,
        title: '未找到"$_searchKeyword"相关结果',
        message: '换个关键词，或到「书源管理」启用更多书源后重试',
      );
    }
    final display = _displayResults;
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        if (_isSearching) LinearProgressIndicator(value: _totalSources > 0 ? _searchedSources / _totalSources : 0),
        // 搜索范围 + 精准搜索
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.m, AppSpacing.s, AppSpacing.m, 0),
          child: Row(
            children: [
              for (final e in const [(0, '全部'), (1, '书名'), (2, '作者')])
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.s),
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
                onSelected: _setPrecision,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l, vertical: AppSpacing.s),
          child: Row(
            children: [
              Text('共找到 ${display.length} 条', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              TextButton.icon(
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                icon: const Icon(Icons.filter_list_outlined, size: 14),
                label: Text(_scope.display, style: const TextStyle(fontSize: 12)),
                onPressed: _showSearchScopeDialog,
              ),
              Text('第$_searchPage页 · $_searchedSources/$_totalSources 源', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                padding: EdgeInsets.zero,
                icon: Icon(_groupBySource ? Icons.view_agenda_outlined : Icons.sort_outlined, color: cs.primary),
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

  void _openDetail(SearchBook book) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BookDetailScreen(
            book: Book(
              name: book.name,
              author: book.author,
              coverUrl: book.coverUrl,
              intro: book.intro,
              kind: book.kind,
              origin: book.origin,
              bookUrl: book.bookUrl,
              noteUrl: book.noteUrl,
              lastChapter: book.lastChapter,
              local: false,
            ),
          ),
        ),
      );

  /// 搜索结果列表：对齐 legado-E SearchActivity 的 LinearLayoutManager +
  /// item_search.xml —— 单列、每项为「左封面 80x110 + 右侧书名/作者/最新章/简介」
  /// 的横向列表项，而非网格大封面。
  Widget _buildFlatList(List<SearchBook> items, {bool shrinkWrap = false}) =>
      ListView.separated(
        shrinkWrap: shrinkWrap,
        physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
        padding: EdgeInsets.fromLTRB(12, 4, 12, shrinkWrap ? 0 : 12),
        itemCount: items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (c, i) => _buildResultCard(items[i]),
      );

  Widget _buildGroupedList(List<SearchBook> items) {
    final groups = groupBy(items, (SearchBook b) => b.originName ?? b.origin ?? '未知来源');
    final entries = groups.entries.toList();
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (c, gi) {
        final e = entries[gi];
        final isLast = gi == entries.length - 1;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AppSectionHeader('${e.key} (${e.value.length})'),
          _buildFlatList(e.value, shrinkWrap: true),
          if (!isLast) const Divider(height: 1),
        ]);
      },
    );
  }

  /// 搜索结果列表项：对齐 legado-E item_search.xml 的横向布局 ——
  /// 左封面固定 80x110（约 3:4），右侧自上而下书名(16)/作者(12)/标签/
  /// 最新章(12)/简介(12)，右上角来源数角标与「加入书架」按钮。
  Widget _buildResultCard(SearchBook book) {
    final cs = Theme.of(context).colorScheme;
    const coverW = 80.0;
    const coverH = 110.0;
    final author = book.author.trim().isEmpty ? '未知作者' : book.author;
    final intro = (book.intro ?? '').trim();
    final kind = (book.kind ?? '').trim();
    final lastChapter = (book.lastChapter ?? '').trim();
    return InkWell(
      onTap: () => _openDetail(book),
      onLongPress: () => _showResultMenu(book),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 左：封面（叠加入书架快捷按钮）
            Stack(
              children: [
                BookCover(
                  name: book.name,
                  coverUrl: book.coverUrl,
                  width: coverW,
                  height: coverH,
                  radius: 6,
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: Material(
                    color: cs.surfaceContainerHighest.withOpacity(0.82),
                    shape: const CircleBorder(),
                    child: InkWell(
                      borderRadius: AppRadius.lAll,
                      onTap: () => _addToShelf(book),
                      child: const Padding(
                        padding: EdgeInsets.all(3),
                        child: Icon(Icons.add, size: 16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: AppSpacing.m),
            // 右：文字信息列（高度与封面一致）
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: coverH),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(book.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        ),
                        if (book.origins.length > 1)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: cs.tertiaryContainer,
                              borderRadius: AppRadius.sAll,
                            ),
                            child: Text('${book.origins.length}源',
                                style: TextStyle(fontSize: 10, color: cs.onTertiaryContainer)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    if (kind.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(kind,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: cs.secondary)),
                      ),
                    if (lastChapter.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(lastChapter,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: cs.primary)),
                      ),
                    if (intro.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(intro,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showResultMenu(SearchBook book) {
    showAppMenuSheet(
      context,
      title: book.name,
      items: [
        AppMenuSheetItem(
          title: '查看详情',
          icon: Icons.info_outline,
          onTap: () => _openDetail(book),
        ),
        AppMenuSheetItem(
          title: '加入书架',
          icon: Icons.add_outlined,
          onTap: () => _addToShelf(book),
        ),
        AppMenuSheetItem(
          title: '换源',
          icon: Icons.swap_horiz_outlined,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChangeSourceScreen(book: Book(name: book.name, author: book.author, coverUrl: book.coverUrl, intro: book.intro, kind: book.kind, origin: book.origin, bookUrl: book.bookUrl, noteUrl: book.noteUrl, lastChapter: book.lastChapter, local: false)))),
        ),
        AppMenuSheetItem(
          title: '复制书名',
          icon: Icons.content_copy_outlined,
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: book.name));
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制')));
          },
        ),
        AppMenuSheetItem(
          title: '分享',
          icon: Icons.share_outlined,
          onTap: () => Share.share('《${book.name}》 - ${book.author}'),
        ),
      ],
    );
  }
}
