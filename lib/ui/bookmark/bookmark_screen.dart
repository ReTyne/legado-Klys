import 'package:flutter/material.dart';
import 'package:legado_md3/data/model/bookmark.dart';
import 'package:legado_md3/data/local/app_database.dart';

class BookmarkScreen extends StatefulWidget {
  final String? bookName;
  final String? bookAuthor;
  final Function(Bookmark)? onSelect;

  const BookmarkScreen({super.key, this.bookName, this.bookAuthor, this.onSelect});

  @override
  State<BookmarkScreen> createState() => _BookmarkScreenState();
}

class _BookmarkScreenState extends State<BookmarkScreen> {
  final _db = DatabaseService();
  List<Bookmark> _bookmarks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBookmarks();
  }

  Future<void> _loadBookmarks() async {
    setState(() => _isLoading = true);
    try {
      List<Bookmark> bookmarks;
      if (widget.bookName != null && widget.bookAuthor != null) {
        bookmarks = await _db.getBookmarks(widget.bookName!, widget.bookAuthor!);
      } else {
        // 获取所有书签
        final db = await _db.database;
        bookmarks = (await db.query('bookmarks', orderBy: 'createTime DESC')).map((m) => Bookmark.fromMap(m)).toList();
      }
      _bookmarks = bookmarks;
    } catch (e) {
      _bookmarks = [];
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _deleteBookmark(Bookmark bookmark) async {
    if (bookmark.id != null) {
      await _db.deleteBookmark(bookmark.id!);
      _loadBookmarks();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.bookName != null ? '《${widget.bookName}》书签' : '全部书签'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _bookmarks.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.bookmark_border, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text('暂无书签', style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 8),
                      const Text('阅读时点击书签按钮添加', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: _bookmarks.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final bookmark = _bookmarks[index];
                    return Dismissible(
                      key: Key('bookmark_${bookmark.id}'),
                      direction: DismissDirection.endToStart,
                      onDismissed: (_) => _deleteBookmark(bookmark),
                      background: Container(
                        color: Colors.red,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 16),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      child: ListTile(
                        leading: const Icon(Icons.bookmark),
                        title: Text(
                          bookmark.chapterTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (widget.bookName == null)
                              Text(bookmark.bookName, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            if (bookmark.content != null && bookmark.content!.isNotEmpty)
                              Text(
                                bookmark.content!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                            Text(
                              DateTime.fromMillisecondsSinceEpoch(bookmark.createTime).toString().substring(0, 16),
                              style: const TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                        trailing: widget.onSelect != null
                            ? const Icon(Icons.chevron_right)
                            : IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _deleteBookmark(bookmark),
                              ),
                        onTap: widget.onSelect != null
                            ? () {
                                widget.onSelect!(bookmark);
                                Navigator.pop(context);
                              }
                            : null,
                      ),
                    );
                  },
                ),
    );
  }
}
