import 'package:flutter/material.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/data/model/search_book.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/help/source/source_engine.dart';

/// 换源：并发在所有启用书源检索同一本书，切换为目标源的目录地址
class ChangeSourceScreen extends StatefulWidget {
  final Book book;
  const ChangeSourceScreen({super.key, required this.book});

  @override
  State<ChangeSourceScreen> createState() => _ChangeSourceScreenState();
}

class _SourceResult {
  BookSource source;
  SearchBook? match;
  bool searching = true;
  String? error;
  _SourceResult(this.source);
}

class _ChangeSourceScreenState extends State<ChangeSourceScreen> {
  final DatabaseService _db = DatabaseService();
  final BookSourceEngine _engine = BookSourceEngine();
  final List<_SourceResult> _results = [];
  bool _loading = true;
  int _done = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _searchAll();
  }

  Future<void> _searchAll() async {
    final sources = await _db.getAllSources(enabled: true);
    _results
      ..clear()
      ..addAll(sources.map(_SourceResult.new));
    _total = _results.length;
    if (mounted) setState(() => _loading = false);

    // 并发池检索，每源最多 15s
    const concurrency = 8;
    int cursor = 0;
    Future<void> worker() async {
      while (true) {
        final i = cursor++;
        if (i >= _results.length) return;
        final r = _results[i];
        try {
          final list = await _engine.search(r.source, widget.book.name).timeout(
            const Duration(seconds: 15), onTimeout: () => []);
          // 优先同名，作者也匹配最佳
          SearchBook? best;
          for (final b in list) {
            if (b.name.replaceAll(RegExp(r'\s'), '') == widget.book.name.replaceAll(RegExp(r'\s'), '')) {
              best = b;
              if (widget.book.author.isEmpty || b.author.contains(widget.book.author) || widget.book.author.contains(b.author)) break;
            }
          }
          best ??= list.isNotEmpty ? list.first : null;
          if (mounted) setState(() { r.match = best; r.searching = false; _done++; });
        } catch (e) {
          if (mounted) setState(() { r.searching = false; r.error = '$e'; _done++; });
        }
      }
    }
    await Future.wait(List.generate(concurrency.clamp(1, _results.isEmpty ? 1 : _results.length), (_) => worker()));
  }

  Future<void> _changeSource(_SourceResult r) async {
    final m = r.match;
    if (m == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('「${r.source.bookSourceName}」未找到本书')));
      return;
    }
    final confirmed = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('确认换源'),
      content: Text('将《${widget.book.name}》更换为「${r.source.bookSourceName}」的源吗？'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('确定')),
      ],
    ));
    if (confirmed != true) return;
    widget.book
      ..origin = r.source.bookSourceUrl
      ..originName = r.source.bookSourceName
      ..noteUrl = m.noteUrl
      ..bookUrl = m.bookUrl
      ..coverUrl = (m.coverUrl?.isNotEmpty ?? false) ? m.coverUrl : widget.book.coverUrl
      ..lastChapter = (m.lastChapter?.isNotEmpty ?? false) ? m.lastChapter : widget.book.lastChapter
      ..intro = (m.intro?.isNotEmpty ?? false) ? m.intro : widget.book.intro;
    // 旧源的目录与缓存章节 URL 已失效，清除并重置进度，阅读页会按新源重新拉取目录
    await _db.deleteChapters(widget.book.name, widget.book.author);
    widget.book.durChapterIndex = 0;
    widget.book.durChapterPos = 0;
    widget.book.lastChapterIndex = 0;
    await _db.updateBook(widget.book);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('换源成功，将重新加载目录')));
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('换源 - ${widget.book.name}'),
        actions: [
          if (_done < _total)
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Center(child: Text('$_done/$_total', style: const TextStyle(fontSize: 12))))
          else
            IconButton(icon: const Icon(Icons.refresh), onPressed: () { setState(() { _done = 0; _results.clear(); _loading = true; }); _searchAll(); }),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _results.isEmpty
              ? const Center(child: Text('暂无可用书源，请先在书源管理中启用'))
              : RefreshIndicator(onRefresh: _searchAll, child: ListView.separated(
                  itemCount: _results.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (c, i) {
                    final r = _results[i];
                    final isCurrent = r.source.bookSourceUrl == widget.book.origin;
                    Widget trailing;
                    if (r.searching) {
                      trailing = const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2));
                    } else if (r.match != null) {
                      trailing = isCurrent ? const Icon(Icons.check_circle, color: Colors.green) : const Icon(Icons.swap_horiz);
                    } else {
                      trailing = const Icon(Icons.do_not_disturb_alt, color: Colors.grey);
                    }
                    return ListTile(
                      leading: CircleAvatar(child: Text(r.source.bookSourceName.isNotEmpty ? r.source.bookSourceName[0] : '?')),
                      title: Text(r.source.bookSourceName, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(r.searching ? '搜索中...' : r.match != null
                        ? '${r.match!.author}  ${r.match!.lastChapter ?? ''}'
                        : (r.error != null ? '搜索失败' : '未找到'),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12)),
                      trailing: trailing,
                      enabled: !r.searching && r.match != null,
                      onTap: isCurrent ? null : () => _changeSource(r),
                    );
                  },
                )),
    );
  }
}
