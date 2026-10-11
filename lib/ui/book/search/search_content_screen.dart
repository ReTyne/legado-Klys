import 'package:flutter/material.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_chapter.dart';
import 'package:legado_md3/help/source/source_engine.dart';

/// 书内全文搜索 - 对齐原版SearchContentScreen
class SearchContentScreen extends StatefulWidget {
  final Book book;
  const SearchContentScreen({super.key, required this.book});

  @override
  State<SearchContentScreen> createState() => _SearchContentScreenState();
}

class _Result {
  final BookChapter chapter;
  final int chapterIndex;
  final List<String> snippets;
  _Result(this.chapter, this.chapterIndex, this.snippets);
}

class _SearchContentScreenState extends State<SearchContentScreen> {
  final _db = DatabaseService();
  final _controller = TextEditingController();
  List<BookChapter> _chapters = [];
  List<_Result> _results = [];
  bool _searching = false;
  String _progress = '';
  final BookSourceEngine _engine = BookSourceEngine();
  final List<String> _history = [];

  @override
  void initState() {
    super.initState();
    _loadChapters();
  }

  Future<void> _loadChapters() async {
    _chapters = await _db.getChapters(widget.book.name, widget.book.author);
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) return;
    setState(() => _searching = true);
    if (!_history.contains(query)) { _history.insert(0, query); if (_history.length > 20) _history.removeLast(); }
    await Future.delayed(const Duration(milliseconds: 100));
    List<_Result> matchIn(String content, int i) {
      final snippets = <String>[];
      var idx = content.indexOf(query);
      while (idx >= 0 && snippets.length < 3) {
        final start = (idx - 20).clamp(0, content.length);
        final end = (idx + query.length + 20).clamp(0, content.length);
        snippets.add('...${content.substring(start, end)}...');
        idx = content.indexOf(query, idx + query.length);
      }
      return snippets.isNotEmpty ? [_Result(_chapters[i], i, snippets)] : <_Result>[];
    }

    final results = <_Result>[];
    // 1) 先搜本地已缓存章节，立即出结果
    final uncached = <int>[];
    for (var i = 0; i < _chapters.length; i++) {
      final content = _chapters[i].content ?? '';
      if (content.isEmpty) { uncached.add(i); continue; }
      results.addAll(matchIn(content, i));
    }
    setState(() { _results = List.from(results); });

    // 2) 网络书：拉取未缓存章节继续搜（并发 4，命中即回存并刷新）
    if (widget.book.origin != null && widget.book.origin != 'local' && uncached.isNotEmpty) {
      final all = await _db.getAllSources();
      dynamic source;
      for (final s in all) { if (s.bookSourceUrl == widget.book.origin) { source = s; break; } }
      if (source != null) {
        var done = 0;
        const concurrency = 4;
        int cursor = 0;
        Future<void> worker() async {
          while (cursor < uncached.length && mounted) {
            final i = uncached[cursor++];
            final ch = _chapters[i];
            try {
              final text = await _engine.getContent(source, ch.url,
                  bookInfo: widget.book.jsContext(),
                  chapter: ch.jsContext(widget.book.bookUrl));
              if (text != null && text.isNotEmpty) {
                ch.content = text;
                await _db.updateChapterContent(widget.book.name, widget.book.author, i, text);
                final hit = matchIn(text, i);
                if (hit.isNotEmpty && mounted) setState(() => _results.addAll(hit));
              }
            } catch (_) {}
            done++;
            if (mounted) setState(() => _progress = '正在搜索未缓存章节 $done/${uncached.length}');
          }
        }
        await Future.wait(List.generate(concurrency, (_) => worker()));
      }
    }
    if (mounted) setState(() { _searching = false; _progress = ''; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(hintText: '在本书中搜索', border: InputBorder.none),
          onSubmitted: _search,
        ),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: () => _search(_controller.text)),
        ],
      ),
      body: _searching && _results.isEmpty
        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const CircularProgressIndicator(), const SizedBox(height: 12), Text(_progress.isEmpty ? '搜索中...' : _progress)]))
        : _results.isNotEmpty
          ? Column(children: [
              if (_searching) LinearProgressIndicator(minHeight: 2, backgroundColor: Colors.grey.shade200),
              if (_progress.isNotEmpty) Padding(padding: const EdgeInsets.all(4), child: Text(_progress, style: const TextStyle(fontSize: 11, color: Colors.grey))),
              Expanded(child: _buildResultList()),
            ])
          : _buildEmpty(),
    );
  }

  Widget _buildResultList() {
    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (context, i) {
        final r = _results[i];
        return ExpansionTile(
          leading: const Icon(Icons.bookmark_outline),
          title: Text(r.chapter.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${r.snippets.length} 处匹配', style: const TextStyle(fontSize: 11)),
          children: r.snippets.map((s) => ListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(left: 56, right: 16),
            title: Text(s, style: const TextStyle(fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
            onTap: () => Navigator.pop(context, r.chapterIndex),
          )).toList(),
        );
      },
    );
  }

  Widget _buildEmpty() {
    if (_controller.text.isEmpty && _history.isNotEmpty) {
      return ListView(children: [
        const Padding(padding: EdgeInsets.all(16), child: Text('搜索历史', style: TextStyle(fontWeight: FontWeight.bold))),
        ..._history.map((h) => ListTile(
          leading: const Icon(Icons.history, size: 20),
          title: Text(h),
          onTap: () { _controller.text = h; _search(h); },
        )),
      ]);
    }
    return const Center(child: Text('输入关键词搜索本书内容（未缓存章节将联网搜索）', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)));
  }
}
