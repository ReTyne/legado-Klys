import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:legado_md3/data/model/bookmark.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/ui/bookmark/bookmark_export.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';

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

  /// 导出书签（对齐 legado-E TocViewModel.saveBookmark / saveBookmarkMd）：
  /// 复用 bookmark_export.dart，与目录页书签 Tab 共用同一导出逻辑。
  Future<void> _exportBookmarks({required bool markdown}) async {
    if (_bookmarks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('暂无书签可导出')));
      return;
    }
    try {
      final file = await exportBookmarks(
        _bookmarks,
        bookName: widget.bookName,
        bookAuthor: widget.bookAuthor,
        markdown: markdown,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('已导出: ${file.path}'),
        action: SnackBarAction(
          label: '分享',
          onPressed: () => Share.shareXFiles([XFile(file.path)],
              subject: '书签导出'),
        ),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('导出失败: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.bookName != null ? '《${widget.bookName}》书签' : '全部书签'),
        actions: [
          PopupMenuButton<String>(
            tooltip: '导出书签',
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              switch (v) {
                case 'json':
                  _exportBookmarks(markdown: false);
                case 'md':
                  _exportBookmarks(markdown: true);
              }
            },
            itemBuilder: (c) => const [
              PopupMenuItem(value: 'json', child: Text('导出为 JSON')),
              PopupMenuItem(value: 'md', child: Text('导出为 Markdown')),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _bookmarks.isEmpty
              ? const AppEmptyState(
                  icon: Icons.bookmark_border,
                  title: '暂无书签',
                  message: '阅读时点击书签按钮添加',
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
                        color: cs.error,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 16),
                        child: Icon(Icons.delete, color: cs.onError),
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
                              Text(bookmark.bookName, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                            if (bookmark.content != null && bookmark.content!.isNotEmpty)
                              Text(
                                bookmark.content!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                            Text(
                              DateTime.fromMillisecondsSinceEpoch(bookmark.createTime).toString().substring(0, 16),
                              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                        trailing: widget.onSelect != null
                            ? const Icon(Icons.chevron_right)
                            : IconButton(
                                tooltip: '删除书签',
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
