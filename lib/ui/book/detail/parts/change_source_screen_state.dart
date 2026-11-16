/// 由 change_source_screen.dart 按「一类一文件」拆出的 _ChangeSourceScreenState。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../change_source_screen.dart';

/// 换源结果排序方式。
enum _ChangeSourceSort { defaultOrder, score, responseTime }

/// 换源结果筛选。
enum _ResultFilter { all, found, notFound }

class _ChangeSourceScreenState extends State<ChangeSourceScreen> {
  final DatabaseService _db = DatabaseService();
  final BookSourceEngine _engine = BookSourceEngine();
  final List<_SourceResult> _results = [];
  bool _loading = true;
  int _done = 0;
  int _total = 0;

  _ChangeSourceSort _sort = _ChangeSourceSort.defaultOrder;
  _ResultFilter _resultFilter = _ResultFilter.all;
  String _groupFilter = '';
  List<String> _groups = [];
  bool _loadTocWordCount = false;
  bool _loadingWordCount = false;

  @override
  void initState() {
    super.initState();
    _searchAll();
  }

  Future<void> _searchAll() async {
    final sources = await _db.getAllSources(enabled: true);
    _results
      ..clear()
      ..addAll(sources.map(_SourceResult.new));
    _total = _results.length;
    // 分组筛选项直接取自本次参与换源的书源，避免额外 DB 查询。
    final groupSet = <String>{};
    for (final s in sources) {
      final g = (s.bookSourceGroup ?? '').trim();
      if (g.isNotEmpty) groupSet.add(g);
    }
    _groups = groupSet.toList()..sort();
    if (mounted) setState(() => _loading = false);

    // 并发池检索，每源最多 15s
    const concurrency = 8;
    int cursor = 0;
    Future<void> worker() async {
      while (true) {
        final i = cursor++;
        if (i >= _results.length) return;
        final r = _results[i];
        try {
          final sw = Stopwatch()..start();
          final list = await _engine
              .search(r.source, widget.book.name)
              .timeout(const Duration(seconds: 15), onTimeout: () => []);
          sw.stop();
          // 优先同名，作者也匹配最佳；同时给出匹配质量评分。
          final target = widget.book.name.replaceAll(RegExp(r'\s'), '');
          SearchBook? best;
          var score = 0;
          for (final b in list) {
            if (b.name.replaceAll(RegExp(r'\s'), '') == target) {
              final authorMatch = widget.book.author.isEmpty ||
                  b.author.contains(widget.book.author) ||
                  widget.book.author.contains(b.author);
              best = b;
              score = authorMatch ? 100 : 80;
              if (authorMatch) break;
            }
          }
          if (best == null && list.isNotEmpty) {
            best = list.first;
            score = 50;
          }
          if (mounted) {
            setState(() {
              r.match = best;
              r.score = score;
              r.responseMs = sw.elapsedMilliseconds;
              r.searching = false;
              _done++;
            });
          }
        } catch (e) {
          if (mounted) {
            setState(() {
              r.searching = false;
              r.error = '$e';
              _done++;
            });
          }
        }
      }
    }

    await Future.wait(List.generate(
        concurrency.clamp(1, _results.isEmpty ? 1 : _results.length),
        (_) => worker()));
    if (_loadTocWordCount) await _loadAllWordCounts();
  }

  /// 归一化章节标题：去空白 / 常见分隔符、统一小写、全角数字转半角，
  /// 容忍不同书源「第1章 / 1. / Chapter 1 / 第一章」等写法差异（§4-6）。
  static String _normalizeTitle(String raw) {
    var s = raw.toLowerCase();
    // 全角数字 → 半角
    const fullWidth = '０１２３４５６７８９';
    const halfWidth = '0123456789';
    for (var i = 0; i < fullWidth.length; i++) {
      s = s.replaceAll(fullWidth[i], halfWidth[i]);
    }
    // 去空白 + 逐个剔除常见标点分隔（避免复杂正则字符类）
    s = s.replaceAll(RegExp(r'\s+'), '');
    const punct = [
      '·',
      '・',
      ',',
      '，',
      '.',
      '。',
      '、',
      ':',
      '：',
      ';',
      '；',
      '!',
      '！',
      '?',
      '？',
      '"',
      '“',
      '”',
      '‘',
      '’',
      '[',
      ']',
      '【',
      '】',
      '(',
      ')',
      '（',
      '）',
      '<',
      '>',
      '《',
      '》',
      '-',
      '—',
      '_',
      '/',
      '\\',
      '|',
    ];
    for (final p in punct) {
      s = s.replaceAll(p, '');
    }
    return s;
  }

