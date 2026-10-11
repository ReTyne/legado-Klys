import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_chapter.dart';
import 'package:legado_md3/di/book_provider.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/help/source/source_engine.dart';
import 'package:legado_md3/ui/book/read/reading_screen.dart';
import 'package:legado_md3/ui/book/audio/audio_player_screen.dart';
import 'package:legado_md3/ui/book/chapter/chapter_list_screen.dart';
import 'package:legado_md3/ui/book/knowledge/character_list_screen.dart';
import 'package:legado_md3/ui/book/detail/change_source_screen.dart';
import 'package:legado_md3/ui/book/detail/change_cover_screen.dart';
import 'package:legado_md3/ui/bookmark/book_marking_screen.dart';
import 'package:legado_md3/ui/stats/read_record_screen.dart';
import 'package:legado_md3/ui/backup/backup_screen.dart';

class BookDetailScreen extends StatefulWidget {
  final Book book;
  const BookDetailScreen({super.key, required this.book});

  @override
  State<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends State<BookDetailScreen> {
  final DatabaseService _db = DatabaseService();
  List<BookChapter> _chapters = [];
  bool _isLoading = true;
  bool _introExpanded = false;
  int _readChapterIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadChapters();
    _loadReadProgress();
  }

  Future<void> _loadChapters() async {
    _chapters = await _db.getChapters(widget.book.name, widget.book.author);
    if (mounted) setState(() {});
    // 本地无目录时自动联网获取（搜索结果首次进入的场景）
    if (_chapters.isEmpty && !widget.book.local) {
      await _fetchTocFromNetwork();
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _fetchTocFromNetwork() async {
    try {
      final sources = await _db.getAllSources(enabled: true);
      final source = sources.where((s) => s.bookSourceUrl == widget.book.origin).firstOrNull;
      if (source == null) return;
      final engine = BookSourceEngine();
      var noteUrl = widget.book.noteUrl;
      // 没有目录地址时先用书籍详情规则补全
      if ((noteUrl == null || noteUrl.isEmpty) && (widget.book.bookUrl ?? '').isNotEmpty) {
        final info = await engine.getBookInfo(source, widget.book.bookUrl!,
            presetName: widget.book.name, presetAuthor: widget.book.author);
        if (info != null) {
          noteUrl = info.noteUrl ?? noteUrl;
          widget.book.noteUrl = noteUrl;
          if ((info.intro ?? '').isNotEmpty) widget.book.intro = info.intro;
          await _db.updateBook(widget.book);
        }
      }
      if (noteUrl != null && noteUrl.isNotEmpty) {
        final chapters = await engine.getToc(source, noteUrl,
            bookInfo: widget.book.jsContext());
        if (chapters.isNotEmpty) {
          await _db.saveChapters(widget.book.name, widget.book.author, chapters);
          _chapters = chapters;
          widget.book.lastChapter = chapters.last.title;
          widget.book.lastChapterIndex = chapters.length - 1;
          await _db.updateBook(widget.book);
        }
      }
    } catch (_) {}
  }

  Future<void> _loadReadProgress() async {
    final records = await _db.getReadRecords();
    for (final r in records) {
      if (r.bookName == widget.book.name && r.author == widget.book.author) {
        _readChapterIndex = r.chapterIndex ?? 0;
        break;
      }
    }
  }

  void _showEditBookDialog() {
    final nameController = TextEditingController(text: widget.book.name);
    final authorController = TextEditingController(text: widget.book.author);
    final introController = TextEditingController(text: widget.book.intro ?? '');
    final kindController = TextEditingController(text: widget.book.kind ?? '');
    final coverController = TextEditingController(text: widget.book.customCoverUrl ?? widget.book.coverUrl ?? '');
    final commentController = TextEditingController(text: widget.book.bookComment ?? '');
    showDialog(context: context, builder: (context) => AlertDialog(
      title: const Text('编辑书籍信息'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nameController, decoration: const InputDecoration(labelText: '书名')),
        const SizedBox(height: 8),
        TextField(controller: authorController, decoration: const InputDecoration(labelText: '作者')),
        const SizedBox(height: 8),
        TextField(controller: coverController, decoration: const InputDecoration(labelText: '封面URL')),
        const SizedBox(height: 8),
        TextField(controller: kindController, decoration: const InputDecoration(labelText: '分类')),
        const SizedBox(height: 8),
        TextField(controller: introController, maxLines: 4, decoration: const InputDecoration(labelText: '简介')),
        const SizedBox(height: 8),
        TextField(controller: commentController, maxLines: 2, decoration: const InputDecoration(labelText: '备注')),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: () async {
          widget.book.name = nameController.text;
          widget.book.author = authorController.text;
          widget.book.kind = kindController.text;
          widget.book.intro = introController.text;
          widget.book.customCoverUrl = coverController.text.isEmpty ? null : coverController.text;
          widget.book.bookComment = commentController.text.isEmpty ? null : commentController.text;
          await _db.updateBook(widget.book);
          if (mounted) { setState(() {}); Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存'))); }
        }, child: const Text('保存')),
      ],
    ));
  }

  Future<void> _updateBook() async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在更新...')));
    try {
      final sources = await _db.getAllSources(enabled: true);
      final source = sources.where((s) => s.bookSourceUrl == widget.book.origin).firstOrNull;
      if (source == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未找到对应书源，无法更新')));
        return;
      }
      final engine = BookSourceEngine();
      var noteUrl = widget.book.noteUrl;
      // 目录地址缺失时先通过书籍详情规则补全
      if ((noteUrl == null || noteUrl.isEmpty) && (widget.book.bookUrl ?? '').isNotEmpty) {
        final info = await engine.getBookInfo(source, widget.book.bookUrl!,
            presetName: widget.book.name, presetAuthor: widget.book.author);
        if (info != null) {
          noteUrl = info.noteUrl ?? noteUrl;
          widget.book.noteUrl = noteUrl;
          if ((info.intro ?? '').isNotEmpty) widget.book.intro = info.intro;
        }
      }
      if (noteUrl == null || noteUrl.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无法获取目录地址，请尝试换源')));
        return;
      }
      final chapters = await engine.getToc(source, noteUrl,
          bookInfo: widget.book.jsContext());
      if (chapters.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('更新失败：未获取到章节')));
        return;
      }
      await _db.saveChapters(widget.book.name, widget.book.author, chapters);
      widget.book.lastChapter = chapters.last.title;
      widget.book.lastChapterIndex = chapters.length - 1;
      await _db.updateBook(widget.book);
      await _loadChapters();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('更新完成，共${chapters.length}章')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('更新失败: $e')));
    }
  }

  Future<void> _downloadAll() async {
    if (_chapters.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('暂无章节，请先更新目录')));
      return;
    }
    final sources = await _db.getAllSources(enabled: true);
    final source = sources.where((s) => s.bookSourceUrl == widget.book.origin).firstOrNull;
    if (source == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未找到对应书源')));
      return;
    }
    final engine = BookSourceEngine();
    int ok = 0, fail = 0;
    showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: Card(child: Padding(padding: EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 12), Text('正在缓存章节...')])))));
    for (int i = 0; i < _chapters.length; i++) {
      final ch = _chapters[i];
      if (ch.isVolume) continue;
      try {
        final content = await engine.getContent(source, ch.url,
            bookInfo: widget.book.jsContext(),
            chapter: ch.jsContext(widget.book.bookUrl));
        if (content != null && content.isNotEmpty) {
          await _db.updateChapterContent(widget.book.name, widget.book.author, ch.index, content);
          ok++;
        } else { fail++; }
      } catch (_) { fail++; }
    }
    if (mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('缓存完成: 成功$ok章${fail > 0 ? ', 失败$fail章' : ''}'))); }
  }

  void _showMoreMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('更新书籍'),
              onTap: () { Navigator.pop(context); _updateBook(); },
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('缓存全部'),
              onTap: () { Navigator.pop(context); _downloadAll(); },
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('换源'),
              onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => ChangeSourceScreen(book: widget.book))); },
            ),
            ListTile(
              leading: const Icon(Icons.image),
              title: const Text('换封面'),
              onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => ChangeCoverScreen(book: widget.book))); },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('编辑书籍信息'),
              onTap: () { Navigator.pop(context); _showEditBookDialog(); },
            ),
            ListTile(
              leading: const Icon(Icons.people_outline),
              title: const Text('角色列表'),
              onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => CharacterListScreen(book: widget.book))); },
            ),
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('书籍标记'),
              onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => BookMarkingScreen(bookName: widget.book.name, author: widget.book.author))); },
            ),
            ListTile(
              leading: const Icon(Icons.bar_chart),
              title: const Text('阅读记录'),
              onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const ReadRecordScreen())); },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('复制书籍URL'),
              onTap: () async { Navigator.pop(context); await Clipboard.setData(ClipboardData(text: widget.book.bookUrl ?? '')); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制'))); },
            ),
            ListTile(
              leading: const Icon(Icons.list_alt),
              title: const Text('复制目录URL'),
              onTap: () async { Navigator.pop(context); await Clipboard.setData(ClipboardData(text: widget.book.noteUrl ?? '')); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制'))); },
            ),
            ListTile(
              leading: const Icon(Icons.push_pin_outlined),
              title: Text((widget.book.customOrder ?? 0) < 0 ? '取消置顶' : '置顶'),
              onTap: () async { Navigator.pop(context); widget.book.customOrder = (widget.book.customOrder ?? 0) < 0 ? 0 : -1; await _db.updateBook(widget.book); if (mounted) setState(() {}); },
            ),
            ListTile(
              leading: Icon(widget.book.allowUpdate ? Icons.sync_disabled : Icons.sync),
              title: Text(widget.book.allowUpdate ? '禁止更新' : '允许更新'),
              onTap: () async { Navigator.pop(context); widget.book.allowUpdate = !widget.book.allowUpdate; await _db.updateBook(widget.book); if (mounted) setState(() {}); },
            ),
            ListTile(
              leading: const Icon(Icons.cloud_sync),
              title: const Text('WebDAV同步'),
              onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const BackupScreen())); },
            ),
            ListTile(
              leading: const Icon(Icons.cleaning_services),
              title: const Text('清除缓存'),
              onTap: () async {
                Navigator.pop(context);
                final chapters = await DatabaseService().getChapters(widget.book.name, widget.book.author);
                for (final ch in chapters) {
                  await DatabaseService().updateChapterContent(widget.book.name, widget.book.author, ch.index, '');
                }
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('缓存已清除')));
              },
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('分享'),
              onTap: () { Navigator.pop(context); Share.share('《${widget.book.name}》 - ${widget.book.author}\n${widget.book.intro ?? ''}'); },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('从书架移除', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(context);
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('移除书籍'),
                    content: Text('确定要从书架移除《${widget.book.name}》吗？'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
                      FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context, true), child: const Text('移除')),
                    ],
                  ),
                );
                if (confirmed == true) {
                  await _db.deleteBook(widget.book.name, widget.book.author);
                  await Provider.of<BookProvider>(context, listen: false).loadBooks();
                  if (mounted) Navigator.pop(context);
                }
              },
            ),
          ],
        )),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: _buildHeader(book),
            ),
            actions: [
              IconButton(icon: const Icon(Icons.more_vert), onPressed: _showMoreMenu),
            ],
          ),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 基本信息
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildCover(book),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(book.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold), maxLines: 2),
                            const SizedBox(height: 8),
                            Text(book.author, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                if (book.kind != null && book.kind!.isNotEmpty) _buildTag(book.kind!),
                                _buildTag(book.local ? '本地' : '网络'),
                                if (book.wordCount != null) _buildTag('${(book.wordCount! / 10000).toStringAsFixed(1)}万字'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // 操作按钮
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => book.type == 2
                              ? AudioPlayerScreen(book: book)
                              : ReadingScreen(book: book))),
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('开始阅读'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChapterListScreen(book: book))),
                          icon: const Icon(Icons.list_alt),
                          label: const Text('目录'),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // 阅读进度
                if (_chapters.isNotEmpty) Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Icon(Icons.bookmark, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('读到: ${_chapters[_readChapterIndex.clamp(0, _chapters.length - 1)].title}', style: const TextStyle(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                                Text('进度: ${((_readChapterIndex + 1) / _chapters.length * 100).toStringAsFixed(1)}%', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                              ],
                            ),
                          ),
                          TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => book.type == 2
                              ? AudioPlayerScreen(book: book, initialIndex: _readChapterIndex)
                              : ReadingScreen(book: book, initialChapter: _readChapterIndex))), child: const Text('继续')),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // 简介
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('简介', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () => setState(() => _introExpanded = !_introExpanded),
                        child: Text(
                          book.intro ?? '暂无简介',
                          style: TextStyle(fontSize: 14, height: 1.6, color: Colors.grey[700]),
                          maxLines: _introExpanded ? null : 4,
                          overflow: _introExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                        ),
                      ),
                      if ((book.intro?.length ?? 0) > 100) TextButton(
                        onPressed: () => setState(() => _introExpanded = !_introExpanded),
                        child: Text(_introExpanded ? '收起' : '展开'),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // 最新章节
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('最新章节', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChapterListScreen(book: book))), child: const Text('全部目录')),
                        ],
                      ),
                      if (_isLoading)
                        const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
                      else if (_chapters.isEmpty)
                        const Padding(padding: EdgeInsets.all(16), child: Text('暂无章节'))
                      else
                        ..._chapters.reversed.take(5).map((chapter) => ListTile(
                          dense: true,
                          title: Text(chapter.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: chapter.isVolume ? const Icon(Icons.folder, size: 16) : null,
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReadingScreen(book: book, initialChapter: _chapters.indexOf(chapter)))),
                        )),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(Book book) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Theme.of(context).colorScheme.primaryContainer, Theme.of(context).scaffoldBackgroundColor],
        ),
      ),
      child: Center(
        child: _buildCover(book, large: true),
      ),
    );
  }

  Widget _buildCover(Book book, {bool large = false}) {
    final width = large ? 120.0 : 80.0;
    final height = large ? 160.0 : 110.0;
    final cover = (book.customCoverUrl != null && book.customCoverUrl!.isNotEmpty) ? book.customCoverUrl : book.coverUrl;
    if (cover != null && cover.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(cover, width: width, height: height, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _buildDefaultCover(book, width, height)),
      );
    }
    return _buildDefaultCover(book, width, height);
  }

  Widget _buildDefaultCover(Book book, double width, double height) {
    final colors = [Colors.blueGrey, Colors.brown, Colors.teal, Colors.indigo, Colors.deepOrange, Colors.purple];
    final color = colors[book.name.hashCode.abs() % colors.length];
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
      child: Center(child: Padding(padding: const EdgeInsets.all(8), child: Text(book.name, maxLines: 3, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)))),
    );
  }

  Widget _buildTag(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(4)),
    child: Text(text, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSecondaryContainer)),
  );
}
