import 'package:flutter/material.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_chapter.dart';
import 'package:legado_md3/data/local/app_database.dart';

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
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
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
                      trailing: isCurrent ? const Icon(Icons.play_arrow, size: 16) : null,
                      onTap: () {
                        Navigator.pop(context, realIndex);
                      },
                    );
                  },
                ),
    );
  }
}
