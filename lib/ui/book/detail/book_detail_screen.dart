import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/constant/app_theme.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_chapter.dart';
import 'package:legado_md3/di/book_provider.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/help/net/network_monitor.dart';
import 'package:legado_md3/help/source/source_engine.dart';
import 'package:legado_md3/help/storage/import_book_service.dart';
import 'package:legado_md3/help/storage/webdav_service.dart';
import 'package:legado_md3/ui/book/reader_router.dart';
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
  bool _inShelf = false;

  @override
  void initState() {
    super.initState();
    _loadChapters();
    _loadReadProgress();
    _checkInShelf();
  }

  Future<void> _checkInShelf() async {
    final books = await _db.getAllBooks();
    final found = books.any((b) => b.name == widget.book.name && b.author == widget.book.author);
    if (mounted && found != _inShelf) setState(() => _inShelf = found);
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

  /// 是否本地 TXT（长章节拆分仅对此生效，对齐 E isLocalTxt 判断）
  bool get _isLocalTxt =>
      widget.book.local &&
      (widget.book.fileName?.toLowerCase().endsWith('.txt') ?? false);

  /// 切换长章节拆分（E: BookInfoActivity menu_split_long_chapter）：
  /// 重新解析目录入库并迁移阅读进度；关闭时提示加载可能变慢。
  Future<void> _toggleSplitLongChapter() async {
    final book = widget.book;
    if (!_isLocalTxt) return;
    final next = !book.splitLongChapter;
    // 忙碌提示（E: upLoading(true)）
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: Card(child: Padding(padding: EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 12), Text('正在重新解析目录...')])))),
    );
    try {
      await ImportBookService.toggleSplitLongChapter(book, _db);
      await _loadChapters();
      // 进度随章节重排变化，同步详情页展示
      _readChapterIndex = book.durChapterIndex;
      if (mounted) {
        setState(() {});
        // E: need_more_time_load_content
        if (!next) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正文过长时加载可能需要更多时间')));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已重新解析目录')));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('重新解析失败: $e')));
    } finally {
      if (mounted) Navigator.pop(context); // 关闭忙碌对话框
    }
  }

  /// 上传本地书籍到 WebDAV 远程书库（E: BookInfoActivity.menu_upload /
  /// RemoteBookWebDav.upload）：PUT 到 `<webdav_url>/<书库目录>/<文件名>`，
  /// 成功后把 origin 标记为 `webDav::<远程地址>` 并刷新最后检查时间。
  Future<void> _uploadBook() async {
    final book = widget.book;
    final localPath = book.fileName;
    if (localPath == null || localPath.isEmpty) return;
    // 已上传过的书籍：E 会先弹确认（远程链接已存在，是否继续）
    if ((book.origin ?? '').startsWith('webDav::')) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('上传书籍'),
          content: const Text('远程 WebDAV 链接已存在，是否继续（将覆盖远程文件）？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('继续')),
          ],
        ),
      );
      if (ok != true) return;
    }
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('webdav_url');
    final user = prefs.getString('webdav_user');
    final pass = prefs.getString('webdav_pass');
    final bookDir = prefs.getString('webdav_book_dir') ?? '书籍';
    if (url == null || url.trim().isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先在「远程书库」页面配置 WebDAV 服务器')));
      return;
    }
    // 离线快速失败（E: NetworkUtils.isAvailable）
    if (!await NetworkMonitor.instance.isOnline) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('网络不可用，请检查网络后重试')));
      return;
    }
    // 忙碌提示（E: waitDialog）
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: Card(child: Padding(padding: EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 12), Text('上传中...')])))),
    );
    try {
      final dav = WebDavService()
        ..configure(baseUrl: url.trim(), username: user, password: pass);
      final ok = await dav.uploadBook(localPath, bookDir: bookDir);
      if (!ok) throw '上传失败（请检查网络与 WebDAV 配置）';
      // 标记远程地址，使远程书库/同步可知该书已上传（E: BookType.webDavTag）
      book.origin = WebDavService.remoteBookUrl(url.trim(), bookDir, localPath.split('/').last);
      // 让本地最后检查时间新于远程，便于后续同步判断
      book.lastCheckTime = DateTime.now().millisecondsSinceEpoch;
      await _db.updateBook(book);
      if (mounted) setState(() {});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('上传成功')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('上传失败: $e')));
    } finally {
      if (mounted) Navigator.pop(context); // 关闭忙碌对话框
    }
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
            // 长章节拆分开关（E: menu_split_long_chapter，仅本地 TXT 可见）
            if (_isLocalTxt)
              ListTile(
                leading: Icon(widget.book.splitLongChapter
                    ? Icons.check_box
                    : Icons.check_box_outline_blank),
                title: const Text('长章节拆分'),
                subtitle: const Text('正文超过 100KB 的章节自动拆分，提升翻页流畅度'),
                onTap: () { Navigator.pop(context); _toggleSplitLongChapter(); },
              ),
            // 上传书籍到远程书库（E: menu_upload，仅本地书籍可见）
            if (widget.book.local && (widget.book.fileName?.isNotEmpty ?? false))
              ListTile(
                leading: const Icon(Icons.cloud_upload_outlined),
                title: const Text('上传书籍'),
                subtitle: const Text('上传到 WebDAV 远程书库'),
                onTap: () { Navigator.pop(context); _uploadBook(); },
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
              leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
              title: Text('从书架移除', style: TextStyle(color: Theme.of(context).colorScheme.error)),
              onTap: () async {
                Navigator.pop(context);
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('移除书籍'),
                    content: Text('确定要从书架移除《${widget.book.name}》吗？'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
                      // 危险操作用 colorScheme.error 底 + onError 前景，替代硬编码 Colors.red
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.error,
                          foregroundColor: Theme.of(context).colorScheme.onError,
                        ),
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('移除'),
                      ),
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
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshBookInfo,
              child: CustomScrollView(
                slivers: [
                  SliverAppBar(
                    expandedHeight: 300,
                    pinned: true,
                    actions: [
                      IconButton(icon: const Icon(Icons.more_vert), onPressed: _showMoreMenu),
                    ],
                    flexibleSpace: FlexibleSpaceBar(
                      background: _buildHeader(book),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 信息行：作者 / 来源(换源) / 读到或最新章节 / 分组 / 目录
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Column(
                            children: [
                              _infoRow(
                                icon: Icons.person_outline,
                                child: Expanded(
                                  child: Text(book.author, maxLines: 1, overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                                ),
                              ),
                              _infoRow(
                                icon: Icons.public,
                                child: Expanded(
                                  child: Text(book.originName ?? book.origin ?? '未知来源', maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                                ),
                                trailing: _accentButton('换源', () => Navigator.push(context,
                                    MaterialPageRoute(builder: (_) => ChangeSourceScreen(book: book)))),
                              ),
                              _infoRow(
                                icon: Icons.menu_book,
                                child: Expanded(
                                  child: Text(_progressText(), maxLines: 1, overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                                ),
                              ),
                              _infoRow(
                                icon: Icons.folder_outlined,
                                child: Expanded(
                                  child: Text(book.group?.isNotEmpty == true ? book.group! : '未分组',
                                      maxLines: 1, overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                                ),
                                trailing: _accentButton('更改分组', _showChangeGroupDialog),
                              ),
                              _infoRow(
                                icon: Icons.folder_open,
                                child: Expanded(
                                  child: Text(_chapters.isEmpty ? '暂无目录' : '共 ${_chapters.length} 章',
                                      maxLines: 1, overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                                ),
                                trailing: _accentButton('查看目录', () => Navigator.push(context,
                                    MaterialPageRoute(builder: (_) => ChapterListScreen(book: book)))),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 8),

                        // 简介（默认 4 行，可展开）
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              GestureDetector(
                                onTap: () => setState(() => _introExpanded = !_introExpanded),
                                child: Text(
                                  book.intro?.isNotEmpty == true ? book.intro! : '暂无简介',
                                  style: TextStyle(fontSize: 14, height: 1.6, color: cs.onSurfaceVariant),
                                  maxLines: _introExpanded ? null : 4,
                                  overflow: _introExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                                ),
                              ),
                              if ((book.intro?.length ?? 0) > 100)
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: () => setState(() => _introExpanded = !_introExpanded),
                                    child: Text(_introExpanded ? '收起' : '展开'),
                                  ),
                                ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 8),

                        // 最新章节列表
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('最新章节', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: cs.onSurface)),
                                  TextButton(
                                    onPressed: () => Navigator.push(context,
                                        MaterialPageRoute(builder: (_) => ChapterListScreen(book: book))),
                                    child: const Text('全部目录'),
                                  ),
                                ],
                              ),
                              if (_isLoading)
                                const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
                              else if (_chapters.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text('暂无章节', style: TextStyle(color: cs.onSurfaceVariant)),
                                )
                              else
                                ..._chapters.reversed.take(5).map((chapter) => ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(chapter.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  trailing: chapter.isVolume ? const Icon(Icons.folder, size: 16) : null,
                                  onTap: () => Navigator.push(context,
                                      MaterialPageRoute(builder: (_) => readerForBook(book, initialChapter: chapter.index))),
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
            ),
          ),
          // 底部操作栏：加入/移出书架 + 阅读
          Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainer,
              border: Border(top: BorderSide(color: cs.outlineVariant)),
            ),
            child: SafeArea(
              child: SizedBox(
                height: 50,
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        style: TextButton.styleFrom(shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero)),
                        onPressed: _toggleShelf,
                        child: Text(
                          _inShelf ? '移出书架' : '加入书架',
                          style: const TextStyle(fontSize: 15),
                        ),
                      ),
                    ),
                    Container(width: 1, color: cs.outlineVariant),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                          backgroundColor: cs.primary,
                          foregroundColor: cs.onPrimary,
                        ),
                        onPressed: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => readerForBook(book, initialChapter: _readChapterIndex))),
                        child: const Text('阅读', style: TextStyle(fontSize: 15)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 头部：封面 + 书名 + 分类标签（对齐 activity_book_info 的 ArcView 区域）
  Widget _buildHeader(Book book) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [cs.primaryContainer, cs.surface],
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 36),
            _buildCover(book, large: true),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(book.name,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 6),
            if (book.kind?.isNotEmpty == true || (book.wordCount ?? 0) > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (book.kind?.isNotEmpty == true) _buildTag(book.kind!),
                    if ((book.wordCount ?? 0) > 0) _buildTag('${(book.wordCount! / 10000).toStringAsFixed(1)}万字'),
                    _buildTag(book.local ? '本地' : '网络'),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 一行「图标 + 内容 + 右侧强调按钮」（对齐 ll_info 内的各 LinearLayout 行）
  Widget _infoRow({required IconData icon, required Widget child, Widget? trailing}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          child,
          if (trailing != null) ...[const SizedBox(width: 8), trailing],
        ],
      ),
    );
  }

  /// 右侧小号强调按钮（对齐 AccentBgTextView）
  Widget _accentButton(String text, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(2)),
        child: Text(text, style: TextStyle(fontSize: 13, color: cs.onPrimaryContainer)),
      ),
    );
  }

  /// 读到进度 / 最新章节文案（对齐 tv_lasted）
  String _progressText() {
    final book = widget.book;
    if (_chapters.isNotEmpty && _readChapterIndex < _chapters.length) {
      final total = _chapters.length;
      final percent = ((_readChapterIndex + 1) / total * 100).toStringAsFixed(1);
      return '读到: ${_chapters[_readChapterIndex].title} ($percent%)';
    }
    if (book.local) return book.lastChapter ?? '本地书籍';
    return '最新: ${book.lastChapter ?? '未知'}';
  }

  Future<void> _refreshBookInfo() async {
    if (widget.book.local) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('本地书籍无需刷新')));
      return;
    }
    try {
      final sources = await _db.getAllSources(enabled: true);
      final source = sources.where((s) => s.bookSourceUrl == widget.book.origin).firstOrNull;
      if (source == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未找到对应书源')));
        return;
      }
      final engine = BookSourceEngine();
      final info = await engine.getBookInfo(source, widget.book.bookUrl ?? '',
          presetName: widget.book.name, presetAuthor: widget.book.author);
      if (info != null && mounted) {
        setState(() {
          widget.book.intro = (info.intro?.isNotEmpty ?? false) ? info.intro : widget.book.intro;
          widget.book.kind = (info.kind?.isNotEmpty ?? false) ? info.kind : widget.book.kind;
          widget.book.lastChapter = info.lastChapter ?? widget.book.lastChapter;
          widget.book.wordCount = info.wordCount ?? widget.book.wordCount;
          if (info.noteUrl?.isNotEmpty ?? false) widget.book.noteUrl = info.noteUrl;
          if (info.coverUrl?.isNotEmpty ?? false) widget.book.coverUrl = info.coverUrl;
        });
        await _db.updateBook(widget.book);
        await _loadChapters();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('刷新失败: $e')));
    }
  }

  void _toggleShelf() {
    if (_inShelf) {
      _confirmRemoveFromShelf();
    } else {
      _addToShelf();
    }
  }

  Future<void> _addToShelf() async {
    final book = widget.book;
    if (!_inShelf) {
      await _db.insertBook(book);
      _inShelf = true;
      await Provider.of<BookProvider>(context, listen: false).loadBooks();
      final prefs = await SharedPreferences.getInstance();
      final showTip = prefs.getBool('oc_showAddShelfTip') ?? true;
      if (mounted && showTip) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已添加《${book.name}》到书架')));
      }
      if (mounted) setState(() {});
    }
  }

  Future<void> _confirmRemoveFromShelf() async {
    final book = widget.book;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除书籍'),
        content: Text('确定要从书架移除《${book.name}》吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _db.deleteBook(book.name, book.author);
      await Provider.of<BookProvider>(context, listen: false).loadBooks();
      if (mounted) {
        setState(() => _inShelf = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已移出书架')));
      }
    }
  }

  /// 更改分组对话框（对齐 tv_change_group）
  void _showChangeGroupDialog() async {
    final groups = <String>{};
    final books = await _db.getAllBooks();
    for (final b in books) {
      if (b.group?.isNotEmpty == true) groups.add(b.group!);
    }
    var selected = widget.book.group ?? '';
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, setS) => AlertDialog(
        title: const Text('更改分组'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 8,
                children: [
                  for (final g in groups)
                    ChoiceChip(
                      label: Text(g),
                      selected: selected == g,
                      onSelected: (_) => setS(() => selected = g),
                    ),
                  ChoiceChip(
                    label: const Text('未分组'),
                    selected: selected.isEmpty,
                    onSelected: (_) => setS(() => selected = ''),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(labelText: '新建分组', isDense: true),
                onSubmitted: (v) => setS(() => selected = v.trim()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              widget.book.group = selected.isEmpty ? null : selected;
              await _db.updateBook(widget.book);
              if (c.mounted) Navigator.pop(c);
              if (mounted) setState(() {});
            },
            child: const Text('确定'),
          ),
        ],
      )),
    );
  }

  Widget _buildCover(Book book, {bool large = false}) {
    final width = large ? 110.0 : 80.0;
    final height = large ? 160.0 : 110.0;
    final cover = (book.customCoverUrl != null && book.customCoverUrl!.isNotEmpty) ? book.customCoverUrl : book.coverUrl;
    if (cover != null && cover.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: Image.network(cover, width: width, height: height, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _buildDefaultCover(book, width, height)),
      );
    }
    return _buildDefaultCover(book, width, height);
  }

  Widget _buildDefaultCover(Book book, double width, double height) {
    final color = defaultCoverPalette[book.name.hashCode.abs() % defaultCoverPalette.length];
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(5)),
      child: Center(child: Padding(padding: const EdgeInsets.all(8), child: Text(book.name, maxLines: 3, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)))),
    );
  }

  Widget _buildTag(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(4)),
    child: Text(text, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSecondaryContainer)),
  );
}
