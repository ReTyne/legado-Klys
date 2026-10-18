import 'package:flutter/material.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/local/app_database.dart';

class CacheManageScreen extends StatefulWidget {
  const CacheManageScreen({super.key});

  @override
  State<CacheManageScreen> createState() => _CacheManageScreenState();
}

class _CacheManageScreenState extends State<CacheManageScreen> {
  final _db = DatabaseService();
  List<Book> _books = [];
  Map<String, int> _chapterCounts = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCache();
  }

  Future<void> _loadCache() async {
    setState(() => _isLoading = true);
    _books = await _db.getAllBooks();
    _chapterCounts = {};
    for (final book in _books) {
      final chapters = await _db.getChapters(book.name, book.author);
      final cached = chapters.where((c) => c.content != null && c.content!.isNotEmpty).toList();
      _chapterCounts['${book.name}_${book.author}'] = cached.length;
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _clearBookCache(Book book) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除缓存'),
        content: Text('确定要清除《${book.name}》的所有章节缓存吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('清除')),
        ],
      ),
    );
    if (confirmed == true) {
      await _db.clearBookChapterContent(book.name, book.author);
      _loadCache();
    }
  }

  Future<void> _clearAllCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除全部缓存'),
        content: const Text('确定要清除所有书籍的章节缓存吗？此操作不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('全部清除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      // 清空全部章节正文缓存（与具体书籍无关，执行一次即可）
      await _db.clearChapterContent();
      _loadCache();
    }
  }

  int get _totalCachedChapters => _chapterCounts.values.fold(0, (a, b) => a + b);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('缓存管理'),
        actions: [
          if (_books.isNotEmpty)
            TextButton(
              onPressed: _clearAllCache,
              child: const Text('全部清除'),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _books.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.cleaning_services, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text('没有缓存的书籍', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: Theme.of(context).colorScheme.primaryContainer,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('共 ${_books.length} 本书'),
                          Text('已缓存 $_totalCachedChapters 章'),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        itemCount: _books.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final book = _books[index];
                          final cached = _chapterCounts['${book.name}_${book.author}'] ?? 0;
                          return ListTile(
                            leading: book.coverUrl != null && book.coverUrl!.isNotEmpty
                                ? Image.network(book.coverUrl!, width: 40, height: 60, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _buildDefaultCover())
                                : _buildDefaultCover(),
                            title: Text(book.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text('${book.author} · 已缓存 $cached 章'),
                            trailing: cached > 0
                                ? TextButton(
                                    onPressed: () => _clearBookCache(book),
                                    child: const Text('清除'),
                                  )
                                : const Text('无缓存', style: TextStyle(color: Colors.grey, fontSize: 12)),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildDefaultCover() {
    return Container(
      width: 40,
      height: 60,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Icon(Icons.book, size: 20, color: Colors.grey),
    );
  }
}