  /// 抽取标题里首个数字作为章节序号（跨源章节编号是最后的兜底匹配依据）。
  static int? _chapterNumber(String title) {
    const cnDigits = {
      '零': '0',
      '〇': '0',
      '一': '1',
      '二': '2',
      '三': '3',
      '四': '4',
      '五': '5',
      '六': '6',
      '七': '7',
      '八': '8',
      '九': '9',
    };
    var s = title;
    cnDigits.forEach((k, v) => s = s.replaceAll(k, v));
    final m = RegExp(r'\d+').firstMatch(s);
    if (m == null) return null;
    return int.tryParse(m.group(0)!);
  }

  /// 在新目录里按「归一化标题」匹配最接近的章节下标；找不到返回 -1。
  /// 策略：精确归一化 > 互相包含 > 章节号数值最接近（§4-6）。
  int _matchChapterIndex(List<BookChapter> chapters, String oldTitle) {
    final t = _normalizeTitle(oldTitle);
    if (t.isEmpty) return -1;
    // 1) 精确归一化匹配
    for (var i = 0; i < chapters.length; i++) {
      if (!chapters[i].isVolume && _normalizeTitle(chapters[i].title) == t) {
        return i;
      }
    }
    // 2) 互相包含（容忍「第X章」前缀 / 副标题后缀差异）
    for (var i = 0; i < chapters.length; i++) {
      final c = chapters[i];
      if (c.isVolume) continue;
      final ct = _normalizeTitle(c.title);
      if (ct.isEmpty) continue;
      if (ct.contains(t) || t.contains(ct)) return i;
    }
    // 3) 章节号数值最接近
    final n = _chapterNumber(oldTitle);
    if (n != null) {
      var bestIdx = -1;
      var bestDiff = 1 << 30;
      for (var i = 0; i < chapters.length; i++) {
        if (chapters[i].isVolume) continue;
        final cn = _chapterNumber(chapters[i].title);
        if (cn == null) continue;
        final diff = (cn - n).abs();
        if (diff < bestDiff) {
          bestDiff = diff;
          bestIdx = i;
        }
      }
      if (bestIdx >= 0) return bestIdx;
    }
    return -1;
  }

