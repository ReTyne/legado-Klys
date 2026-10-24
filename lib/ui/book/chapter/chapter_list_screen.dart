import 'package:flutter/material.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_chapter.dart';
import 'package:legado_md3/data/local/app_database.dart';
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
                        Navigator.pop(context, realIndex);
                      },
                    );
                  },
                ),
    );
  }
}
