import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/di/book_provider.dart';
import 'package:legado_md3/help/source/source_engine.dart';
import 'package:legado_md3/help/storage/download_service.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';

/// 书架管理 —— 对齐 legado-E `ui/book/manage/BookshelfManageActivity.kt`。
///
/// 顶栏：标题「书架管理」+ 搜索过滤（书名/作者）+ 全选/反选；
/// 列表：勾选框 + 封面 + 书名/作者，拖动右侧手柄手动排序（持久化 order）；
/// 底部操作栏（E 的 SelectActionBar）对齐 `menu/bookshelf_menage_sel.xml`：
/// 移动分组 / 移除分组 / 缓存 / 清理缓存 / 批量换源 / 允许更新 / 禁止更新 /
/// 导出 / 选中区间 / 删除。缓存接入 DownloadService 真实队列。
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

  /// 批量操作后统一刷新：reload provider → 退出多选 → 刷新本页列表
  Future<void> _reloadAfterBatch() async {
    if (!mounted) return;
    final provider = Provider.of<BookProvider>(context, listen: false);
    await provider.loadBooks();
    _exitSelectMode();
    await _load();
  }

  // ---------- 分组（加入 / 移除） ----------

  Future<void> _batchMoveGroup() async {
    final provider = Provider.of<BookProvider>(context, listen: false);
    final groups = provider.displayGroups()
        .where((g) => g != '全部' && !BookProvider.isVirtualGroup(g))
        .toList();
    final controller = TextEditingController();
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('移动到分组'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final g in groups)
              ActionChip(
                  label: Text(g),
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    _applyGroupToSelected(g);
                  }),
            ActionChip(
                label: const Text('未分组'),
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _applyGroupToSelected(null);
                }),
          ]),
          const SizedBox(height: 12),
          TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: '新分组名称')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final g = controller.text.trim();
              if (g.isEmpty) return;
              Navigator.pop(dialogContext);
              _applyGroupToSelected(g);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _applyGroupToSelected(String? group) async {
    for (final b in _selected) {
      b.group = group;
      await _db.updateBook(b);
    }
    if (!mounted) return;
    await _reloadAfterBatch();
  }

  Future<void> _batchRemoveGroup() async {
    await _applyGroupToSelected(null);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已移除所选书籍的分组')));
    }
  }

  // ---------- 允许 / 禁止更新 ----------

  Future<void> _setUpdateEnabled(bool enabled) async {
    final picked = List.of(_selected);
    for (final b in picked) {
      b.canUpdate = enabled;
      await _db.updateBook(b);
    }
    if (!mounted) return;
    await _reloadAfterBatch();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${enabled ? '已允许更新' : '已禁止更新'} ${picked.length} 本')));
  }

  // ---------- 缓存 / 清理缓存 ----------

  /// 批量缓存：缓存项接入 DownloadService 真实队列（enqueue），
  /// 由队列串行逐章下载并写入 book_chapters.content。
  Future<void> _batchCache() async {
    final picked = List.of(_selected);
    _exitSelectMode();
    final queued = await runWithBusyDialog<int>(
      context,
      message: '正在加入缓存队列...',
      task: () async {
        var n = 0;
        for (final b in picked) {
          if (b.local || b.origin == null || b.noteUrl == null) continue;
          final chapters = await _db.getChapters(b.name, b.author);
          if (chapters.isEmpty) continue;
          await DownloadService.instance.enqueue(b.name, b.author);
          n++;
        }
        return n;
      }(),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已将 $queued 本书加入缓存队列')));
    }
  }

  /// 清理缓存：批量缓存的反操作——逐章把已缓存正文置空，保留目录结构。
  Future<void> _batchClearCache() async {
    final picked = List.of(_selected);
    _exitSelectMode();
    final cleared = await runWithBusyDialog<int>(
      context,
      message: '正在清理缓存...',
      task: () async {
        var n = 0;
        for (final b in picked) {
          final chapters = await _db.getChapters(b.name, b.author);
          for (final ch in chapters) {
            if ((ch.content ?? '').isEmpty) continue;
            await _db.updateChapterContent(b.name, b.author, ch.index, '');
            n++;
          }
        }
        return n;
      }(),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已清理 $cleared 章缓存')));
    }
  }

  // ---------- 批量换源 ----------

  /// 选中目标书源后，对每本书在该源检索同名书并切换目录地址。
  /// 复用 change_source_screen 的换源字段逻辑（search + deleteChapters + 重置进度）。
  Future<void> _batchChangeSource() async {
    final sources = await _db.getAllSources(enabled: true);
    if (!mounted) return;
    if (sources.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('暂无可用书源，请先在书源管理中启用')));
      return;
    }
    final target = await showAppRadioDialog<BookSource>(
      context,
      title: '批量换源 · 选择目标书源',
      options: [
        for (final s in sources)
          AppRadioOption<BookSource>(s, s.bookSourceName),
      ],
      groupValue: sources.first,
    );
    if (target == null || !mounted) return;
    final picked = List.of(_selected);
    _exitSelectMode();
    var fail = 0;
    final ok = await runWithBusyDialog<int>(
      context,
      message: '正在批量换源...',
      task: () async {
        var done = 0;
        for (final b in picked) {
          if (b.local) {
            fail++;
            continue;
          }
          try {
            final list = await _engine
                .search(target, b.name)
                .timeout(const Duration(seconds: 15), onTimeout: () => []);
            final hit = list
                    .where((r) =>
                        r.name.replaceAll(RegExp(r'\s'), '') ==
                        b.name.replaceAll(RegExp(r'\s'), ''))
                    .firstOrNull ??
                (list.isNotEmpty ? list.first : null);
            if (hit == null) {
              fail++;
              continue;
            }
            b
              ..origin = target.bookSourceUrl
              ..originName = target.bookSourceName
              ..noteUrl = hit.noteUrl
              ..bookUrl = hit.bookUrl
              ..coverUrl = (hit.coverUrl?.isNotEmpty ?? false)
                  ? hit.coverUrl
                  : b.coverUrl
              ..lastChapter = (hit.lastChapter?.isNotEmpty ?? false)
                  ? hit.lastChapter
                  : b.lastChapter
              ..intro = (hit.intro?.isNotEmpty ?? false) ? hit.intro : b.intro;
            await _db.deleteChapters(b.name, b.author);
            b.durChapterIndex = 0;
            b.durChapterPos = 0;
            b.lastChapterIndex = 0;
            await _db.updateBook(b);
            done++;
          } catch (_) {
            fail++;
          }
        }
        return done;
      }(),
    );
    if (!mounted) return;
    await _reloadAfterBatch();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('批量换源完成：成功 $ok 本，失败 $fail 本')));
  }

  // ---------- 选中区间 ----------

  /// 选中区间：把当前已选书籍在可见列表中的最小/最大索引之间的书全部选中。
  void _selectRange() {
    if (_selected.isEmpty) return;
    final indices = <int>[];
    for (var i = 0; i < _visible.length; i++) {
      if (_selected.contains(_visible[i])) indices.add(i);
    }
    if (indices.isEmpty) return;
    indices.sort();
    final from = indices.first;
    final to = indices.last;
    setState(() {
      for (var i = from; i <= to; i++) {
        _selected.add(_visible[i]);
      }
    });
  }

  // ---------- 导出 ----------

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

  // ---------- 删除 ----------

  Future<void> _batchDelete() async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: '删除书籍',
      content: '确定删除选中的 ${_selected.length} 本书吗？将同时删除已缓存章节。',
      confirmText: '删除',
      danger: true,
    );
    if (confirmed) {
      final picked = List.of(_selected);
      for (final book in picked) {
        await _db.deleteBook(book.name, book.author);
      }
      if (!mounted) return;
      await _reloadAfterBatch();
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
      _books = list;
    });
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
          if (_selected.isEmpty)
            IconButton(
              icon: const Icon(Icons.search_outlined),
              tooltip: '搜索',
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
            )
          else ...[
            IconButton(
                icon: const Icon(Icons.select_all_outlined),
                tooltip: '全选',
                onPressed: _selectAll),
            IconButton(
                icon: const Icon(Icons.flip_outlined),
                tooltip: '反选',
                onPressed: _invert),
            IconButton(
                icon: const Icon(Icons.close_outlined),
                tooltip: '退出多选',
                onPressed: _exitSelectMode),
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
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(children: [
                    _batchBtn(Icons.drive_file_move_outline, '移动分组',
                        _batchMoveGroup),
                    _batchBtn(Icons.folder_off_outlined, '移除分组',
                        _batchRemoveGroup),
                    _batchBtn(Icons.cloud_download_outlined, '缓存',
                        _batchCache),
                    _batchBtn(Icons.delete_sweep_outlined, '清理缓存',
                        _batchClearCache),
                    _batchBtn(Icons.swap_horiz_outlined, '批量换源',
                        _batchChangeSource),
                    _batchBtn(Icons.update_outlined, '允许更新',
                        () => _setUpdateEnabled(true)),
                    _batchBtn(Icons.update_disabled_outlined, '禁止更新',
                        () => _setUpdateEnabled(false)),
                    _batchBtn(Icons.file_upload_outlined, '导出',
                        _batchExport),
                    _batchBtn(Icons.segment_outlined, '选中区间',
                        _selectRange),
                    _batchBtn(Icons.delete_sweep_outlined, '删除',
                        _batchDelete,
                        danger: true),
                  ]),
                ),
              ]),
            ),
    );
  }

  Widget _buildThumb(Book book) {
    final url = (book.customCoverUrl != null && book.customCoverUrl!.isNotEmpty)
        ? book.customCoverUrl
        : book.coverUrl;
    return BookCover(
      name: book.name,
      coverUrl: url,
      width: 36,
      height: 50,
      radius: 4,
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
            icon: const Icon(Icons.clear_outlined),
            tooltip: '清空',
            onPressed: () => query = ''),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: '返回',
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
