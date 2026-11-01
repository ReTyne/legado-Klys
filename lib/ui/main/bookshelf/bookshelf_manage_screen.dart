import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/di/book_provider.dart';
import 'package:legado_md3/help/source/source_engine.dart';

/// 书架管理 —— 对齐 legado-E `ui/book/manage/BookshelfManageActivity.kt`。
///
/// 功能位置与 E 一致：
/// - 顶栏：标题「书架管理」+ 搜索过滤（书名/作者）+ 全选/反选
/// - 列表：勾选框 + 封面 + 书名/作者，拖动右侧手柄手动排序（持久化 order）
/// - 底部操作栏（E 的 SelectActionBar）：移动到分组 / 缓存 / 导出 / 删除
///
/// 书架主页的「多选模式」「清空书架」入口已迁移到本页，与 E 的菜单结构保持一致。
class BookshelfManageScreen extends StatefulWidget {
  const BookshelfManageScreen({super.key});

  @override
  State<BookshelfManageScreen> createState() => _BookshelfManageScreenState();
}

class _BookshelfManageScreenState extends State<BookshelfManageScreen> {
  final DatabaseService _db = DatabaseService();
  final BookSourceEngine _engine = BookSourceEngine();
  final TextEditingController _searchController = TextEditingController();

  List<Book> _books = [];
  List<Book> _visible = [];
  final Set<Book> _selected = {};
  String _query = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final provider = Provider.of<BookProvider>(context, listen: false);
    final books = List<Book>.of(provider.books);
    books.sort((a, b) {
      final pa = (a.order ?? 0) < 0 ? -1 : 0;
      final pb = (b.order ?? 0) < 0 ? -1 : 0;
      if (pa != pb) return pa.compareTo(pb);
      final oa = a.order ?? 0;
      final ob = b.order ?? 0;
      if (oa != ob) return oa.compareTo(ob);
      return b.durChapterTime.compareTo(a.durChapterTime);
    });
    if (!mounted) return;
    setState(() {
      _books = books;
      _loading = false;
    });
    _applyFilter();
  }

  void _applyFilter() {
    final q = _query.toLowerCase();
    setState(() {
      _visible = q.isEmpty
          ? List.of(_books)
          : _books
              .where((b) =>
                  b.name.toLowerCase().contains(q) ||
                  b.author.toLowerCase().contains(q))
              .toList();
    });
  }

  void _toggle(Book book) {
    setState(() {
      if (_selected.contains(book)) {
        _selected.remove(book);
      } else {
        _selected.add(book);
      }
    });
  }

  void _selectAll() =>
      setState(() => _selected..clear()..addAll(_visible));

  void _invert() {
    final all = _visible.toSet();
    setState(() {
      final inverted = all.difference(_selected);
      _selected
        ..clear()
        ..addAll(inverted);
    });
  }

  void _exitSelectMode() => setState(() => _selected.clear());

  // ---------- 批量操作（与书架页批量逻辑一致，集中到管理页） ----------

  Future<void> _batchMoveGroup() async {
    final provider = Provider.of<BookProvider>(context, listen: false);
    final groups = provider.displayGroups()
        .where((g) => g != '全部' && !BookProvider.isVirtualGroup(g))
        .toList();
    final controller = TextEditingController();
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移动到分组'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final g in groups)
              ActionChip(label: Text(g), onPressed: () => _doMoveGroup(g)),
            ActionChip(label: const Text('未分组'), onPressed: () => _doMoveGroup(null)),
          ]),
          const SizedBox(height: 12),
          TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: '新分组名称')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final g = controller.text.trim();
              if (g.isEmpty) return;
              Navigator.pop(context);
              _doMoveGroup(g);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _doMoveGroup(String? group) async {
    final provider = Provider.of<BookProvider>(context, listen: false);
    for (final b in _selected) {
      b.group = group;
      await _db.updateBook(b);
    }
    if (!mounted) return;
    Navigator.pop(context);
    await provider.loadBooks();
    _exitSelectMode();
    await _load();
  }

  Future<void> _batchCache() async {
    final picked = List.of(_selected);
    _exitSelectMode();
    int ok = 0, fail = 0, done = 0;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (d) => StatefulBuilder(builder: (d, setP) {
        _cacheBooks(picked, (o, f, dd) {
          if (!mounted) return;
          setP(() {
            ok = o;
            fail = f;
            done = dd;
          });
        });
        return AlertDialog(
          title: const Text('批量缓存'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            LinearProgressIndicator(value: picked.isEmpty ? 0 : done / picked.length),
            const SizedBox(height: 12),
            Text('进度 $done/${picked.length}，成功 $ok 章，失败 $fail 章'),
          ]),
        );
      }),
    );
  }

  Future<void> _cacheBooks(List<Book> books,
      void Function(int ok, int fail, int done) onProgress) async {
    int ok = 0, fail = 0;
    for (var i = 0; i < books.length; i++) {
      final r = await _cacheBook(books[i]);
      ok += r.ok;
      fail += r.fail;
      onProgress(ok, fail, i + 1);
    }
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('批量缓存完成: 成功$ok章${fail > 0 ? ', 失败$fail章' : ''}')));
  }

  Future<({int ok, int fail})> _cacheBook(Book book) async {
    int ok = 0, fail = 0;
    if (book.local || book.origin == null || book.noteUrl == null) {
      return (ok: ok, fail: fail);
    }
    final sources = await _db.getAllSources(enabled: true);
    final source = sources.where((s) => s.bookSourceUrl == book.origin).firstOrNull;
    if (source == null) return (ok: ok, fail: fail);
    final chapters = await _db.getChapters(book.name, book.author);
    for (final ch in chapters) {
      if (ch.isVolume || (ch.content ?? '').isNotEmpty) continue;
      try {
        final content = await _engine.getContent(source, ch.url,
            bookInfo: book.jsContext(), chapter: ch.jsContext(book.bookUrl));
        if (content != null && content.isNotEmpty) {
          await _db.updateChapterContent(book.name, book.author, ch.index, content);
          ok++;
        } else {
          fail++;
        }
      } catch (_) {
        fail++;
      }
    }
    return (ok: ok, fail: fail);
  }

  Future<void> _batchExport() async {
    final picked = List.of(_selected);
    _exitSelectMode();
    int ok = 0;
    for (final book in picked) {
      try {
        final chapters = await _db.getChapters(book.name, book.author);
        final buf = StringBuffer()
          ..writeln('《${book.name}》 作者:${book.author}')
          ..writeln(book.intro ?? '')
          ..writeln('\n');
        for (final ch in chapters) {
          buf.writeln(ch.title);
          buf.writeln(ch.content ?? '');
          buf.writeln('');
        }
        final safe = book.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        final file = File('${Directory.systemTemp.path}/$safe.txt');
        await file.writeAsString(buf.toString());
        await Share.shareXFiles([XFile(file.path)], text: '《${book.name}》导出');
        ok++;
      } catch (_) {}
    }
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已导出 $ok 本')));
    }
  }

  Future<void> _batchDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除书籍'),
        content: Text('确定删除选中的 ${_selected.length} 本书吗？将同时删除已缓存章节。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      for (final book in _selected) {
        await _db.deleteBook(book.name, book.author);
      }
      final provider = Provider.of<BookProvider>(context, listen: false);
      await provider.loadBooks();
      _exitSelectMode();
      await _load();
    }
  }

  // ---------- 手动排序（对齐 E 的 ItemTouchHelper 拖拽排序） ----------

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    final list = List<Book>.of(_visible);
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    setState(() {
      _visible = list;
      // 同步回全量列表，保持两者顺序一致
      _books = list;
    });
    // 持久化 order：按当前可见顺序连续赋值（置顶书籍 order<0 保持不变）
    int seq = 0;
    for (final b in _visible) {
      if ((b.order ?? 0) < 0) continue;
      b.order = seq++;
      await _db.updateBook(b);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: _selected.isEmpty
            ? const Text('书架管理')
            : Text('已选 ${_selected.length} 本'),
        actions: [
          if (_selected.isEmpty) ...[
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () async {
                final q = await showSearch<String>(
                  context: context,
                  delegate: _BookSearchDelegate(_books),
                );
                if (q != null) {
                  _searchController.text = q;
                  setState(() => _query = q);
                  _applyFilter();
                }
              },
            ),
          ] else ...[
            IconButton(icon: const Icon(Icons.select_all), tooltip: '全选', onPressed: _selectAll),
            IconButton(icon: const Icon(Icons.flip), tooltip: '反选', onPressed: _invert),
            IconButton(icon: const Icon(Icons.close), tooltip: '退出多选', onPressed: _exitSelectMode),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _visible.isEmpty
              ? Center(
                  child: Text(_query.isEmpty ? '书架为空' : '没有匹配的书籍',
                      style: TextStyle(color: cs.onSurfaceVariant)))
              : ReorderableListView.builder(
                  padding: const EdgeInsets.only(bottom: 12),
                  buildDefaultDragHandles: false,
                  itemCount: _visible.length,
                  onReorder: _onReorder,
                  itemBuilder: (context, i) {
                    final book = _visible[i];
                    final selected = _selected.contains(book);
                    return ListTile(
                      key: ValueKey('${book.name}::${book.author}'),
                      leading: Row(mainAxisSize: MainAxisSize.min, children: [
                        Checkbox(value: selected, onChanged: (_) => _toggle(book)),
                        _buildThumb(book),
                      ]),
                      title: Text(book.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                          '${book.author}${book.local ? ' · 本地' : ''}${(book.lastChapter ?? '').isEmpty ? '' : ' · ${book.lastChapter}'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12)),
                      trailing: ReorderableDragStartListener(
                        index: i,
                        child: const Icon(Icons.drag_handle),
                      ),
                      selected: selected,
                      onTap: () => _toggle(book),
                    );
                  },
                ),
      bottomNavigationBar: _selected.isEmpty
          ? null
          : SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Divider(height: 1),
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  _batchBtn(Icons.drive_file_move_outline, '移动分组', _batchMoveGroup),
                  _batchBtn(Icons.cloud_download_outlined, '缓存', _batchCache),
                  _batchBtn(Icons.file_upload_outlined, '导出', _batchExport),
                  _batchBtn(Icons.delete_sweep_outlined, '删除', _batchDelete, danger: true),
                ]),
              ]),
            ),
    );
  }

  Widget _buildThumb(Book book) {
    final url = (book.customCoverUrl != null && book.customCoverUrl!.isNotEmpty)
        ? book.customCoverUrl
        : book.coverUrl;
    if (url == null || url.isEmpty) {
      return Container(
        width: 36,
        height: 50,
        decoration: BoxDecoration(
          color: const Color(0xFF607D8B),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Icon(Icons.book, size: 18, color: Colors.white),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: CachedNetworkImage(
        imageUrl: url,
        width: 36,
        height: 50,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => Container(
          width: 36,
          height: 50,
          color: const Color(0xFF607D8B),
          child: const Icon(Icons.book, size: 18, color: Colors.white),
        ),
      ),
    );
  }

  Widget _batchBtn(IconData icon, String label, VoidCallback onTap,
      {bool danger = false}) {
    final color = danger ? Theme.of(context).colorScheme.error : null;
    return TextButton.icon(
      onPressed: _selected.isEmpty ? null : onTap,
      icon: Icon(icon, size: 20, color: color),
      label: Text(label, style: TextStyle(color: color, fontSize: 13)),
    );
  }
}

/// 书架管理内搜索（对齐 E BookshelfManageActivity 的 SearchView）
class _BookSearchDelegate extends SearchDelegate<String> {
  final List<Book> books;
  _BookSearchDelegate(this.books);

  @override
  List<Widget> buildActions(BuildContext context) => [
        IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () => query = ''),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, ''),
      );

  @override
  Widget buildResults(BuildContext context) => _buildList();

  @override
  Widget buildSuggestions(BuildContext context) => _buildList();

  Widget _buildList() {
    final q = query.toLowerCase();
    final result = q.isEmpty
        ? books
        : books
            .where((b) =>
                b.name.toLowerCase().contains(q) ||
                b.author.toLowerCase().contains(q))
            .toList();
    return ListView.builder(
      itemCount: result.length,
      itemBuilder: (context, i) {
        final b = result[i];
        return ListTile(
          title: Text(b.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(b.author, maxLines: 1),
          onTap: () => close(context, b.name),
        );
      },
    );
  }
}
