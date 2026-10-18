import 'package:flutter/material.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/ui/book/detail/book_detail_screen.dart';

/// 封面相册 - 以网格展示书架所有书籍封面
class CoverAlbumScreen extends StatefulWidget {
  const CoverAlbumScreen({super.key});

  @override
  State<CoverAlbumScreen> createState() => _CoverAlbumScreenState();
}

class _CoverAlbumScreenState extends State<CoverAlbumScreen> {
  final DatabaseService _db = DatabaseService();
  List<Book> _books = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final books = await _db.getAllBooks();
    if (mounted) setState(() { _books = books; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('封面相册 (${_books.length})')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _books.isEmpty
              ? const Center(child: Text('书架暂无书籍'))
              : GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 0.72),
                  itemCount: _books.length,
                  itemBuilder: (context, i) {
                    final book = _books[i];
                    return GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BookDetailScreen(book: book))),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Expanded(child: _cover(book)),
                        const SizedBox(height: 4),
                        Text(book.name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11)),
                      ]),
                    );
                  },
                ),
    );
  }

  Widget _cover(Book book) {
    final url = book.customCoverUrl?.isNotEmpty == true ? book.customCoverUrl! : book.coverUrl;
    if (url != null && url.isNotEmpty && url.startsWith('http')) {
      return ClipRRect(borderRadius: BorderRadius.circular(6),
        child: Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder(book)));
    }
    return _placeholder(book);
  }

  Widget _placeholder(Book book) => ClipRRect(borderRadius: BorderRadius.circular(6),
    child: Container(
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [Theme.of(context).colorScheme.primaryContainer, Theme.of(context).colorScheme.secondaryContainer])),
      child: Center(child: Padding(padding: const EdgeInsets.all(4), child: Text(book.name, maxLines: 3, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onPrimaryContainer))))));
}