  Future<void> _changeSource(_SourceResult r) async {
    final m = r.match;
    if (m == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('「${r.source.bookSourceName}」未找到本书')));
      return;
    }
    final confirmed = await showAppConfirmDialog(
      context,
      title: '确认换源',
      content: '将《${widget.book.name}》更换为「${r.source.bookSourceName}」的源吗？',
    );
    if (!confirmed || !mounted) return;

    // 迁移 sheet 取消时完整恢复换源前的书籍字段，不留内存副作用
    final prev = (
      origin: widget.book.origin,
      originName: widget.book.originName,
      noteUrl: widget.book.noteUrl,
      bookUrl: widget.book.bookUrl,
      coverUrl: widget.book.coverUrl,
      lastChapter: widget.book.lastChapter,
      intro: widget.book.intro,
    );

    // 1) 记录换源前的章节标题（当前阅读进度所在章），作为进度匹配依据
    final oldChapters =
        await _db.getChapters(widget.book.name, widget.book.author);
    final oldIndex = widget.book.durChapterIndex;
    final oldTitle = (oldIndex >= 0 && oldIndex < oldChapters.length)
        ? oldChapters[oldIndex].title
        : '';

    // 2) 切换书籍来源字段（目录地址沿用搜索结果，缺省回退书籍地址）
    final tocUrl =
        (m.noteUrl?.isNotEmpty ?? false) ? m.noteUrl! : (m.bookUrl ?? '');
    widget.book
      ..origin = r.source.bookSourceUrl
      ..originName = r.source.bookSourceName
      ..noteUrl = (m.noteUrl?.isNotEmpty ?? false) ? m.noteUrl : m.bookUrl
      ..bookUrl = m.bookUrl ?? tocUrl
      ..coverUrl =
          (m.coverUrl?.isNotEmpty ?? false) ? m.coverUrl : widget.book.coverUrl
      ..lastChapter = (m.lastChapter?.isNotEmpty ?? false)
          ? m.lastChapter
          : widget.book.lastChapter
      ..intro = (m.intro?.isNotEmpty ?? false) ? m.intro : widget.book.intro;

    // 3) 拉取新书源目录（忙碌对话框），用于按标题匹配进度
    final info = <String, dynamic>{
      ...widget.book.jsContext(),
      'bookUrl': m.bookUrl ?? tocUrl,
      'tocUrl': tocUrl,
      'origin': r.source.bookSourceUrl,
      'originName': r.source.bookSourceName,
    };
    if (!mounted) return;
    final newChapters = await runWithBusyDialog<List<BookChapter>>(
      context,
      message: '正在获取新书源目录...',
      task: (() async {
        if (tocUrl.isEmpty) return <BookChapter>[];
        try {
          return await _engine.getToc(r.source, tocUrl, bookInfo: info).timeout(
              const Duration(seconds: 20),
              onTimeout: () => <BookChapter>[]);
        } catch (_) {
          return <BookChapter>[];
        }
      })(),
    );
    if (!mounted) return;

 // 4) 统计可迁移数据，弹出迁移选项 sheet
    final matched =
        newChapters.isNotEmpty ? _matchChapterIndex(newChapters, oldTitle) : -1;
    final bookmarks =
        await _db.getBookmarks(widget.book.name, widget.book.author);
    final highlights =
        await _db.getBookHighlights(widget.book.name, widget.book.author);
    if (!mounted) return;
    final options = await _showSourceMigrationSheet(
      context,
      bookName: widget.book.name,
      sourceName: r.source.bookSourceName,
      matchedTitle: matched >= 0 ? newChapters[matched].title : null,
      hasMatch: matched >= 0,
      bookmarkCount: bookmarks.length,
      highlightCount: highlights.length,
    );
    if (options == null || !mounted) {
      widget.book
        ..origin = prev.origin
        ..originName = prev.originName
        ..noteUrl = prev.noteUrl
        ..bookUrl = prev.bookUrl
        ..coverUrl = prev.coverUrl
        ..lastChapter = prev.lastChapter
        ..intro = prev.intro;
      return;
    }

    final keepProgress = options.keepProgress && matched >= 0;
    final newIndex = keepProgress ? matched : 0;
    final oldPagePos = widget.book.durChapterPos;

    // 5) 按章节标题把书签 / 高亮重映射到新源目录索引
    if (options.migrateBookmarks && bookmarks.isNotEmpty) {
      await _migrateBookmarks(bookmarks, newChapters);
    }
    if (options.migrateHighlights && highlights.isNotEmpty) {
      await _migrateHighlights(highlights, newChapters);
    }

    // 6) 目录落库：拉到新目录则直接保存（阅读页无需重复联网），否则清空让阅读页重拉
    if (newChapters.isNotEmpty) {
      await _db.saveChapters(widget.book.name, widget.book.author, newChapters);
      widget.book.lastChapterIndex = newChapters.length - 1;
    } else {
      await _db.deleteChapters(widget.book.name, widget.book.author);
      widget.book.lastChapterIndex = 0;
    }
    widget.book.durChapterIndex = newIndex;
    widget.book.durChapterPos =
        (keepProgress && options.keepPagePos) ? oldPagePos : 0;
    await _db.updateBook(widget.book);
    if (mounted) {
      final migrated = <String>[];
      if (options.migrateBookmarks && bookmarks.isNotEmpty) migrated.add('书签');
      if (options.migrateHighlights && highlights.isNotEmpty) {
        migrated.add('高亮');
      }
      final suffix = migrated.isEmpty ? '' : '，已迁移${migrated.join(' / ')}';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            Text(keepProgress ? '换源成功，已保留阅读进度$suffix' : '换源成功，将从头开始$suffix'),
      ));
      Navigator.pop(context, true);
    }
  }

  /// 书签按章节标题重映射：能匹配到新章节才迁移，匹配不到保留原记录不丢数据。
  Future<void> _migrateBookmarks(
      List<Bookmark> bookmarks, List<BookChapter> newChapters) async {
    if (newChapters.isEmpty) return;
    for (final b in bookmarks) {
      final idx = _matchChapterIndex(newChapters, b.chapterTitle);
      if (idx < 0) continue;
      if (b.id != null) await _db.deleteBookmark(b.id!);
      b.id = null;
      b.chapterIndex = idx;
      b.chapterTitle = newChapters[idx].title;
      await _db.insertBookmark(b);
    }
  }

  /// 划线 / 高亮按章节标题重映射（BookHighlight.id 为 final，重建对象）。
  Future<void> _migrateHighlights(
      List<BookHighlight> hs, List<BookChapter> newChapters) async {
    if (newChapters.isEmpty) return;
    for (final h in hs) {
      final idx = _matchChapterIndex(newChapters, h.chapterTitle);
      if (idx < 0) continue;
      if (h.id != null) await _db.deleteBookHighlight(h.id!);
      await _db.insertBookHighlight(BookHighlight(
        bookName: h.bookName,
        author: h.author,
        chapterIndex: idx,
        chapterTitle: newChapters[idx].title,
        content: h.content,
        start: h.start,
        end: h.end,
        color: h.color,
        note: h.note,
        createTime: h.createTime,
      ));
    }
  }

  // ==================== 排序 / 筛选 / 目录字数 / 源操作 ====================

  /// 按分组、结果状态筛选后排序；置顶(-1) 恒在前、置底(1) 恒在后。
  List<_SourceResult> _visibleResults() {
    final list = _results.where((r) {
      if (_groupFilter.isNotEmpty &&
          (r.source.bookSourceGroup ?? '').trim() != _groupFilter) {
        return false;
      }
      switch (_resultFilter) {
        case _ResultFilter.found:
          if (r.match == null) return false;
          break;
        case _ResultFilter.notFound:
          if (r.match != null || r.searching) return false;
          break;
        case _ResultFilter.all:
          break;
      }
      return true;
    }).toList();

    int cmp(_SourceResult a, _SourceResult b) {
      if (a.pin != b.pin) return a.pin.compareTo(b.pin);
      switch (_sort) {
        case _ChangeSourceSort.score:
          return b.score.compareTo(a.score);
        case _ChangeSourceSort.responseTime:
          final at = a.responseMs ?? 1 << 30;
          final bt = b.responseMs ?? 1 << 30;
          return at.compareTo(bt);
        case _ChangeSourceSort.defaultOrder:
          return 0;
      }
    }

    list.sort((a, b) {
      final c = cmp(a, b);
      return c != 0 ? c : _results.indexOf(a).compareTo(_results.indexOf(b));
    });
    return list;
  }

  /// 拉取单个源的目录并统计章节数 / 目录字数（标题与正文字符数之和）。
  Future<void> _loadToc(_SourceResult r) async {
    final m = r.match;
    if (m == null || r.toc != null) return;
    final tocUrl =
        (m.noteUrl?.isNotEmpty ?? false) ? m.noteUrl! : (m.bookUrl ?? '');
    if (tocUrl.isEmpty) return;
    try {
      final chapters = await _engine.getToc(r.source, tocUrl, bookInfo: {
        'bookUrl': m.bookUrl ?? tocUrl,
        'name': m.name,
        'author': m.author,
        'tocUrl': tocUrl,
        'durChapterIndex': 0,
      }).timeout(const Duration(seconds: 15), onTimeout: () => <BookChapter>[]);
      var words = 0;
      for (final c in chapters) {
        words += c.title.length + (c.content?.length ?? 0);
      }
      if (mounted) {
        setState(() {
          r.toc = chapters;
          r.chapterCount = chapters.length;
          r.tocWordCount = words;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          r.toc = <BookChapter>[];
          r.chapterCount = 0;
          r.tocWordCount = 0;
        });
      }
    }
  }

  /// 开关打开时为所有命中源并发加载目录字数。
  Future<void> _loadAllWordCounts() async {
    final targets =
        _results.where((r) => r.match != null && r.toc == null).toList();
    if (targets.isEmpty) return;
    if (mounted) setState(() => _loadingWordCount = true);
    const concurrency = 4;
    var cursor = 0;
    Future<void> worker() async {
      while (true) {
        final i = cursor++;
        if (i >= targets.length) return;
        await _loadToc(targets[i]);
      }
    }

    await Future.wait(
        List.generate(concurrency.clamp(1, targets.length), (_) => worker()));
    if (mounted) setState(() => _loadingWordCount = false);
  }

  /// 目录预览：展示命中源抓取到的章节列表。
  Future<void> _previewToc(_SourceResult r) async {
    if (r.toc == null) await _loadToc(r);
    if (!mounted) return;
    final chapters = r.toc ?? [];
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('目录预览 · ${r.source.bookSourceName}'),
        content: SizedBox(
          width: double.maxFinite,
          child: chapters.isEmpty
              ? const Text('未获取到目录')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: chapters.length > 200 ? 200 : chapters.length,
                  itemBuilder: (_, i) => ListTile(
                    dense: true,
                    title: Text(chapters[i].title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('关闭')),
        ],
      ),
    );
  }

  void _setPin(_SourceResult r, int pin) {
    if (mounted) setState(() => r.pin = pin);
  }

  Future<void> _disableSource(_SourceResult r) async {
    final ok = await showAppConfirmDialog(
      context,
      title: '禁用书源',
      content: '确定禁用「${r.source.bookSourceName}」吗？',
      confirmText: '禁用',
      danger: true,
    );
    if (ok != true) return;
    await _db.enable(r.source.bookSourceUrl, false);
    if (mounted) setState(() => _results.remove(r));
  }

  Future<void> _deleteSource(_SourceResult r) async {
    final ok = await showAppConfirmDialog(
      context,
      title: '删除书源',
      content: '确定删除「${r.source.bookSourceName}」吗？此操作不可撤销。',
      confirmText: '删除',
      danger: true,
    );
    if (ok != true) return;
    await _db.deleteSource(r.source.bookSourceUrl);
    if (mounted) setState(() => _results.remove(r));
  }

  /// 长按结果弹出的单源操作面板。
  void _showResultActions(_SourceResult r) {
    showModalBottomSheet<void>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.list_alt_outlined),
              title: const Text('预览目录'),
              onTap: () {
                Navigator.pop(c);
                _previewToc(r);
              },
            ),
            ListTile(
              leading: const Icon(Icons.vertical_align_top),
              title: const Text('置顶'),
              onTap: () {
                Navigator.pop(c);
                _setPin(r, -1);
              },
            ),
            ListTile(
              leading: const Icon(Icons.vertical_align_bottom),
              title: const Text('置底'),
              onTap: () {
                Navigator.pop(c);
                _setPin(r, 1);
              },
            ),
            if (r.pin != 0)
              ListTile(
                leading: const Icon(Icons.layers_clear_outlined),
                title: const Text('取消置顶/置底'),
                onTap: () {
                  Navigator.pop(c);
                  _setPin(r, 0);
                },
              ),
            ListTile(
              leading: const Icon(Icons.block_outlined),
              title: const Text('禁用此源'),
              onTap: () {
                Navigator.pop(c);
                _disableSource(r);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error),
              title: const Text('删除此源'),
              onTap: () {
                Navigator.pop(c);
                _deleteSource(r);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.m, vertical: AppSpacing.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: _groupFilter.isEmpty ? null : _groupFilter,
                  hint: const Text('全部分组', style: TextStyle(fontSize: 12)),
                  items: [
                    const DropdownMenuItem<String>(
                        value: '', child: Text('全部分组')),
                    ..._groups.map((g) => DropdownMenuItem<String>(
                        value: g,
                        child: Text(g,
                            maxLines: 1, overflow: TextOverflow.ellipsis))),
                  ],
                  onChanged: (v) => setState(() => _groupFilter = v ?? ''),
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              DropdownButton<_ResultFilter>(
                value: _resultFilter,
                items: const [
                  DropdownMenuItem(
                      value: _ResultFilter.all, child: Text('全部结果')),
                  DropdownMenuItem(
                      value: _ResultFilter.found, child: Text('有结果')),
                  DropdownMenuItem(
                      value: _ResultFilter.notFound, child: Text('无结果')),
                ],
                onChanged: (v) =>
                    setState(() => _resultFilter = v ?? _ResultFilter.all),
              ),
            ],
          ),
          Row(
            children: [
              const Text('加载详情目录字数', style: TextStyle(fontSize: 12)),
              Switch(
                value: _loadTocWordCount,
                onChanged: (v) {
                  setState(() => _loadTocWordCount = v);
                  if (v) _loadAllWordCounts();
                },
              ),
              if (_loadingWordCount)
                const Padding(
                  padding: EdgeInsets.only(left: AppSpacing.s),
                  child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              const Spacer(),
              PopupMenuButton<_ChangeSourceSort>(
                icon: const Icon(Icons.sort, size: 20),
                tooltip: '排序',
                onSelected: (v) => setState(() => _sort = v),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                      value: _ChangeSourceSort.defaultOrder,
                      child: Text('默认顺序')),
                  PopupMenuItem(
                      value: _ChangeSourceSort.score, child: Text('按评分')),
                  PopupMenuItem(
                      value: _ChangeSourceSort.responseTime,
                      child: Text('按响应时间')),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('换源 - ${widget.book.name}'),
        actions: [
          if (_done < _total)
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
                child: Center(
                    child: Text('$_done/$_total',
                        style: const TextStyle(fontSize: 12))))
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '重新搜索',
              onPressed: () {
                setState(() {
                  _done = 0;
                  _results.clear();
                  _loading = true;
                });
                _searchAll();
              },
            ),
        ],
      ),
      body: _loading
          ? const AppLoadingIndicator()
          : _results.isEmpty
              ? const AppEmptyState(
                  icon: Icons.source_outlined,
                  title: '暂无可用书源',
                  message: '请先在书源管理中启用书源',
                )
              : Column(
                  children: [
                    _buildFilterBar(),
                    Expanded(child: _buildResultList(cs)),
                  ],
                ),
    );
  }

  Widget _buildResultList(ColorScheme cs) {
    final visible = _visibleResults();
    if (visible.isEmpty) {
      return RefreshIndicator(
        onRefresh: _searchAll,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            Center(child: Text('当前筛选条件下没有结果')),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _searchAll,
      child: ListView.separated(
        itemCount: visible.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (c, i) {
          final r = visible[i];
          final isCurrent = r.source.bookSourceUrl == widget.book.origin;
          Widget status;
          if (r.searching) {
            status = const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2));
          } else if (r.match != null) {
            status = isCurrent
                ? Icon(Icons.check_circle, color: cs.primary)
                : const Icon(Icons.swap_horiz);
          } else {
            status = Icon(Icons.do_not_disturb_alt, color: cs.onSurfaceVariant);
          }
          final info = StringBuffer();
          if (!r.searching) {
            info.write('评分 ${r.score}');
            if (r.responseMs != null) info.write('  ·  ${r.responseMs}ms');
            if (r.chapterCount != null) {
              info.write('  ·  ${r.chapterCount}章  ·  目录字数 ${r.tocWordCount}');
            }
          }
          final primary = r.searching
              ? '搜索中...'
              : r.match != null
                  ? '${r.match!.author}  ${r.match!.lastChapter ?? ''}'
                  : (r.error != null ? '搜索失败' : '未找到');
          return ListTile(
            leading: CircleAvatar(
              child: Text(r.source.bookSourceName.isNotEmpty
                  ? r.source.bookSourceName[0]
                  : '?'),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(r.source.bookSourceName,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                if (r.pin == -1) const Icon(Icons.vertical_align_top, size: 14),
                if (r.pin == 1)
                  const Icon(Icons.vertical_align_bottom, size: 14),
              ],
            ),
            subtitle: Text(
              info.isEmpty ? primary : '$primary\n$info',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
            isThreeLine: info.isNotEmpty,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                status,
                const SizedBox(width: 2),
                IconButton(
                  icon: const Icon(Icons.more_vert, size: 18),
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(6),
                  tooltip: '更多操作',
                  onPressed: () => _showResultActions(r),
                ),
              ],
            ),
            onTap: r.searching || isCurrent ? null : () => _changeSource(r),
            onLongPress: () => _showResultActions(r),
          );
        },
      ),
    );
  }
}
