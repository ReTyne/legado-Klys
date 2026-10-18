import 'package:flutter/material.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book.dart';

/// 下载管理 - 查看每本书已缓存章节，支持清理缓存
class DownloadManageScreen extends StatefulWidget {
  const DownloadManageScreen({super.key});

  @override
  State<DownloadManageScreen> createState() => _DownloadManageScreenState();
}

class _DownloadManageScreenState extends State<DownloadManageScreen> {
  final DatabaseService _db = DatabaseService();
  List<Book> _books = [];
  final Map<String, int> _cachedCount = {};
  final Map<String, int> _totalCount = {};
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final books = await _db.getAllBooks();
    final counts = <String, int>{};
    final totals = <String, int>{};
    for (final b in books) {
      final chapters = await _db.getChapters(b.name, b.author);
      final cached = chapters.where((ch) => ch.content != null && ch.content!.isNotEmpty).length;
      totals['${b.name}-${b.author}'] = chapters.length;
      if (cached > 0) counts['${b.name}-${b.author}'] = cached;
    }
    if (mounted) setState(() { _books = books; _cachedCount..clear()..addAll(counts); _totalCount..clear()..addAll(totals); _loading = false; });
  }

  Future<void> _clearBookCache(Book book) async {
    final chapters = await _db.getChapters(book.name, book.author);
    for (var i = 0; i < chapters.length; i++) {
      await _db.updateChapterContent(book.name, book.author, i, '');
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已清理《${book.name}》缓存')));
      _load();
    }
  }

  Future<void> _clearAll() async {
    final confirm = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('清空所有缓存'),
      content: const Text('确定清空全部已下载章节内容？此操作不可恢复。'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('清空'))],
    ));
    if (confirm != true) return;
    for (final b in _books) {
      final chapters = await _db.getChapters(b.name, b.author);
      for (var i = 0; i < chapters.length; i++) {
        await _db.updateChapterContent(b.name, b.author, i, '');
      }
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final entries = _books.where((b) => (_cachedCount['${b.name}-${b.author}'] ?? 0) > 0).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('下载管理'),
        actions: [
          if (entries.isNotEmpty) IconButton(tooltip: '清空缓存', icon: const Icon(Icons.delete_sweep), onPressed: _clearAll),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : entries.isEmpty
              ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.download_done, size: 64, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('暂无已下载内容', style: TextStyle(color: Colors.grey)),
                ]))
              : ListView.separated(
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final book = entries[i];
                    final count = _cachedCount['${book.name}-${book.author}'] ?? 0;
                    final total = _totalCount['${book.name}-${book.author}'] ?? 0;
                    return ListTile(
                      leading: const Icon(Icons.menu_book_outlined),
                      title: Text(book.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('已缓存 $count 章${total > 0 ? ' / 共 $total 章' : ''}'),
                      trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _clearBookCache(book)),
                    );
                  },
                ),
    );
  }
}
