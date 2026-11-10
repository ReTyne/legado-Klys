/// 由 bookshelf_screen.dart 按「一类一文件」拆出的 _BookshelfScreenState。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../bookshelf_screen.dart';


class _BookshelfScreenState extends State<BookshelfScreen> {
  final DatabaseService _db = DatabaseService();
  final BookSourceEngine _engine = BookSourceEngine();
  bool _isUpdating = false;
  bool _searching = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  _ViewCfg _cfg = _ViewCfg();
  _CoverCfg _coverCfg = const _CoverCfg();
  /// 当前是否 WiFi（由 _reloadCfg 预取，供同步的 _buildCover 消费）。
  bool _wifiOk = false;

  int _sortBy = 3;
  bool _sortAsc = false;

  /// _filteredBooks 缓存：key（搜索词+分组+排序+书籍集合版本）未变时直接复用，
  /// 避免每次 build 全量过滤 + 排序。
  List<Book>? _filteredCache;
  String _filteredKey = '';
  /// 搜索输入防抖（150ms），避免每敲一个字符全量重排
  Timer? _searchDebounce;
  /// 分组页签「待更新」数量缓存（数据版本变化时才重算）
  Map<String, int>? _waitUpdateCache;
  int _waitUpdateKey = -1;

  // —— 更新目录容错（对齐 E MainViewModel）——
  /// 待更新队列（E: waitUpTocBooks）。
  final Set<String> _waitUpTocBooks = <String>{};
  /// 正在更新集合（E: onUpTocBooks），与待更新队列构成「双集合去重」。
  final Set<String> _onUpTocBooks = <String>{};
  /// 更新失败标记集合（E: BookType.updateError），供封面角标与详情开关消费。
  Set<String> _updateErrorBooks = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = Provider.of<BookProvider>(context, listen: false);
      try {
        await provider.loadViewPrefs();
      } catch (_) {}
      // 书籍列表由 MainScreen 首帧统一 loadBooks，此处不再重复全量 DB 读
      if (mounted) await _reloadCfg();
      // 进入自动刷新（oc_autoRefresh）
      try {
        if ((await SharedPreferences.getInstance()).getBool('oc_autoRefresh') ?? false) {
          _updateAllBooks();
        }
      } catch (_) {}
    });
  }

  Future<void> _reloadCfg() async {
    final cfg = await _ViewCfg.load();
    final coverCfg = await _CoverCfg.load();
    // 精确 WiFi 判断（原生通道）；开关未开时不必发起平台调用。
    final wifiOk = coverCfg.onlyWifi
        ? await NetworkMonitor.instance.isWifi
        : false;
    // 对齐 E BookType.updateError：加载失败标记供封面角标展示。
    final errorBooks = await loadUpdateErrorBooks();
    if (!mounted) return;
    setState(() {
      _cfg = cfg;
      _coverCfg = coverCfg;
      _wifiOk = wifiOk;
      _sortBy = _ViewCfg.sortMap[cfg.sortType.clamp(0, 4)];
      _sortAsc = cfg.sortAscending;
      _updateErrorBooks = errorBooks;
      // 配置可能影响过滤条件，作废 _filteredBooks 缓存
      _filteredCache = null;
      _filteredKey = '';
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 未读章节数
  int _unread(Book b) {
    final latest = b.lastChapterIndex ?? b.durChapterIndex;
    return (latest - b.durChapterIndex).clamp(0, 1 << 30);
  }

  List<Book> get _filteredBooks {
    final provider = Provider.of<BookProvider>(context, listen: false);
    // 缓存 key：搜索词 + 当前分组 + 排序 + 影响过滤的配置 + 书籍集合版本
    // （loadBooks/debugSeed 会重建 List，identityHashCode 随之变化）
    final key =
        '$_searchQuery|${provider.currentGroup}|$_sortBy|$_sortAsc|${_cfg.searchFilterFirst}|${_cfg.showLocalBook}|${provider.books.length}|${identityHashCode(provider.books)}';
    final cached = _filteredCache;
    if (cached != null && _filteredKey == key) return cached;
    // 搜索优先过滤：开启后搜索时跨全部分组
    var books = (_cfg.searchFilterFirst && _searchQuery.isNotEmpty)
        ? provider.books
        : provider.filteredBooks;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      books = books
          .where((b) =>
              b.name.toLowerCase().contains(q) ||
              b.author.toLowerCase().contains(q))
          .toList();
    }
    // bs_showLocalBook：关闭时书架不显示本地导入书籍（仅过滤视图，数据保留，
    // 长按菜单/书籍详情等其它入口不受影响）
    if (!_cfg.showLocalBook) {
      books = books.where((b) => !b.local).toList();
    }
    books = List.from(books);
    switch (_sortBy) {
      case 1:
        books.sort((a, b) =>
            _sortAsc ? a.name.compareTo(b.name) : b.name.compareTo(a.name));
        break;
      case 2:
        books.sort((a, b) => _sortAsc
            ? a.author.compareTo(b.author)
            : b.author.compareTo(a.author));
        break;
      case 3:
        books.sort((a, b) => _sortAsc
            ? a.durChapterTime.compareTo(b.durChapterTime)
            : b.durChapterTime.compareTo(a.durChapterTime));
        break;
      case 4:
        books.sort((a, b) => _sortAsc
            ? (a.lastCheckTime ?? 0).compareTo(b.lastCheckTime ?? 0)
            : (b.lastCheckTime ?? 0).compareTo(a.lastCheckTime ?? 0));
        break;
      case 5:
        books.sort((a, b) => _sortAsc
            ? (a.wordCount ?? 0).compareTo(b.wordCount ?? 0)
            : (b.wordCount ?? 0).compareTo(a.wordCount ?? 0));
        break;
      default:
        // 智能/手动：置顶(order<0)在前，其次按 order_num，再按最近阅读
        books.sort((a, b) {
          final pa = (a.order ?? 0) < 0 ? -1 : 0;
          final pb = (b.order ?? 0) < 0 ? -1 : 0;
          if (pa != pb) return pa.compareTo(pb);
          final oa = a.order ?? 0;
          final ob = b.order ?? 0;
          if (oa != ob) return oa.compareTo(ob);
          return b.durChapterTime.compareTo(a.durChapterTime);
        });
    }
    _filteredKey = key;
    _filteredCache = books;
    return books;
  }

  /// 更新目录（对齐 E MainViewModel.upToc / addToWaitUp / startUpTocJob /
  /// updateToc / addDownload 的容错体系）：
  ///  - 双集合去重：waitUpTocBooks + onUpTocBooks；
  ///  - onlyUpdateRead：跳过未读完的书；
  ///  - updateError：书源缺失 / 抓取失败标红，成功清除；
  ///  - preDownloadNum：所有目录更新完才启动后续 N 章预下载；
  ///  - threadCount：并发池替代串行 for。
  Future<void> _updateAllBooks() async {
    setState(() => _isUpdating = true);
    final provider = Provider.of<BookProvider>(context, listen: false);
    final prefs = await SharedPreferences.getInstance();
    final onlyUpdateRead = prefs.getBool('only_update_read') ?? false;

    var toUpdate = provider.books
        .where((b) =>
            !b.local && b.canUpdate && b.origin != null && b.noteUrl != null)
        .toList();
    if (_cfg.updateLimit > 0 && toUpdate.length > _cfg.updateLimit) {
      toUpdate = toUpdate.sublist(0, _cfg.updateLimit);
    }

    // 对齐 E addToWaitUp：onlyUpdateRead 跳过未读完 + 双集合去重。
    final queue = <Book>[];
    String keyOf(Book b) => (b.bookUrl ?? '').isNotEmpty
        ? b.bookUrl!
        : '${b.name}::${b.author}';
    for (final b in toUpdate) {
      if (onlyUpdateRead && _unread(b) > 0) continue;
      final key = keyOf(b);
      if (_waitUpTocBooks.contains(key) || _onUpTocBooks.contains(key)) {
        continue;
      }
      _waitUpTocBooks.add(key);
      queue.add(b);
    }

    final sources = await _db.getAllSources(enabled: true);
    final sourceMap = {for (var s in sources) s.bookSourceUrl: s};
    // 目录更新完才预下载（E: onCompletion「所有目录更新完再开始缓存章节」）。
    final preTargets = <({Book book, BookSource source})>[];
    int updated = 0;

    // 并发池：poolSize = min(threadCount, MAX_THREAD)（E: upPool）。
    final poolSize = AppPrefs.threadCount.clamp(1, 32);
    int cursor = 0;
    Future<void> worker() async {
      while (true) {
        final i = cursor++;
        if (i >= queue.length) return;
        final book = queue[i];
        final key = keyOf(book);
        _onUpTocBooks.add(key);
        try {
          final source = sourceMap[book.origin];
          if (source == null) {
            // E: source == null → addType(BookType.updateError)
            await markUpdateError(book);
            continue;
          }
          final newChapters = await _engine.getToc(source, book.noteUrl!,
              bookInfo: book.jsContext());
          final oldChapters = await _db.getChapters(book.name, book.author);
          if (newChapters.length > oldChapters.length) {
            await _db.saveChapters(book.name, book.author, newChapters);
            book.lastChapter = newChapters.last.title;
            book.lastChapterIndex = newChapters.length - 1;
            book.latestChapterTime = DateTime.now().millisecondsSinceEpoch;
            book.lastCheckTime = DateTime.now().millisecondsSinceEpoch;
            await _db.updateBook(book);
            updated++;
            preTargets.add((book: book, source: source));
          }
          // E: 成功 → removeType(BookType.updateError)
          await clearUpdateError(book);
        } catch (_) {
          // E: onFailure → 重新取书后 addType(BookType.updateError)
          await markUpdateError(book);
        } finally {
          _onUpTocBooks.remove(key);
          _waitUpTocBooks.remove(key);
        }
      }
    }
    await Future.wait(List.generate(
        poolSize.clamp(1, queue.isEmpty ? 1 : queue.length), (_) => worker()));

    // E addDownload：preDownloadNum == 0 时不预下载；区间
    // [durChapterIndex, min(total-1, durChapterIndex + preDownloadNum)]。
    final preNum = AppPrefs.preDownloadNum;
    if (preNum > 0) {
      for (final t in preTargets) {
        await _preDownload(t.book, t.source, preNum);
      }
    }

    _updateErrorBooks = await loadUpdateErrorBooks();
    await provider.loadBooks();
    if (!mounted) return;
    setState(() {
      _isUpdating = false;
      _filteredCache = null;
      _filteredKey = '';
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            '更新完成，共检查 ${queue.length} 本，$updated 本有新章节')));
  }

  /// 对齐 E MainViewModel.addDownload：只缓存 durChapterIndex 起后续
  /// preDownloadNum 章（不缓存整本），且跳过卷标 / 已缓存章节。
  Future<void> _preDownload(Book book, BookSource source, int num) async {
    final chapters = await _db.getChapters(book.name, book.author);
    if (chapters.isEmpty) return;
    final start = book.durChapterIndex.clamp(0, chapters.length - 1);
    final end = (book.durChapterIndex + num).clamp(0, chapters.length - 1);
    for (var i = start; i <= end; i++) {
      final ch = chapters[i];
      if (ch.isVolume || (ch.content ?? '').isNotEmpty) continue;
      try {
        final content = await _engine.getContent(source, ch.url,
            bookInfo: book.jsContext(), chapter: ch.jsContext(book.bookUrl));
        if (content != null && content.isNotEmpty) {
          await _db.updateChapterContent(
              book.name, book.author, ch.index, content);
        }
      } catch (_) {}
    }
  }

  /// 书架 AppBar 右上角 overflow 菜单 —— 项与顺序严格对齐
  /// legado-E `res/menu/main_bookshelf.xml` 的 11 个 showAsAction="never" 项。
  /// 由单一真源 EPlacement 生成，回调逐 id 映射原「更多」底部 sheet 的各动作；
  /// 容器由底部 sheet 改为锚定 AppBar 右上的 EOverflowMenuButton。
  /// 「搜索」为 always 常驻图标，仍独立渲染在 AppBar。
  List<EOverflowItem> _bookshelfOverflowItems() {
    final actions = <String, VoidCallback>{
      'menu_update_toc': () {
        _updateAllBooks();
      },
      'menu_add_local': () {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const LocalImportScreen()));
      },
      'menu_remote': () {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const RemoteBookScreen()));
      },
      'menu_add_url': _showAddBookByUrlDialog,
      'menu_bookshelf_manage': () async {
        await Navigator.push(context,
            MaterialPageRoute(builder: (_) => const BookshelfManageScreen()));
        if (mounted) {
          await Provider.of<BookProvider>(context, listen: false).loadBooks();
        }
      },
      'menu_download': () {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const CacheManageScreen()));
      },
      'menu_group_manage': () async {
        await Navigator.push(context,
            MaterialPageRoute(builder: (_) => const GroupManageScreen()));
        if (mounted) {
          await Provider.of<BookProvider>(context, listen: false).loadBooks();
        }
      },
      'menu_bookshelf_layout': _showBookshelfConfigDialog,
      'menu_export_bookshelf': () {
        _exportBookshelf();
      },
      'menu_import_bookshelf': _showImportBookshelfDialog,
      'menu_log': () {
        _showLogDialog();
      },
    };
    final overflowMenus = EPlacement.mainMenus['bookshelf']!
        .where((e) => e.overflow)
        .toList();
    return eOverflowItemsFrom(
      overflowMenus,
      onTapFor: (id) => actions[id] ?? () {},
      icons: const {
        'menu_update_toc': Icons.refresh_outlined,
        'menu_add_local': Icons.folder_open_outlined,
        'menu_remote': Icons.cloud_download_outlined,
        'menu_add_url': Icons.link_outlined,
        'menu_bookshelf_manage': Icons.select_all_outlined,
        'menu_download': Icons.download_outlined,
        'menu_group_manage': Icons.folder_special_outlined,
        'menu_bookshelf_layout': Icons.view_quilt_outlined,
        'menu_export_bookshelf': Icons.ios_share_outlined,
        'menu_import_bookshelf': Icons.file_download_outlined,
        'menu_log': Icons.article_outlined,
      },
    );
  }

  /// 书架布局对话框 —— 项与顺序对齐 legado-E `dialog_bookshelf_config.xml`：
  /// 分组样式 / 显示未读 / 显示上次更新时间 / 显示待更新书籍 / 快速滚动条 /
  /// 布局（列表·紧凑列表·网格2~6）/ 排序（六项）/ 书名显示（网格布局下）。
  void _showBookshelfConfigDialog() {
    // 对话框内的临时值，确认后一次性落盘
    int groupStyle = _cfg.groupStyle;
    bool showUnread = _cfg.showUnread;
    bool showLastUpdateTime = _cfg.showLastUpdateTime;
    bool showWaitUpdateCount = _cfg.showWaitUpdateCount;
    bool showFastScroller = _cfg.showFastScroller;
    int gridNameMode = _cfg.gridNameMode;
    final provider = Provider.of<BookProvider>(context, listen: false);

    // 当前布局 -> E 风格布局单选索引：
    // 0列表 1紧凑列表 2网格2列 3网格3列 4网格4列 5网格5列 6网格6列
    int layoutIndex;
    final curLayout = provider.bookshelfLayout;
    if (curLayout == 1) {
      layoutIndex = 1;
    } else if (curLayout == 2 || curLayout == 3) {
      layoutIndex = _cfg.columnCount.clamp(2, 6);
    } else if (curLayout == 4) {
      layoutIndex = _cfg.columnCount.clamp(2, 6);
    } else {
      layoutIndex = 0;
    }

    // 当前内部排序 -> E 风格排序单选索引：
    // E: 0最近阅读 1更新时间 2书名 3手动 4综合 5作者
    // Klys 内部: 0智能/手动 1书名 2作者 3最近阅读 4更新时间 5字数
    const internalToE = {3: 0, 4: 1, 1: 2, 0: 3, 2: 5};
    int sortIndex = internalToE[_sortBy] ?? 0;

    // E 风格布局索引 -> (Klys layout, columnCount)
    (int, int?) layoutValue(int i) => switch (i) {
          0 => (0, null),
          1 => (1, null),
          _ => (2, i),
        };

    showDialog(
      context: context,
      builder: (dialogContext) {
        final cs = Theme.of(dialogContext).colorScheme;
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            Widget radio(String label, int value, int group, ValueChanged<int> onChanged) {
              return RadioListTile<int>(
                dense: true,
                visualDensity: VisualDensity.compact,
                value: value,
                groupValue: group,
                title: Text(label, style: const TextStyle(fontSize: 13)),
                onChanged: (v) => onChanged(v ?? 0),
              );
            }

            return AlertDialog(
              title: const Text('书架布局'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 分组样式
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('分组样式', style: TextStyle(fontSize: 14)),
                      trailing: DropdownButton<int>(
                        value: groupStyle,
                        underline: const SizedBox.shrink(),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('标签')),
                          DropdownMenuItem(value: 1, child: Text('分区')),
                        ],
                        onChanged: (v) =>
                            setLocal(() => groupStyle = v ?? 0),
                      ),
                    ),
                    SwitchListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      contentPadding: EdgeInsets.zero,
                      value: showUnread,
                      title: const Text('显示未读', style: TextStyle(fontSize: 14)),
                      onChanged: (v) => setLocal(() => showUnread = v),
                    ),
                    SwitchListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      contentPadding: EdgeInsets.zero,
                      value: showLastUpdateTime,
                      title: const Text('显示上次更新时间', style: TextStyle(fontSize: 14)),
                      onChanged: (v) => setLocal(() => showLastUpdateTime = v),
                    ),
                    SwitchListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      contentPadding: EdgeInsets.zero,
                      value: showWaitUpdateCount,
                      title: const Text('显示待更新书籍', style: TextStyle(fontSize: 14)),
                      onChanged: (v) => setLocal(() => showWaitUpdateCount = v),
                    ),
                    SwitchListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      contentPadding: EdgeInsets.zero,
                      value: showFastScroller,
                      title: const Text('快速滚动条', style: TextStyle(fontSize: 14)),
                      onChanged: (v) => setLocal(() => showFastScroller = v),
                    ),
                    const Divider(height: 16),
                    Text('布局', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: cs.primary)),
                    radio('列表', 0, layoutIndex, (v) => setLocal(() => layoutIndex = v)),
                    radio('紧凑列表', 1, layoutIndex, (v) => setLocal(() => layoutIndex = v)),
                    for (final n in const [2, 3, 4, 5, 6])
                      radio('网格$n列', n, layoutIndex, (v) => setLocal(() => layoutIndex = v)),
                    const Divider(height: 16),
                    Text('排序', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: cs.primary)),
                    radio('最近阅读', 0, sortIndex, (v) => setLocal(() => sortIndex = v)),
                    radio('更新时间', 1, sortIndex, (v) => setLocal(() => sortIndex = v)),
                    radio('书名', 2, sortIndex, (v) => setLocal(() => sortIndex = v)),
                    radio('手动', 3, sortIndex, (v) => setLocal(() => sortIndex = v)),
                    radio('综合', 4, sortIndex, (v) => setLocal(() => sortIndex = v)),
                    radio('作者', 5, sortIndex, (v) => setLocal(() => sortIndex = v)),
                    // 书名显示：仅网格布局可见（同 E 的 book_name_choice 可见性逻辑）
                    if (layoutIndex >= 2) ...[
                      const Divider(height: 16),
                      Text('书名', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: cs.primary)),
                      RadioListTile<int>(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        contentPadding: EdgeInsets.zero,
                        value: 0,
                        groupValue: gridNameMode,
                        title: const Text('显示', style: TextStyle(fontSize: 13)),
                        onChanged: (v) => setLocal(() => gridNameMode = 0),
                      ),
                      RadioListTile<int>(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        contentPadding: EdgeInsets.zero,
                        value: 1,
                        groupValue: gridNameMode,
                        title: const Text('隐藏', style: TextStyle(fontSize: 13)),
                        onChanged: (v) => setLocal(() => gridNameMode = 1),
                      ),
                      RadioListTile<int>(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        contentPadding: EdgeInsets.zero,
                        value: 2,
                        groupValue: gridNameMode,
                        title: const Text('叠加', style: TextStyle(fontSize: 13)),
                        onChanged: (v) => setLocal(() => gridNameMode = 2),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消')),
                FilledButton(
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setInt('bs_groupStyle', groupStyle);
                    await prefs.setBool('bs_showUnread', showUnread);
                    await prefs.setBool('bs_showLastUpdateTime', showLastUpdateTime);
                    await prefs.setBool('bs_showWaitUpdateCount', showWaitUpdateCount);
                    await prefs.setBool('bs_showFastScroller', showFastScroller);
                    await prefs.setInt('bs_gridNameMode', gridNameMode);
                    // 布局与列数
                    final (layout, cols) = layoutValue(layoutIndex);
                    await provider.setBookshelfLayout(layout);
                    if (cols != null) {
                      await prefs.setInt('bs_columnCount', cols);
                      _cfg.columnCount = cols;
                    }
                    // 排序：E 索引 -> Klys cfg 索引
                    // E: 0最近阅读 1更新时间 2书名 3手动 4综合 5作者
                    // cfg: 0最近阅读 1书名 2作者 3添加时间(更新时间) 4手动
                    const eToCfg = [0, 3, 1, 4, 0, 2];
                    await prefs.setInt('bs_sortType', eToCfg[sortIndex]);
                    if (!mounted || !dialogContext.mounted) return;
                    Navigator.pop(dialogContext);
                    await _reloadCfg();
                  },
                  child: const Text('确定'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// 日志对话框（对齐 legado-E 书架菜单 menu_log / AppLogDialog）
  Future<void> _showLogDialog() async {
    final logs = await CrashLogHelper.instance.readLogs();
    if (!mounted) return;
    final cs = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('日志'),
        content: SizedBox(
          width: double.maxFinite,
          child: logs.trim().isEmpty
              ? Text('暂无日志', style: TextStyle(color: cs.onSurfaceVariant))
              : SingleChildScrollView(
                  child: SelectableText(logs, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                ),
        ),
        actions: [
          if (logs.trim().isNotEmpty)
            TextButton(
              onPressed: () async {
                await CrashLogHelper.instance.clear();
                if (mounted && c.mounted) Navigator.pop(c);
              },
              child: const Text('清空'),
            ),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭')),
        ],
      ),
    );
  }

  /// URL 添加书籍对话框（对齐原版 menu_add_url）
  void _showAddBookByUrlDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('URL添加书籍'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 1,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: '书籍链接（每行一个）\n将按书源的书籍地址规则自动匹配',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final text = controller.text;
              Navigator.pop(context);
              _addBookByUrl(text);
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  /// URL 添加书籍：按 bookUrlPattern 匹配书源 → 抓取详情/目录 → 入库并刷新书架
  Future<void> _addBookByUrl(String raw) async {
    final urls = raw
        .split(RegExp(r'[\r\n]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (urls.isEmpty) return;
    final provider = Provider.of<BookProvider>(context, listen: false);
    final sources = await _db.getAllSources(enabled: true);
    int done = 0, ok = 0, fail = 0;
    bool started = false;
    if (!mounted || !context.mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (d) => StatefulBuilder(builder: (d, setP) {
        if (!started) {
          started = true;
          _addBooksByUrl(urls, sources, provider, (d2, ok2, fail2) {
            done = d2;
            ok = ok2;
            fail = fail2;
            setP(() {});
          }).then((_) {
            if (mounted && d.mounted) Navigator.pop(d);
          });
        }
        return AlertDialog(
          title: const Text('URL添加书籍'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            LinearProgressIndicator(value: done / urls.length),
            const SizedBox(height: AppSpacing.m),
            Text('进度 $done/${urls.length}，成功 $ok，失败 $fail'),
          ]),
        );
      }),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok > 0 ? '添加完成：成功 $ok 本，失败 $fail 本' : '添加失败：没有书源匹配这些链接')));
  }

  Future<void> _addBooksByUrl(List<String> urls, List<BookSource> sources,
      BookProvider provider,
      void Function(int done, int ok, int fail) onProgress) async {
    int done = 0, ok = 0, fail = 0;
    for (final url in urls) {
      // 按书籍地址规则（bookUrlPattern）匹配第一个可用书源
      BookSource? matched;
      for (final s in sources) {
        try {
          if (_engine.matchBookUrl(s, url)) {
            matched = s;
            break;
          }
        } catch (_) {}
      }
      if (matched == null) {
        fail++;
        done++;
        onProgress(done, ok, fail);
        continue;
      }
      try {
        final book = await _engine
            .getBookInfo(matched, url)
            .timeout(const Duration(seconds: 30));
        if (book == null || book.name.isEmpty) {
          fail++;
          done++;
          onProgress(done, ok, fail);
          continue;
        }
        book.bookUrl = url;
        book.origin = matched.bookSourceUrl;
        book.originName = matched.bookSourceName;
        book.noteUrl = (book.noteUrl == null || book.noteUrl!.isEmpty) ? url : book.noteUrl;
        book.lastCheckTime = DateTime.now().millisecondsSinceEpoch;
        final existing = await _db.getBook(book.name, book.author);
        if (existing != null) {
          // 书架已有该书：刷新信息但保留阅读进度与分组
          book.durChapterIndex = existing.durChapterIndex;
          book.durChapterPos = existing.durChapterPos;
          book.durChapterTime = existing.durChapterTime;
          book.group = existing.group;
          book.order = existing.order;
          await _db.updateBook(book);
        } else {
          await _db.insertBook(book);
        }
        // 尽力拉取目录，便于添加后立即可读
        try {
          final chapters = await _engine
              .getToc(matched, book.noteUrl!, bookInfo: book.jsContext())
              .timeout(const Duration(seconds: 30));
          if (chapters.isNotEmpty) {
            await _db.saveChapters(book.name, book.author, chapters);
            book.lastChapter = chapters.last.title;
            book.lastChapterIndex = chapters.length - 1;
            await _db.updateBook(book);
          }
        } catch (_) {}
        ok++;
      } catch (_) {
        fail++;
      }
      done++;
      onProgress(done, ok, fail);
    }
    await provider.loadBooks();
  }

  /// 导出书架：书籍列表（书名/作者/分组/书源URL/目录URL/进度）生成 JSON 并分享
  Future<void> _exportBookshelf() async {
    final provider = Provider.of<BookProvider>(context, listen: false);
    final books = provider.books;
    if (books.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('书架为空，无可导出内容')));
      return;
    }
    try {
      final data = <Map<String, dynamic>>[];
      for (final b in books) {
        data.add({
          'name': b.name,
          'author': b.author,
          'group': b.group,
          'origin': b.origin,
          'originName': b.originName,
          'bookUrl': b.bookUrl,
          'noteUrl': b.noteUrl,
          'coverUrl': b.coverUrl,
          'intro': b.intro,
          'lastChapter': b.lastChapter,
          'durChapterIndex': b.durChapterIndex,
          'durChapterPos': b.durChapterPos,
          'durChapterTime': b.durChapterTime,
          'local': b.local,
        });
      }
      final json = const JsonEncoder.withIndent('  ').convert(data);
      final file = File('${Directory.systemTemp.path}/bookshelf.json');
      await file.writeAsString(json, flush: true);
      await Share.shareXFiles([XFile(file.path)], text: '书架导出（${books.length} 本）');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导出失败: $e')));
      }
    }
  }

  /// 导入书架对话框：支持粘贴 JSON 内容/JSON 链接，或选择本地文件
  void _showImportBookshelfDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入书架'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: controller,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              hintText: '书架 JSON 内容，或以 http(s) 开头的 JSON 链接',
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _pickBookshelfFile();
              },
              icon: const Icon(Icons.folder_open, size: 18),
              label: const Text('选择文件'),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              Navigator.pop(context);
              _importBookshelf(text);
            },
            child: const Text('导入'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickBookshelfFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'txt'],
      );
      if (result == null || result.files.isEmpty || result.files.first.path == null) return;
      final text = await File(result.files.first.path!).readAsString();
      await _importBookshelf(text);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导入失败: $e')));
      }
    }
  }

  /// 导入书架：解析 JSON（或先下载链接内容）→ 按 bookUrl/书名去重合并进书架
  Future<void> _importBookshelf(String input) async {
    final text = input.trim();
    if (text.isEmpty) return;
    String jsonText = text;
    if (text.startsWith('http://') || text.startsWith('https://')) {
      try {
        final dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 20),
        ));
        final resp = await dio.get<String>(text,
            options: Options(responseType: ResponseType.plain));
        jsonText = (resp.data ?? '').toString();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('下载书架失败: $e')));
        }
        return;
      }
    }
    List<dynamic> arr;
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is! List) throw const FormatException('不是 JSON 数组');
      arr = decoded;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('解析失败: $e')));
      }
      return;
    }
    if (arr.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('JSON 内容为空')));
      }
      return;
    }
    if (!mounted || !context.mounted) return;
    final provider = Provider.of<BookProvider>(context, listen: false);
    final sources = await _db.getAllSources(enabled: true);
    int done = 0, added = 0, skipped = 0, failed = 0;
    bool started = false;
    if (!mounted || !context.mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (d) => StatefulBuilder(builder: (d, setP) {
        if (!started) {
          started = true;
          _importBookshelfJson(arr, sources, provider, (d2, a, s, f) {
            done = d2;
            added = a;
            skipped = s;
            failed = f;
            setP(() {});
          }).then((_) {
            if (mounted && d.mounted) Navigator.pop(d);
          });
        }
        return AlertDialog(
          title: const Text('导入书架'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            LinearProgressIndicator(value: done / arr.length),
            const SizedBox(height: AppSpacing.m),
            Text('进度 $done/${arr.length}，新增 $added，已存在 $skipped，失败 $failed'),
          ]),
        );
      }),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('导入完成：新增 $added 本，已存在 $skipped 本，失败 $failed 本')));
  }

  Future<void> _importBookshelfJson(List<dynamic> arr, List<BookSource> sources,
      BookProvider provider,
      void Function(int done, int added, int skipped, int failed)
          onProgress) async {
    final existingUrls = <String>{
      for (final b in provider.books)
        if ((b.bookUrl ?? '').isNotEmpty) b.bookUrl!
    };
    final existingKeys = <String>{
      for (final b in provider.books) '${b.name}_${b.author}'
    };
    int done = 0, added = 0, skipped = 0, failed = 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final item in arr) {
      if (item is! Map) {
        failed++;
        done++;
        onProgress(done, added, skipped, failed);
        continue;
      }
      final name = (_jstr(item['name']) ?? '').trim();
      final author = (_jstr(item['author']) ?? '').trim();
      if (name.isEmpty) {
        failed++;
        done++;
        onProgress(done, added, skipped, failed);
        continue;
      }
      final bookUrl = (_jstr(item['bookUrl']) ?? '').trim();
      final origin = (_jstr(item['origin']) ?? '').trim();
      final group = _jstr(item['group']);
      // 按 bookUrl 或 书名+作者 去重
      if ((bookUrl.isNotEmpty && existingUrls.contains(bookUrl)) ||
          existingKeys.contains('${name}_$author')) {
        skipped++;
        done++;
        onProgress(done, added, skipped, failed);
        continue;
      }
      Book? book;
      if (bookUrl.isNotEmpty && origin.isNotEmpty) {
        // 完整书籍信息：直接入库（进度一并恢复）
        final localRaw = item['local'];
        book = Book(
          name: name,
          author: author,
          coverUrl: _jstr(item['coverUrl']),
          intro: _jstr(item['intro']),
          kind: _jstr(item['kind']),
          lastChapter: _jstr(item['lastChapter']),
          origin: origin,
          originName: _jstr(item['originName']),
          bookUrl: bookUrl,
          noteUrl: _jstr(item['noteUrl']),
          durChapterIndex: _jint(item['durChapterIndex']),
          durChapterPos: _jint(item['durChapterPos']),
          durChapterTime: _jint(item['durChapterTime']),
          local: localRaw == true || localRaw == 1,
          group: group,
          lastCheckTime: now,
        );
      } else {
        // 仅书名/作者（如原版导出的精简格式）：走书源精确搜索补全
        for (final s in sources) {
          try {
            final results = await _engine
                .search(s, name)
                .timeout(const Duration(seconds: 20));
            final hit = results
                    .where((r) => r.name == name && (author.isEmpty || r.author == author))
                    .firstOrNull ??
                results.where((r) => r.name == name).firstOrNull;
            if (hit != null) {
              book = Book(
                name: hit.name,
                author: hit.author,
                coverUrl: hit.coverUrl,
                intro: hit.intro,
                kind: hit.kind,
                lastChapter: hit.lastChapter,
                origin: hit.origin,
                originName: hit.originName,
                bookUrl: hit.bookUrl,
                noteUrl: hit.noteUrl,
                group: group,
                lastCheckTime: now,
              );
              break;
            }
          } catch (_) {}
        }
      }
      if (book == null) {
        failed++;
        done++;
        onProgress(done, added, skipped, failed);
        continue;
      }
      try {
        await _db.insertBook(book);
        existingKeys.add('${book.name}_${book.author}');
        if ((book.bookUrl ?? '').isNotEmpty) existingUrls.add(book.bookUrl!);
        added++;
      } catch (_) {
        failed++;
      }
      done++;
      onProgress(done, added, skipped, failed);
    }
    await provider.loadBooks();
  }

  static String? _jstr(dynamic v) => v?.toString();

  static int _jint(dynamic v) =>
      v is int ? v : (int.tryParse(v?.toString() ?? '') ?? 0);

  /// 点击书籍：按「默认直接打开阅读」设置分流到阅读页或详情页
  Future<void> _openBook(Book book) async {
    bool defaultRead = false;
    try {
      defaultRead = (await SharedPreferences.getInstance()).getBool('oc_defaultRead') ?? false;
    } catch (_) {}
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) =>
        defaultRead ? readerForBook(book) : BookDetailScreen(book: book)));
  }

  void _showBookMenu(Book book) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(leading: const Icon(Icons.play_arrow_outlined), title: const Text('开始阅读'), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => readerForBook(book))); }),
              ListTile(leading: const Icon(Icons.info_outline), title: const Text('书籍详情'), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => BookDetailScreen(book: book))); }),
              ListTile(leading: const Icon(Icons.ios_share_outlined), title: const Text('导出书籍'), onTap: () async {
                Navigator.pop(context);
                _showExportDialog(book);
              }),
              const Divider(),
              ListTile(leading: const Icon(Icons.refresh_outlined), title: const Text('更新目录'), onTap: () async {
                Navigator.pop(context);
                if (book.local || book.origin == null || book.noteUrl == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('本地书籍无需更新'))); return; }
                final sources = await _db.getAllSources(enabled: true);
                final source = sources.where((s) => s.bookSourceUrl == book.origin).firstOrNull;
                if (source == null) { if (mounted && context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未找到对应书源或书源已停用'))); return; }
                try {
                  final chapters = await _engine.getToc(source, book.noteUrl!,
                      bookInfo: book.jsContext());
                  await _db.saveChapters(book.name, book.author, chapters);
                  book.lastChapter = chapters.last.title;
                  book.lastChapterIndex = chapters.length - 1;
                  book.lastCheckTime = DateTime.now().millisecondsSinceEpoch;
                  await _db.updateBook(book);
                  if (mounted && context.mounted) await Provider.of<BookProvider>(context, listen: false).loadBooks();
                  if (mounted && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('更新完成，共${chapters.length}章')));
                } catch (e) {
                  if (mounted && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('更新失败: $e')));
                }
              }),
              ListTile(leading: const Icon(Icons.swap_horiz_outlined), title: const Text('换源'), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => ChangeSourceScreen(book: book))); }),
              ListTile(leading: const Icon(Icons.image_outlined), title: const Text('换封面'), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => ChangeCoverScreen(book: book))); }),
              ListTile(leading: const Icon(Icons.download_outlined), title: const Text('缓存全部'), onTap: () { Navigator.pop(context); _cacheOneBook(book); }),
              // 对齐 legado-E 的 BooksAdapterList：长按书籍直接进详情，书架无「书籍标记」等 E 没有的入口
              ListTile(leading: const Icon(Icons.bookmark_border), title: const Text('添加书签'), onTap: () { Navigator.pop(context); _addBookmarkAtProgress(book); }),
              const Divider(),
              ListTile(leading: const Icon(Icons.move_down_outlined), title: const Text('移动到分组'), onTap: () { Navigator.pop(context); _showMoveGroupDialog(book); }),
              ListTile(leading: const Icon(Icons.push_pin_outlined), title: Text((book.order ?? 0) < 0 ? '取消置顶' : '置顶'), onTap: () async {
                Navigator.pop(context);
                book.order = (book.order ?? 0) < 0 ? 0 : -1;
                await _db.updateBook(book);
                if (mounted && context.mounted) await Provider.of<BookProvider>(context, listen: false).loadBooks();
                if (mounted && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text((book.order ?? 0) < 0 ? '已置顶' : '已取消置顶')));
              }),
              ListTile(leading: const Icon(Icons.share_outlined), title: const Text('分享'), onTap: () async {
                Navigator.pop(context);
                await Share.share('《${book.name}》 - ${book.author}\n${book.intro ?? ''}', subject: book.name);
              }),
              const Divider(),
              ListTile(leading: Icon(Icons.delete_outline, color: cs.error), title: Text('删除', style: TextStyle(color: cs.error)), onTap: () async {
                Navigator.pop(context);
                // 对齐 E BookshelfManageActivity 批量删除：本地书带「同时删除
                // 源文件」复选框（deleteBookOriginal 持久化）。
                final choice = await showDeleteBookConfirm(
                  context,
                  book: book,
                  title: '删除《${book.name}》',
                  message: '确定要删除这本书吗？将同时删除已缓存章节。',
                  confirmText: '删除',
                );
                await applyDeleteBookChoice(
                    book, choice, () => _db.deleteBook(book.name, book.author));
                if (choice.confirmed && mounted && context.mounted) {
                  await Provider.of<BookProvider>(context, listen: false).loadBooks();
                }
              }),
            ]),
          ),
        );
      },
    );
  }

  /// 导出书籍对话框（对齐 legado-E CacheActivity 导出选项：格式/编码/章节名/替换规则/范围）
  Future<void> _showExportDialog(Book book) async {
    final chapters = await _db.getChapters(book.name, book.author);
    if (chapters.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('暂无章节可导出')));
      }
      return;
    }
    var format = 'txt';
    var charset = 'UTF-8';
    var noChapterName = false;
    var useReplace = true;
    // 对齐 legado-E CacheActivity 的导出范围三选一：0全部 1仅已缓存 2自定义范围。
    // 旧实现以 bool 表达三态，「仅已缓存/自定义范围」两个 radio 共用 value=false 无法互斥。
    int rangeMode = 0;
    final startCtrl = TextEditingController(text: '1');
    final endCtrl = TextEditingController(text: '${chapters.length}');

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, setS) {
        return AlertDialog(
          title: const Text('导出书籍'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('TXT'),
                      selected: format == 'txt',
                      onSelected: (_) => setS(() => format = 'txt'),
                    ),
                    ChoiceChip(
                      label: const Text('EPUB'),
                      selected: format == 'epub',
                      onSelected: (_) => setS(() => format = 'epub'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('UTF-8'),
                      selected: charset == 'UTF-8',
                      onSelected: (_) => setS(() => charset = 'UTF-8'),
                    ),
                    ChoiceChip(
                      label: const Text('GBK'),
                      selected: charset == 'GBK',
                      onSelected: (_) => setS(() => charset = 'GBK'),
                    ),
                  ],
                ),
                const Divider(),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('不添加章节名'),
                  value: noChapterName,
                  onChanged: (v) => setS(() => noChapterName = v),
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('应用替换规则'),
                  subtitle: const Text('导出时对正文执行已启用的替换净化', style: TextStyle(fontSize: 11)),
                  value: useReplace,
                  onChanged: (v) => setS(() => useReplace = v),
                ),
                const Divider(),
                // 对齐 legado-E CacheActivity：导出范围互斥单选，选中态由 groupValue 唯一确定
                RadioListTile<int>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('全部章节'),
                  value: 0,
                  groupValue: rangeMode,
                  onChanged: (v) => setS(() => rangeMode = v ?? 0),
                ),
                RadioListTile<int>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('仅已缓存的章节'),
                  value: 1,
                  groupValue: rangeMode,
                  onChanged: (v) => setS(() => rangeMode = v ?? 0),
                ),
                RadioListTile<int>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('自定义范围'),
                  value: 2,
                  groupValue: rangeMode,
                  onChanged: (v) => setS(() => rangeMode = v ?? 0),
                ),
                if (rangeMode == 2)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: startCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: '起始章', isDense: true),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: AppSpacing.s),
                          child: Text('至'),
                        ),
                        Expanded(
                          child: TextField(
                            controller: endCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: '结束章', isDense: true),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                Navigator.pop(c);
                await _doExport(book, chapters,
                    format: format,
                    charset: charset,
                    noChapterName: noChapterName,
                    useReplace: useReplace,
                    cachedOnly: rangeMode == 1,
                    customRange: rangeMode == 2,
                    start: int.tryParse(startCtrl.text.trim()),
                    end: int.tryParse(endCtrl.text.trim()));
              },
              child: const Text('导出'),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _doExport(Book book, List<BookChapter> allChapters,
      {required String format,
      required String charset,
      required bool noChapterName,
      required bool useReplace,
      bool cachedOnly = false,
      bool customRange = false,
      int? start,
      int? end}) async {
    var chapters = allChapters;
    if (cachedOnly) {
      chapters = chapters.where((c) => (c.content ?? '').isNotEmpty).toList();
    } else if (customRange) {
      final s = ((start ?? 1) - 1).clamp(0, chapters.length - 1);
      final e = ((end ?? chapters.length) - 1).clamp(s, chapters.length - 1);
      chapters = chapters.sublist(s, e + 1);
    }
    if (chapters.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('所选范围内没有可导出的章节')));
      }
      return;
    }
    List<ReplaceRule> rules = const [];
    if (useReplace) {
      try {
        rules = await _db.getReplaceRules();
      } catch (_) {}
    }
    try {
      final options = ExportOptions(
        charset: charset,
        noChapterName: noChapterName,
        useReplace: useReplace,
        replaceRules: rules,
      );
      final path = format == 'epub'
          ? await ExportBookService.exportToEpub(book, chapters, options: options)
          : await ExportBookService.exportToTxt(book, chapters, options: options);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已导出到: $path')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('导出失败: $e')));
      }
    }
  }

  /// 在当前阅读进度处添加书签
  Future<void> _addBookmarkAtProgress(Book book) async {
    try {
      final chapters = await _db.getChapters(book.name, book.author)
        ..removeWhere((c) => c.isVolume);
      if (chapters.isEmpty) {
        if (mounted && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('暂无章节，请先更新目录后再添加书签')));
        }
        return;
      }
      final idx = book.durChapterIndex.clamp(0, chapters.length - 1);
      final ch = chapters[idx];
      final raw = (ch.content ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
      final excerpt = raw.length > 60 ? raw.substring(0, 60) : raw;
      await _db.addBookmark(Bookmark(
        bookName: book.name,
        bookAuthor: book.author,
        chapterIndex: ch.index,
        chapterTitle: ch.title,
        pageIndex: book.durChapterPos,
        content: excerpt.isEmpty ? null : excerpt,
      ));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已在《${ch.title}》添加书签')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('添加书签失败: $e')));
      }
    }
  }

  void _showMoveGroupDialog(Book book) {
    final provider = Provider.of<BookProvider>(context, listen: false);
    final controller = TextEditingController(text: book.group ?? '');
    // 移动分组仅支持用户自定义分组，虚拟分组（本地/音频/视频/未分组）不可作为目标
    final groups = provider.displayGroups()
        .where((g) => g != '全部' && !BookProvider.isVirtualGroup(g))
        .toList();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移动到分组'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (groups.isNotEmpty) Wrap(spacing: 8, runSpacing: 4, children: [
            for (final g in groups) ActionChip(label: Text(g), onPressed: () async {
              book.group = g;
              await _db.updateBook(book);
              await provider.loadBooks();
              if (mounted && context.mounted) Navigator.pop(context);
            }),
            ActionChip(label: const Text('未分组'), onPressed: () async {
              book.group = null;
              await _db.updateBook(book);
              await provider.loadBooks();
              if (mounted && context.mounted) Navigator.pop(context);
            }),
          ]),
          const SizedBox(height: AppSpacing.s),
          TextField(controller: controller, decoration: const InputDecoration(hintText: '输入新分组名称（留空为未分组）')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: () async {
            final t = controller.text.trim();
            book.group = t.isEmpty ? null : t;
            await _db.updateBook(book);
            await provider.loadBooks();
            if (mounted && context.mounted) Navigator.pop(context);
          }, child: const Text('确定')),
        ],
      ),
    );
  }

  String _fmtTime(int? ms) {
    if (ms == null || ms <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<BookProvider>(context);
    final books = _filteredBooks;
    final layout = provider.bookshelfLayout;
    return Scaffold(
      appBar: AppBar(
        title: !_searching
            ? const Text('书架')
            : TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                    hintText: '搜索书名/作者...', border: InputBorder.none),
                onChanged: (v) {
                  // 150ms 防抖：避免每敲一个字符全量过滤 + 排序
                  _searchDebounce?.cancel();
                  _searchDebounce = Timer(
                      const Duration(milliseconds: 150), () {
                    if (!mounted) return;
                    setState(() => _searchQuery = v);
                  });
                },
              ),
        actions: [
          if (!_searching)
            IconButton(
                icon: const Icon(Icons.search_outlined),
                tooltip: '搜索',
                onPressed: () => setState(() => _searching = true)),
          if (_searching)
            IconButton(
                icon: const Icon(Icons.clear_outlined),
                tooltip: '清除搜索',
                onPressed: () {
                  _searchDebounce?.cancel();
                  _searchController.clear();
                  setState(() {
                    _searching = false;
                    _searchQuery = '';
                  });
                }),
          if (!_searching)
            EOverflowMenuButton(
              tooltip: '更多',
              items: _bookshelfOverflowItems(),
            ),
        ],
        bottom: _cfg.showTabMenu
            ? PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: _buildGroupTabs(provider))
            : null,
      ),
      body: _isUpdating
          ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(), SizedBox(height: AppSpacing.l), Text('正在更新...')]))
          : books.isEmpty
              ? AppEmptyState(
                  icon: Icons.menu_book_outlined,
                  title: '书架为空',
                  message: '去搜索或发现页面添加书籍',
                  action: FilledButton.icon(
                    onPressed: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const SearchScreen())),
                    icon: const Icon(Icons.search_outlined),
                    label: const Text('去搜索'),
                  ),
                )
              : _wrapFastScroller(_buildBody(provider, books, layout)),
    );
  }

  Widget _buildGroupTabs(BookProvider provider) {
    final hideEmpty = _cfg.hideEmptyGroups && _searchQuery.isEmpty;
    var groups = provider.displayGroups(hideEmpty: hideEmpty);
    int Function(String) countOf = provider.bookCountOf;
    // bs_showLocalBook 关闭时本地书籍整体隐藏：页签计数与可见性按过滤后的集合计算，
    // 可见数为 0 的虚拟分组（如“本地”）不再展示，避免点进去是空书架
    if (!_cfg.showLocalBook) {
      int visibleOf(String g) => provider.books
          .where((b) => !b.local && BookProvider.bookInGroup(b, g))
          .length;
      groups = groups.where((g) => g == '全部' || visibleOf(g) > 0).toList();
      countOf = visibleOf;
    }
    // 待更新数量按数据版本预计算一次，build 只读缓存
    if (_cfg.showWaitUpdateCount) {
      _ensureWaitUpdateCache(provider);
    }
    // 横向 FilterChip 页签统一收敛到 AppChipTabs<int>（按索引选中）。
    final selectedIdx = groups.indexOf(provider.currentGroup);
    return AppChipTabs<int>(
      items: List.generate(groups.length, (i) => i),
      selected: selectedIdx, // -1 表示当前分组不在列表中，全部不选中
      labelOf: (i) => _chipLabel(groups[i], countOf(groups[i]), provider),
      onSelected: (i) => provider.setCurrentGroup(groups[i]),
    );
  }

  /// 分组页签文案：书籍数量（bs_showBookCount）与待更新数量（bs_showWaitUpdateCount）
  String _chipLabel(String group, int count, BookProvider provider) {
    var label = _cfg.showBookCount ? '$group $count' : group;
    if (_cfg.showWaitUpdateCount) {
      final wait = _waitUpdateCache?[group] ?? 0;
      if (wait > 0) label = '$label · 待更新$wait';
    }
    return label;
  }

  /// 待更新数量预计算：可参与“一键更新”的网络书籍数（本地书、禁止更新、缺书源/目录地址的不计）。
  /// 每本书计入「全部」+ 所属用户分组 + 命中的虚拟分组，与原 bookInGroup 语义一致；
  /// 仅在书籍集合版本（identityHashCode）变化时重算，避免每次 build 全量遍历。
  void _ensureWaitUpdateCache(BookProvider provider) {
    final key = identityHashCode(provider.books);
    if (_waitUpdateCache != null && _waitUpdateKey == key) return;
    final map = <String, int>{};
    for (final b in provider.books) {
      if (b.local || !b.canUpdate || b.origin == null || b.noteUrl == null) {
        continue;
      }
      void add(String g) => map[g] = (map[g] ?? 0) + 1;
      add('全部');
      if (b.group != null && b.group!.isNotEmpty) add(b.group!);
      for (final vg in BookProvider.virtualGroups) {
        if (BookProvider.inVirtualGroup(b, vg)) add(vg);
      }
    }
    _waitUpdateCache = map;
    _waitUpdateKey = key;
  }

  Widget _buildBody(BookProvider provider, List<Book> books, int layout) {
    // 平铺分组：全部视图且未搜索时，按分组分区
    if (_cfg.groupStyle == 1 &&
        provider.currentGroup == '全部' &&
        _searchQuery.isEmpty) {
      final groups = provider.displayGroups(hideEmpty: _cfg.hideEmptyGroups)
          .where((g) => g != '全部')
          .toList();
      final sections = <MapEntry<String, List<Book>>>[];
      for (final g in groups) {
        // 统一走分组判定：用户分组按 group 匹配，虚拟分组按属性匹配
        final gb = books.where((b) => BookProvider.bookInGroup(b, g)).toList();
        if (gb.isNotEmpty) sections.add(MapEntry(g, gb));
      }
      // 分组列表已含“未分组”虚拟分组时不再重复追加未分组分区
      if (!groups.contains(BookProvider.vGroupUngrouped)) {
        final ungrouped =
            books.where((b) => b.group == null || b.group!.isEmpty).toList();
        if (ungrouped.isNotEmpty) sections.add(MapEntry('未分组', ungrouped));
      }
      // 分组 section 级别懒构建：屏幕外分组的书籍项完全不构建
      return ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.only(bottom: AppSpacing.m),
        itemCount: sections.length,
        itemBuilder: (c, i) {
          final sec = sections[i];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                dense: true,
                leading: const Icon(Icons.folder_outlined, size: 20),
                title: Text(sec.key,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                trailing: _cfg.showBookCount
                    ? Text('${sec.value.length}',
                        style: TextStyle(
                            color: Theme.of(c).colorScheme.onSurfaceVariant,
                            fontSize: 12))
                    : null,
              ),
              _shrinkLayout(sec.value, layout),
              const Divider(),
            ],
          );
        },
      );
    }
    return _buildBookList(books, layout);
  }

  /// 平铺分组下，单个分组内的布局（shrinkWrap，不独立滚动）
  Widget _shrinkLayout(List<Book> books, int layout) {
    switch (layout) {
      case 2:
      case 3:
      case 4:
        final cols = layout == 3
            ? (_cfg.columnCount + 1).clamp(2, 8)
            : _cfg.columnCount.clamp(1, 8);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            childAspectRatio: layout == 4 ? 0.6 : 0.65,
            crossAxisSpacing: layout == 3 ? 4 : 8,
            mainAxisSpacing: layout == 3 ? 4 : 8,
          ),
          itemCount: books.length,
          itemBuilder: (c, i) => layout == 4
              ? _buildCoverItem(books[i])
              : _buildGridItem(books[i], compact: layout == 3),
        );
      default:
        // shrinkWrap 懒构建：替代 Column(children:[for(...)]) 全量构建书籍项
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: books.length,
          itemBuilder: (c, i) => _buildListItem(books[i],
              compact: layout == 1 || _cfg.compactDetails),
        );
    }
  }

  /// bs_showFastScroller：控制书架是否显示快速滚动条（常显滑块，可拖动快速定位）
  Widget _wrapFastScroller(Widget child) => _cfg.showFastScroller
      ? Scrollbar(controller: _scrollController, thumbVisibility: true, child: child)
      : child;

  Widget _buildBookList(List<Book> books, int layout) {
    switch (layout) {
      case 0:
      case 1:
        return ListView.separated(
          controller: _scrollController,
          padding: const EdgeInsets.all(AppSpacing.s),
          itemCount: books.length,
          separatorBuilder: (_, __) => _cfg.showDivider
              ? const Divider(height: 1)
              : const SizedBox(height: AppSpacing.xs),
          itemBuilder: (c, i) =>
              _buildListItem(books[i], compact: layout == 1 || _cfg.compactDetails),
        );
      case 2:
      case 3:
        final cols = layout == 3
            ? (_cfg.columnCount + 1).clamp(2, 8)
            : _cfg.columnCount.clamp(1, 8);
        return GridView.builder(
          controller: _scrollController,
          padding: EdgeInsets.all(layout == 3 ? 4 : 8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            childAspectRatio: 0.65,
            crossAxisSpacing: layout == 3 ? 4 : 8,
            mainAxisSpacing: layout == 3 ? 4 : 8,
          ),
          itemCount: books.length,
          itemBuilder: (c, i) =>
              _buildGridItem(books[i], compact: layout == 3),
        );
      case 4:
        return GridView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(AppSpacing.m),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: _cfg.columnCount.clamp(1, 8),
            childAspectRatio: 0.6,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: books.length,
          itemBuilder: (c, i) => _buildCoverItem(books[i]),
        );
      default:
        return ListView.builder(
          controller: _scrollController,
          itemCount: books.length,
          itemBuilder: (c, i) => _buildListItem(books[i]),
        );
    }
  }

  /// 阅读进度敏感子树：只监听 BookProvider.readingRevision，
  /// 翻页保存进度时（readingRevision.value++）仅局部重建该子树
  /// （未读角标、副标题等），不再触发整书架 notifyListeners 重排。
  Widget _revAware(Widget child) {
    final rev = context.read<BookProvider>().readingRevision;
    return ValueListenableBuilder<int>(
      valueListenable: rev,
      builder: (_, __, child) => child!,
      child: child,
    );
  }

  /// 书架列表项 —— 结构对齐 legado-E `res/layout/item_bookshelf_list.xml`：
  /// 左侧封面 66x90，右侧书名(16sp)/作者(13sp)+上次更新时间/读到(13sp)/最新(13sp)，
  /// 未读数量以角标叠加在封面右上（showUnread）。
  Widget _buildListItem(Book book, {bool compact = false}) {
    final cs = Theme.of(context).colorScheme;
    final coverW = compact ? 36.0 : 66.0;
    final coverH = compact ? 50.0 : 90.0;
    final subStyle = TextStyle(fontSize: compact ? 11 : 13, color: cs.onSurfaceVariant);

    // 「读到」行：按需单章查询 + 缓存，避免全量加载目录
    final durKey = '${book.bookUrl ?? ''}::${book.name}::${book.author}::${book.durChapterIndex}';
    Widget durLine;
    if (compact) {
      durLine = Text(book.lastChapter ?? '暂无章节',
          maxLines: 1, overflow: TextOverflow.ellipsis, style: subStyle);
    } else {
      durLine = FutureBuilder<String>(
        future: _durChapterTitle(book, durKey),
        builder: (context, snap) {
          final title = snap.data;
          if (title == null || title.isEmpty) return const SizedBox.shrink();
          return Text('读到: $title',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: subStyle);
        },
      );
    }

    final timeText =
        _cfg.showLastUpdateTime ? _fmtTime(book.lastCheckTime) : '';
    final lastText = book.lastChapter ?? '';

    return ListTile(
      contentPadding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12, vertical: 2),
      leading: _buildCover(book, width: coverW, height: coverH),
      title: Text(book.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: compact ? 13 : 16, fontWeight: FontWeight.w500)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Expanded(
                child: Text(book.author,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: subStyle)),
            if (timeText.isNotEmpty)
              Text(timeText, maxLines: 1, style: subStyle),
          ]),
          durLine,
          if (lastText.isNotEmpty)
            Text('最新: $lastText',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: subStyle),
        ],
      ),
      onTap: () => _openBook(book),
      onLongPress: () => _showBookMenu(book),
    );
  }

  final Map<String, String> _durTitleCache = {};

  /// 当前阅读章节标题（对应 E 实体的 durChapterTitle），单章查询 + 内存缓存
  Future<String> _durChapterTitle(Book book, String key) async {
    final cached = _durTitleCache[key];
    if (cached != null) return cached;
    try {
      final ch = await _db.getChapter(book.name, book.author, book.durChapterIndex);
      final title = ch?.title ?? '';
      _durTitleCache[key] = title;
      return title;
    } catch (_) {
      return '';
    }
  }

  Widget _buildGridItem(Book book, {required bool compact}) {
    final cs = Theme.of(context).colorScheme;
    // bs_gridNameMode：0封面下显示书名（E 默认）1隐藏 2叠加到封面底部
    final showNameBelow = _cfg.gridNameMode != 1;
    final overlayOnCover = _cfg.gridNameMode == 2;
    Widget cover = _buildCover(book, width: double.infinity, height: double.infinity, radius: 8);
    if (overlayOnCover) {
      cover = Stack(
        fit: StackFit.expand,
        children: [
          cover,
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.6)],
                ),
              ),
              child: Text(
                book.name,
                maxLines: _cfg.maxTitleLines.clamp(1, 5),
                textAlign: _cfg.centerTitle ? TextAlign.center : TextAlign.start,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Colors.white, shadows: [Shadow(blurRadius: 2)]),
              ),
            ),
          ),
        ],
      );
    }
    return RepaintBoundary(
      child: GestureDetector(
        onTap: () => _openBook(book),
        onLongPress: () => _showBookMenu(book),
        child: Column(children: [
          Expanded(child: cover),
          if (showNameBelow)
            _revAware(Padding(
              padding: EdgeInsets.all(compact ? 4 : 8),
              child: Text(book.name,
                  maxLines: _cfg.maxTitleLines.clamp(1, 5),
                  textAlign: _cfg.centerTitle ? TextAlign.center : TextAlign.start,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: _cfg.compactTitle ? 11 : (compact ? 11 : 13),
                      color: cs.onSurface)),
            )),
        ]),
      ),
    );
  }

  Widget _buildCoverItem(Book book) {
    return RepaintBoundary(
      child: GestureDetector(
        onTap: () => _openBook(book),
        onLongPress: () => _showBookMenu(book),
        child: ClipRRect(
          borderRadius: AppRadius.sAll,
          child: _buildCover(book,
              width: double.infinity, height: double.infinity, radius: 0),
        ),
      ),
    );
  }

  /// 「有未读只显示小红点」（bs_showUnreadNew）的角标形态。
  /// 数字角标（bs_showUnread）已交给 BookCover.badge（组件内部用 cs.error），
  /// 这里同样不再硬编码 Color(0xFFB3261E)，危险色统一取 cs.error。
  Widget _withUnreadDot(Widget child, double width, double height) {
    final cs = Theme.of(context).colorScheme;
    final stack = Stack(fit: StackFit.expand, children: [
      child,
      Positioned(
        right: 2,
        top: 2,
        child: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: cs.error, shape: BoxShape.circle),
        ),
      ),
    ]);
    if (width.isFinite && height.isFinite) {
      return SizedBox(width: width, height: height, child: stack);
    }
    return stack;
  }

  Widget _buildCover(Book book,
      {required double width, required double height, double radius = 4}) {
    final url = (book.customCoverUrl != null && book.customCoverUrl!.isNotEmpty)
        ? book.customCoverUrl
        : book.coverUrl;

    // cover_onlyWifi：仅 WiFi 下加载网络封面。
    // _wifiOk 由 NetworkMonitor.isWifi（原生 ConnectivityManager 通道）在
    // _reloadCfg 中预取；非 WiFi / 离线 / 非 Android 时交给 BookCover 回退
    // DefaultCover，不发起网络请求。
    final blockNetwork = _coverCfg.onlyWifi &&
        url != null &&
        url.startsWith('http') &&
        (!_wifiOk || !NetworkMonitor.instance.online.value);

    // 数字未读角标交给 BookCover.badge（组件内部用 cs.error，不再硬编码）。
    final unread = _unread(book);
    final int? badge = (_cfg.showUnread && unread > 0) ? unread : null;

    // 封面叠加文字交给 BookCover.overlay（组件自带底部渐变墨层）；
    // 文字统一用白色（与 DefaultCover 白字一致，不再引入第二套日夜配色）。
    Widget? overlay;
    if (_coverCfg.showName || _coverCfg.showAuthor) {
      overlay = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_coverCfg.showName)
            Text(book.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    shadows: [Shadow(blurRadius: 2)])),
          if (_coverCfg.showAuthor)
            Text(book.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    shadows: [Shadow(blurRadius: 2)])),
        ],
      );
    }

    Widget cover = BookCover(
      name: book.name,
      coverUrl: blockNetwork ? null : url,
      width: width,
      height: height,
      radius: radius,
      badge: badge,
      overlay: overlay,
    );

    // 封面阴影（bs_coverShadow）：属内容/图像层墨色阴影，保留既有硬编码。
    if (_cfg.coverShadow) {
      cover = Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: const [
            BoxShadow(
                color: Color(0x33000000),
                blurRadius: 4,
                offset: Offset(1, 2)),
          ],
        ),
        child: cover,
      );
    }

    // bs_showUnreadNew 小红点是 BookCover.badge 之外的第二种角标形态，保留。
    final showDot = !(_cfg.showUnread && unread > 0) &&
        _cfg.showUnreadNew &&
        unread > 0;
    if (showDot) cover = _withUnreadDot(cover, width, height);

    // 对齐 E BookType.updateError：更新目录失败的书在封面左上角标红「!」，
    // 是该标记的真实视觉消费点（标记由 _updateAllBooks 写入）。
    if (_updateErrorBooks.contains(updateErrorBookKey(book))) {
      final badgeCs = Theme.of(context).colorScheme;
      cover = Stack(
        fit: StackFit.expand,
        children: [
          cover,
          Positioned(
            left: 2,
            top: 2,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: badgeCs.error,
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Icon(Icons.error_outline,
                  size: 12, color: Colors.white),
            ),
          ),
        ],
      );
    }

    // 角标依赖 durChapterIndex（阅读进度），随 readingRevision 局部重建。
    return _revAware(cover);
  }

  /// 单本缓存（书籍菜单「缓存全部」）。忙碌态统一走 runWithBusyDialog。
  Future<void> _cacheOneBook(Book book) async {
    final r = await runWithBusyDialog(
      context,
      message: '正在缓存章节...',
      task: _cacheBook(book),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('缓存完成: 成功${r.ok}章${r.fail > 0 ? ', 失败${r.fail}章' : ''}')));
    }
  }

  Future<({int ok, int fail})> _cacheBook(Book book) async {
    int ok = 0, fail = 0;
    if (book.local || book.origin == null || book.noteUrl == null) {
      return (ok: ok, fail: fail);
    }
    final sources = await _db.getAllSources(enabled: true);
    final source =
        sources.where((s) => s.bookSourceUrl == book.origin).firstOrNull;
    if (source == null) return (ok: ok, fail: fail);
    final chapters = await _db.getChapters(book.name, book.author);
    for (final ch in chapters) {
      if (ch.isVolume || (ch.content ?? '').isNotEmpty) continue;
      try {
        final content = await _engine.getContent(source, ch.url,
            bookInfo: book.jsContext(),
            chapter: ch.jsContext(book.bookUrl));
        if (content != null && content.isNotEmpty) {
          await _db.updateChapterContent(
              book.name, book.author, ch.index, content);
          ok++;
        } else {
          fail++;
        }
      } catch (_) {
        fail++;
      }
    }
    return (ok: ok, fail: fail);
  }


}
