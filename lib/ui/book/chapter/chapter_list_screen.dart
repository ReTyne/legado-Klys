import 'package:flutter/material.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_chapter.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/help/storage/import_book_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChapterListScreen extends StatefulWidget {
  final Book? book;
  final List<BookChapter>? chapters;
  final int currentIndex;

  const ChapterListScreen({super.key, this.book, this.chapters, this.currentIndex = 0});

  @override
  State<ChapterListScreen> createState() => _ChapterListScreenState();
}

class _ChapterListScreenState extends State<ChapterListScreen> {
  final DatabaseService _db = DatabaseService();
  final TextEditingController _searchController = TextEditingController();
  List<BookChapter> _allChapters = [];
  List<BookChapter> _filteredChapters = [];
  bool _isLoading = true;
  bool _reverse = false;
  bool _countWords = false;
  bool _tocChanged = false; // 本次会话是否重排过目录（通知阅读页重载）
  Map<int, int> _wordCounts = {};
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _loadCountWordsPref();
    _loadChapters();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
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
      if (widget.currentIndex < _allChapters.length) {
        _scrollController.animateTo(
          widget.currentIndex * 56.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void _filterChapters(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredChapters = _allChapters;
      } else {
        _filteredChapters = _allChapters.where((c) => c.title.toLowerCase().contains(query.toLowerCase())).toList();
      }
    });
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

  /// 是否本地 TXT（长章节拆分仅对此生效，对齐 E isLocalTxt 判断）
  bool get _isLocalTxt =>
      widget.book != null &&
      widget.book!.local &&
      (widget.book!.fileName?.toLowerCase().endsWith('.txt') ?? false);

  /// 切换长章节拆分（E: TocActivity menu_split_long_chapter）：
  /// 重新解析目录入库 → 刷新列表 → 以 (index, tocChanged) 通知阅读页重载目录。
  Future<void> _toggleSplitLongChapter() async {
    final book = widget.book;
    if (book == null || !_isLocalTxt) return;
    final next = !book.splitLongChapter;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: Card(child: Padding(padding: EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 12), Text('正在重新解析目录...')])))),
    );
    try {
      await ImportBookService.toggleSplitLongChapter(book, _db);
      final chapters = await _db.getChapters(book.name, book.author);
      if (!mounted) return;
      setState(() {
        _allChapters = chapters;
        _filteredChapters = chapters;
        _tocChanged = true;
      });
      if (_countWords) await _loadWordCounts();
      // E: need_more_time_load_content
      if (next) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已重新解析目录')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正文过长时加载可能需要更多时间')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('重新解析失败: $e')));
    } finally {
      if (mounted) Navigator.pop(context); // 关闭忙碌对话框
    }
  }

  static String _formatCount(int n) {
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万字';
    return '$n字';
  }

  @override
  Widget build(BuildContext context) {
    final chapters = _reverse ? _filteredChapters.reversed.toList() : _filteredChapters;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.book?.name ?? '目录'),
        actions: [
          IconButton(
            icon: Icon(_reverse ? Icons.swap_vert : Icons.swap_vert),
            onPressed: () => setState(() => _reverse = !_reverse),
            tooltip: '反转顺序',
          ),
          PopupMenuButton<String>(
            tooltip: '目录选项',
            onSelected: (value) {
              if (value == 'reverse') setState(() => _reverse = !_reverse);
            },
            itemBuilder: (context) => [
              const PopupMenuItem<String>(
                value: 'reverse',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.swap_vert),
                  title: Text('反转顺序'),
                ),
              ),
              CheckedPopupMenuItem<String>(
                value: 'countWords',
                checked: _countWords,
                onTap: () => _toggleCountWords(!_countWords),
                child: const Text('显示章节字数'),
              ),
              // 长章节拆分开关（E: menu_split_long_chapter，仅本地 TXT 可见）
              if (_isLocalTxt)
                CheckedPopupMenuItem<String>(
                  value: 'splitLongChapter',
                  checked: widget.book!.splitLongChapter,
                  onTap: () => _toggleSplitLongChapter(),
                  child: const Text('长章节拆分'),
                ),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索章节...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchController.clear(); _filterChapters(''); })
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                isDense: true,
              ),
              onChanged: _filterChapters,
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : chapters.isEmpty
              ? const Center(child: Text('暂无章节'))
              : ListView.builder(
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
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Text(chapter.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      );
                    }
                    return ListTile(
                      dense: true,
                      title: Text(chapter.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: isCurrent ? Theme.of(context).colorScheme.primary : null, fontWeight: isCurrent ? FontWeight.bold : null)),
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
                ),
    );
  }
}
