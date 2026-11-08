import 'package:flutter/material.dart';

import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/download_task.dart';
import 'package:legado_md3/help/storage/download_service.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';

/// 下载管理（对齐官方原版 CacheActivity + DownloadService）。
///
/// 此前本页只是「查看已缓存章节 + 清理」，名不副实。现在改用
/// [DownloadService]（ChangeNotifier）展示真实活跃队列：进度条、暂停/继续、
/// 重试、取消、清除已完成，并提供「下载全书 / 从当前章开始」入口。
/// 原「已缓存章节 + 清理」能力保留在页面下半部，不删功能。
class DownloadManageScreen extends StatefulWidget {
  const DownloadManageScreen({super.key});

  @override
  State<DownloadManageScreen> createState() => _DownloadManageScreenState();
}

class _DownloadManageScreenState extends State<DownloadManageScreen> {
  final DatabaseService _db = DatabaseService();
  final DownloadService _downloads = DownloadService.instance;

  List<Book> _books = [];
  final Map<String, int> _cachedCount = {};
  final Map<String, int> _totalCount = {};
  bool _loadingCache = true;

  @override
  void initState() {
    super.initState();
    _downloads.load();
    _loadCache();
  }

  Future<void> _loadCache() async {
    setState(() => _loadingCache = true);
    final books = await _db.getAllBooks();
    final counts = <String, int>{};
    final totals = <String, int>{};
    for (final b in books) {
      final chapters = await _db.getChapters(b.name, b.author);
      final cached =
          chapters.where((ch) => ch.content != null && ch.content!.isNotEmpty).length;
      totals['${b.name}-${b.author}'] = chapters.length;
      if (cached > 0) counts['${b.name}-${b.author}'] = cached;
    }
    if (!mounted) return;
    setState(() {
      _books = books;
      _cachedCount
        ..clear()
        ..addAll(counts);
      _totalCount
        ..clear()
        ..addAll(totals);
      _loadingCache = false;
    });
  }

