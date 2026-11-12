import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_chapter.dart';
import 'package:legado_md3/data/model/book_highlight.dart';
import 'package:legado_md3/data/model/bookmark.dart';
import 'package:legado_md3/data/model/replace_rule.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/help/source/replace_rule_service.dart';
import 'package:legado_md3/help/storage/import_book_service.dart';
import 'package:legado_md3/ui/bookmark/bookmark_export.dart';
import 'package:legado_md3/ui/config/txt_toc_rule_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 目录页：「目录 / 书签 / 高亮」三 Tab，
/// 菜单按当前 Tab 分组切换（E: onMenuOpened 的 menu_group_toc / menu_group_bookmark / menu_group_text）。
class ChapterListScreen extends StatefulWidget {
  final Book? book;
  final List<BookChapter>? chapters;
  final int currentIndex;

  const ChapterListScreen({super.key, this.book, this.chapters, this.currentIndex = 0});

  @override
  State<ChapterListScreen> createState() => _ChapterListScreenState();
}

class _ChapterListScreenState extends State<ChapterListScreen>
    with SingleTickerProviderStateMixin {
  final DatabaseService _db = DatabaseService();
  final TextEditingController _searchController = TextEditingController();
  late TabController _tabController;
  late ScrollController _scrollController;

  int _tabIndex = 0;
  List<BookChapter> _allChapters = [];
  List<BookChapter> _filteredChapters = [];
  bool _isLoading = true;
  bool _reverse = false;
  bool _countWords = false;
  bool _tocChanged = false; // 本次会话是否重排过目录（通知阅读页重载）
  Map<int, int> _wordCounts = {};

  // 目录标题是否应用替换净化规则
  bool _tocUseReplace = false;
  List<ReplaceRule> _replaceRules = [];

  // 书签 Tab（E: BookmarkFragment）
  List<Bookmark> _bookmarks = [];
  String _bookmarkQuery = '';

  // 高亮 Tab
  List<BookHighlight> _highlights = [];
  String _highlightQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this)
      ..addListener(() {
        // 切换 Tab 时菜单分组随之切换；搜索按当前 Tab 分流
        if (!_tabController.indexIsChanging && mounted) {
          setState(() => _tabIndex = _tabController.index);
        }
      });
    _scrollController = ScrollController();
    _loadCountWordsPref();
    _loadTocUseReplace();
    _loadChapters();
    _loadBookmarks();
    _loadHighlights();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadChapters() async {
    if (widget.chapters != null) {
      _allChapters = widget.chapters!;
    } else if (widget.book != null) {
      _allChapters = await _db.getChapters(widget.book!.name, widget.book!.author);
    }
    _filteredChapters = _allChapters;
    if (mounted) setState(() => _isLoading = false);
    // 滚动到当前章节
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.currentIndex < _allChapters.length && _scrollController.hasClients) {
        _scrollController.animateTo(
          widget.currentIndex * 56.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  Future<void> _loadBookmarks() async {
    final book = widget.book;
    try {
      final list = book != null
          ? await _db.getBookmarks(book.name, book.author)
          : await _db.getBookmarks();
      if (mounted) setState(() => _bookmarks = list);
    } catch (_) {
      if (mounted) setState(() => _bookmarks = []);
    }
  }

  /// 高亮 Tab 数据源：DatabaseService().getBookHighlights(bookName, author)（§3.B4）
  Future<void> _loadHighlights() async {
    final book = widget.book;
    try {
      final list = book != null
          ? await _db.getBookHighlights(book.name, book.author)
          : <BookHighlight>[];
      if (mounted) setState(() => _highlights = list);
    } catch (_) {
      if (mounted) setState(() => _highlights = []);
    }
  }

  Future<void> _deleteHighlight(BookHighlight h) async {
    if (h.id == null) return;
    await _db.deleteBookHighlight(h.id!);
    await _loadHighlights();
  }

  List<Bookmark> get _filteredBookmarks {
    if (_bookmarkQuery.isEmpty) return _bookmarks;
    final q = _bookmarkQuery.toLowerCase();
    return _bookmarks
        .where((b) =>
            b.chapterTitle.toLowerCase().contains(q) ||
            (b.content ?? '').toLowerCase().contains(q))
        .toList();
  }

  List<BookHighlight> get _filteredHighlights {
    if (_highlightQuery.isEmpty) return _highlights;
    final q = _highlightQuery.toLowerCase();
    return _highlights
        .where((h) =>
            h.content.toLowerCase().contains(q) ||
            h.chapterTitle.toLowerCase().contains(q) ||
            h.note.toLowerCase().contains(q))
        .toList();
  }

  void _filterChapters(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredChapters = _allChapters;
      } else {
        _filteredChapters = _allChapters
            .where((c) => c.title.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  void _onSearchChanged(String query) {
    // 按当前 Tab 分流（目录 / 书签 / 高亮）
    if (_tabIndex == 0) {
      _filterChapters(query);
    } else if (_tabIndex == 1) {
      setState(() => _bookmarkQuery = query);
    } else {
      setState(() => _highlightQuery = query);
    }
  }

  /// 读取「显示章节字数」开关（prefs tocCountWords，默认 false）。
  Future<void> _loadCountWordsPref() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getBool('tocCountWords') ?? false;
    if (!mounted) return;
    setState(() => _countWords = value);
    if (value) await _loadWordCounts();
  }

  /// 单次聚合查询各章节 content 长度（避免逐章 N+1 查询）。
  Future<void> _loadWordCounts() async {
    final book = widget.book;
    if (book == null) return;
    try {
      final db = await _db.database;
      final rows = await db.rawQuery(
        'SELECT chapter_index AS idx, LENGTH(content) AS len '
        'FROM book_chapters WHERE bookName = ? AND bookAuthor = ?',
        [book.name, book.author],
      );
      final map = <int, int>{};
      for (final row in rows) {
        final idx = row['idx'] as int?;
        final len = row['len'] as int?;
        if (idx != null && len != null && len > 0) map[idx] = len;
      }
      if (mounted) setState(() => _wordCounts = map);
    } catch (_) {
      // 查询失败静默降级：不显示字数
    }
  }

  Future<void> _toggleCountWords(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('tocCountWords', value);
    if (!mounted) return;
    setState(() => _countWords = value);
    if (value) await _loadWordCounts();
  }

  /// 读取并使用「目录标题替换」
  Future<void> _loadTocUseReplace() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getBool('tocUiUseReplace') ?? false;
    if (value) {
      try {
        _replaceRules = await _db.getReplaceRules();
      } catch (_) {}
    }
    if (mounted) setState(() => _tocUseReplace = value);
  }

  Future<void> _toggleTocUseReplace() async {
    final next = !_tocUseReplace;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('tocUiUseReplace', next);
    if (next && _replaceRules.isEmpty) {
      try {
        _replaceRules = await _db.getReplaceRules();
      } catch (_) {}
    }
    if (mounted) setState(() => _tocUseReplace = next);
  }

  /// 章节标题按替换规则处理
  String _displayTitle(String raw) {
    if (!_tocUseReplace || _replaceRules.isEmpty) return raw;
    // 目录标题走 scopeTitle 通道（上游 ReplaceRuleDao.findEnabledByTitleScope），
    // 并同时传书名与书源 origin 供 scope / excludeScope 匹配。
    return ReplaceRuleService().applyRules(
      raw,
      _replaceRules,
      scope: widget.book?.origin,
      name: widget.book?.name,
      isTitle: true,
    );
  }

  /// 是否本地 TXT
  bool get _isLocalTxt =>
      widget.book != null &&
      widget.book!.local &&
      (widget.book!.fileName?.toLowerCase().endsWith('.txt') ?? false);

  /// 切换长章节拆分（E: menu_split_long_chapter）：
  /// 重新解析目录入库 → 刷新列表 → 以 (index, tocChanged) 通知阅读页重载目录。
  Future<void> _toggleSplitLongChapter() async {
    final book = widget.book;
    if (book == null || !_isLocalTxt) return;
    final next = !book.splitLongChapter;
    try {
      final chapters = await runWithBusyDialog<List<BookChapter>>(
        context,
        message: '正在重新解析目录...',
        task: (() async {
          await ImportBookService.toggleSplitLongChapter(book, _db);
          return _db.getChapters(book.name, book.author);
        })(),
      );
      if (!mounted) return;
      setState(() {
        _allChapters = chapters;
        _filteredChapters = chapters;
        _tocChanged = true;
      });
      if (_countWords) await _loadWordCounts();
      if (!mounted) return;
      // E: need_more_time_load_content
      if (next) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已重新解析目录')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正文过长时加载可能需要更多时间')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('重新解析失败: $e')));
    }
  }

  /// 导出书签
  Future<void> _exportBookmarks(bool markdown) async {
    if (_bookmarks.isEmpty) {
      _tip('暂无书签可导出');
      return;
    }
    try {
      final file = await exportBookmarks(
        _bookmarks,
        bookName: widget.book?.name,
        bookAuthor: widget.book?.author,
        markdown: markdown,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('已导出: ${file.path}'),
        action: SnackBarAction(
          label: '分享',
          onPressed: () => Share.shareXFiles([XFile(file.path)], subject: '书签导出'),
        ),
      ));
    } catch (e) {
      _tip('导出失败: $e');
    }
  }

  Future<void> _deleteBookmark(Bookmark bm) async {
    if (bm.id == null) return;
    await _db.deleteBookmark(bm.id!);
    await _loadBookmarks();
  }

  /// 日志：展示本书目录诊断信息
  void _showLog() {
    showDialog(context: context, builder: (c) => AlertDialog(
      title: const Text('日志'),
      content: SingleChildScrollView(child: Text(
        '书名：${widget.book?.name ?? '-'}\n作者：${widget.book?.author ?? '-'}\n'
        '来源：${widget.book?.originName ?? widget.book?.origin ?? '本地'}\n'
        '目录地址：${widget.book?.noteUrl ?? ''}\n'
        '章节数：${_allChapters.length}\n书签数：${_bookmarks.length}',
        style: const TextStyle(fontSize: 12, height: 1.5),
      )),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭'))],
    ));
  }

  void _tip(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  static String _formatCount(int n) {
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万字';
    return '$n字';
  }

  /// 菜单项按当前 Tab 分组
  List<PopupMenuEntry<String>> _menuItems() {
    if (_tabIndex == 0) {
      // 目录 Tab：menu_group_toc + menu_group_text（本地 TXT） + menu_log
      return <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(value: 'reverse', child: Text('反转顺序')),
        CheckedPopupMenuItem<String>(
          value: 'useReplace',
          checked: _tocUseReplace,
          child: const Text('使用替换'),
        ),
        CheckedPopupMenuItem<String>(
          value: 'countWords',
          checked: _countWords,
          child: const Text('显示章节字数'),
        ),
        if (_isLocalTxt) ...[
          const PopupMenuDivider(),
          // 复用全局 TXT 目录规则页
          const PopupMenuItem<String>(value: 'tocRegex', child: Text('TXT目录规则')),
          CheckedPopupMenuItem<String>(
            value: 'splitLongChapter',
            checked: widget.book!.splitLongChapter,
            child: const Text('长章节拆分'),
          ),
        ],
        const PopupMenuDivider(),
        const PopupMenuItem<String>(value: 'log', child: Text('日志')),
      ];
    }
    if (_tabIndex == 1) {
      // 书签 Tab：menu_group_bookmark + menu_log
      return <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(value: 'export', child: Text('导出')),
        const PopupMenuItem<String>(value: 'exportMd', child: Text('导出(MD)')),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(value: 'log', child: Text('日志')),
      ];
    }
    // 高亮 Tab：仅「日志」（高亮无书签导出语义，避免死开关）
    return <PopupMenuEntry<String>>[
      const PopupMenuItem<String>(value: 'log', child: Text('日志')),
    ];
  }

  Future<void> _onMenuSelected(String value) async {
    switch (value) {
      case 'reverse':
        setState(() => _reverse = !_reverse);
        break;
      case 'useReplace':
        await _toggleTocUseReplace();
        break;
      case 'countWords':
        await _toggleCountWords(!_countWords);
        break;
      case 'tocRegex':
        if (!mounted) return;
        await Navigator.push(context,
            MaterialPageRoute(builder: (_) => const TxtTocRuleScreen()));
        break;
      case 'splitLongChapter':
        await _toggleSplitLongChapter();
        break;
      case 'export':
        await _exportBookmarks(false);
        break;
      case 'exportMd':
        await _exportBookmarks(true);
        break;
      case 'log':
        _showLog();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.book?.name ?? '目录'),
        actions: [
          PopupMenuButton<String>(
            tooltip: _tabIndex == 0
                ? '目录选项'
                : _tabIndex == 1 ? '书签选项' : '高亮选项',
            onSelected: _onMenuSelected,
            itemBuilder: (_) => _menuItems(),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: '目录'), Tab(text: '书签'), Tab(text: '高亮')],
        ),
      ),
      body: Column(
        children: [
          // 搜索框对当前 Tab 生效
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.l, AppSpacing.s, AppSpacing.l, AppSpacing.s),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: _tabIndex == 0
                    ? '搜索章节...'
                    : _tabIndex == 1 ? '搜索书签...' : '搜索高亮...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: '清除搜索',
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        })
                    : null,
                border: const OutlineInputBorder(borderRadius: AppRadius.mAll),
                isDense: true,
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildChapterTab(),
                _buildBookmarkTab(),
                _buildHighlightTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChapterTab() {
    if (_isLoading) return const AppLoadingIndicator();
    final chapters = _reverse ? _filteredChapters.reversed.toList() : _filteredChapters;
    if (chapters.isEmpty) {
      return const AppEmptyState(icon: Icons.list_alt_outlined, title: '暂无章节');
    }
    return ListView.builder(
      controller: _scrollController,
      itemCount: chapters.length,
      itemBuilder: (context, index) {
        final chapter = chapters[index];
        final realIndex = _allChapters.indexOf(chapter);
        final isCurrent = realIndex == widget.currentIndex;
        final chapterLen = _countWords ? (_wordCounts[chapter.index] ?? 0) : 0;
        if (chapter.isVolume) {
          return Container(
            color: Theme.of(context).colorScheme.secondaryContainer,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l, vertical: AppSpacing.s),
            child: Text(_displayTitle(chapter.title), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          );
        }
        return ListTile(
          dense: true,
          title: Text(_displayTitle(chapter.title), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: isCurrent ? Theme.of(context).colorScheme.primary : null, fontWeight: isCurrent ? FontWeight.bold : null)),
          trailing: chapterLen > 0 || isCurrent
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (chapterLen > 0)
                      Text(_formatCount(chapterLen),
                          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
                    if (isCurrent) const Icon(Icons.play_arrow, size: 16),
                  ],
                )
              : null,
          onTap: () {
            // (章索引, 目录是否被重排)：阅读页据此决定是否重载目录
            Navigator.pop(context, (realIndex, _tocChanged));
          },
        );
      },
    );
  }

  Widget _buildBookmarkTab() {
    final items = _filteredBookmarks;
    if (items.isEmpty) {
      return const AppEmptyState(
        icon: Icons.bookmark_border,
        title: '暂无书签',
        message: '阅读时点击书签按钮添加',
      );
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final bm = items[index];
        return ListTile(
          leading: const Icon(Icons.bookmark),
          title: Text(bm.chapterTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: (bm.content ?? '').isNotEmpty
              ? Text(bm.content!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))
              : null,
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '删除书签',
            onPressed: () => _deleteBookmark(bm),
          ),
          onTap: () {
            // 返回书签所在章索引，目录未重排
            Navigator.pop(context, (bm.chapterIndex, false));
          },
        );
      },
    );
  }

  /// 高亮 Tab：展示划线文本 + 章名，点击跳到该章（§3.B4）。
  Widget _buildHighlightTab() {
    final items = _filteredHighlights;
    if (items.isEmpty) {
      return const AppEmptyState(
        icon: Icons.highlight_outlined,
        title: '暂无高亮',
        message: '阅读时长按选中文本可添加划线 / 高亮',
      );
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final h = items[index];
        final chapterLabel = h.chapterTitle.isNotEmpty
            ? h.chapterTitle
            : '第${h.chapterIndex + 1}章';
        return ListTile(
          leading: Icon(Icons.format_color_text,
              color: Theme.of(context).colorScheme.primary),
          title: Text(
            h.content.isNotEmpty ? h.content : '（划线内容）',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(chapterLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
              if (h.note.isNotEmpty)
                Text('批注：${h.note}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '删除高亮',
            onPressed: () => _deleteHighlight(h),
          ),
          onTap: () {
            // 返回高亮所在章索引，目录未重排
            Navigator.pop(context, (h.chapterIndex, false));
          },
        );
      },
    );
  }
}