  void _tip(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /* ---------------- 下载队列 ---------------- */

  /// 「下载全书 / 从当前章开始」：选书后调用 enqueue(bookName, author, {startIndex, endIndex})。
  Future<void> _showEnqueueDialog() async {
    final books = await _db.getAllBooks();
    if (!mounted) return;
    if (books.isEmpty) {
      _tip('书架暂无书籍，无法创建下载任务');
      return;
    }
    Book selected = books.first;
    final mode = await showDialog<int>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('新建下载任务'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<Book>(
                isExpanded: true,
                value: selected,
                items: books
                    .map((b) => DropdownMenuItem<Book>(
                          value: b,
                          child: Text(b.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) => setD(() => selected = v ?? selected),
              ),
              const SizedBox(height: 8),
              const Text('选择下载范围（从当前章开始按书籍阅读进度计算）：',
                  style: TextStyle(fontSize: 12)),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c), child: const Text('取消')),
            TextButton(
                onPressed: () => Navigator.pop(c, 0), child: const Text('下载全书')),
            FilledButton(
                onPressed: () => Navigator.pop(c, 1),
                child: const Text('从当前章开始')),
          ],
        ),
      ),
    );
    if (mode == null) return;
    final startIndex = mode == 1 ? selected.durChapterIndex : 0;
    await _downloads.enqueue(selected.name, selected.author,
        startIndex: startIndex, endIndex: -1);
    _tip('已加入下载队列：《${selected.name}》');
  }

  Future<void> _clearBookCache(Book book) async {
    final ok = await showAppConfirmDialog(
      context,
      title: '清除缓存',
      content: '确定清除《${book.name}》的全部已缓存章节吗？',
      confirmText: '清除',
      danger: true,
    );
    if (!ok) return;
    final chapters = await _db.getChapters(book.name, book.author);
    for (var i = 0; i < chapters.length; i++) {
      await _db.updateChapterContent(book.name, book.author, i, '');
    }
    await _loadCache();
    _tip('已清理《${book.name}》缓存');
  }

  Future<void> _clearAllCache() async {
    final ok = await showAppConfirmDialog(
      context,
      title: '清空所有缓存',
      content: '确定清空全部已下载章节内容？此操作不可恢复。',
      confirmText: '清空',
      danger: true,
    );
    if (!ok || !mounted) return;
    await runWithBusyDialog<void>(
      context,
      message: '正在清理缓存…',
      task: _clearAllCacheTask(),
    );
    await _loadCache();
    _tip('已清空所有缓存');
  }

  Future<void> _clearAllCacheTask() async {
    for (final b in _books) {
      final chapters = await _db.getChapters(b.name, b.author);
      for (var i = 0; i < chapters.length; i++) {
        await _db.updateChapterContent(b.name, b.author, i, '');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('下载管理'),
        actions: [
          IconButton(
            tooltip: '清除已完成',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () async {
              await _downloads.clearFinished();
              _tip('已清除已完成任务');
            },
          ),
          IconButton(
            tooltip: '清空所有章节缓存',
            icon: const Icon(Icons.cleaning_services_outlined),
            onPressed: _clearAllCache,
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _downloads,
        builder: (context, _) {
          final tasks = _downloads.tasks;
          return ListView(
            children: [
              const AppSectionHeader('下载任务'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: FilledButton.icon(
                  onPressed: _showEnqueueDialog,
                  icon: const Icon(Icons.download),
                  label: const Text('下载全书 / 从当前章开始'),
                ),
              ),
              if (tasks.isEmpty)
                const SizedBox(
                  height: 180,
                  child: AppEmptyState(
                    icon: Icons.download_outlined,
                    title: '暂无下载任务',
                    message: '点击上方按钮为书架书籍创建缓存任务',
                  ),
                )
              else
                for (final task in tasks) _buildTaskTile(task, cs),
              const AppSectionHeader('已缓存章节'),
              _buildCachedSection(cs),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: '新建下载任务',
        onPressed: _showEnqueueDialog,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildTaskTile(DownloadTask t, ColorScheme cs) {
    final id = t.id;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(t.bookName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              Text(DownloadTask.statusName(t.status),
                  style: TextStyle(fontSize: 12, color: cs.primary)),
            ]),
            const SizedBox(height: 2),
            Text('${t.author} · 章节 ${t.startIndex + 1}-${t.endIndex + 1} · '
                '已完成 ${t.done}/${t.total}',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: t.progress, minHeight: 4),
            if (t.error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(t.error,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: cs.error)),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (t.status == 0 || t.status == 1)
                  TextButton.icon(
                    onPressed: id == null ? null : () => _downloads.pause(id),
                    icon: const Icon(Icons.pause, size: 18),
                    label: const Text('暂停'),
                  ),
                if (t.status == 4)
                  TextButton.icon(
                    onPressed: id == null ? null : () => _downloads.resume(id),
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('继续'),
                  ),
                if (t.status == 3)
                  TextButton.icon(
                    onPressed: id == null ? null : () => _downloads.retry(id),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('重试'),
                  ),
                TextButton.icon(
                  onPressed: id == null ? null : () => _downloads.cancel(id),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('取消'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCachedSection(ColorScheme cs) {
    if (_loadingCache) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: AppLoadingIndicator(),
      );
    }
    final entries = _books
        .where((b) => (_cachedCount['${b.name}-${b.author}'] ?? 0) > 0)
        .toList();
    if (entries.isEmpty) {
      return const SizedBox(
        height: 150,
        child: AppEmptyState(
          icon: Icons.download_done_outlined,
          title: '暂无已缓存章节',
          message: '创建下载任务或阅读后，这里会显示各书的缓存数量',
        ),
      );
    }
    return Column(
      children: entries.map((book) {
        final count = _cachedCount['${book.name}-${book.author}'] ?? 0;
        final total = _totalCount['${book.name}-${book.author}'] ?? 0;
        return ListTile(
          leading: const Icon(Icons.menu_book_outlined),
          title:
              Text(book.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('已缓存 $count 章${total > 0 ? ' / 共 $total 章' : ''}'),
          trailing: IconButton(
            tooltip: '清除该书缓存',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _clearBookCache(book),
          ),
        );
      }).toList(),
    );
  }
}
