import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';
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
import 'package:legado_md3/ui/book/detail/change_source_screen.dart';
import 'package:legado_md3/ui/book/detail/change_cover_screen.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/ui/book/source/source_login_screen.dart';

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
  /// 目录获取失败原因（非空时详情页展示错误 + 重试，替代原先静默吞掉）
  String? _tocError;
  bool _introExpanded = false;
  int _readChapterIndex = 0;
  bool _inShelf = false;
  // 对齐 E LocalConfig.bookInfoDeleteAlert：删除书架提醒开关
  bool _deleteAlert = true;
  // 对齐 E onMenuOpened：当前书源，控制「登录 / 源变量 / 书籍变量」可见性
  BookSource? _detailSource;

  @override
  void initState() {
    super.initState();
    _loadChapters();
    _loadReadProgress();
    _checkInShelf();
    _loadDeleteAlert();
    _loadDetailSource();
  }

  Future<void> _loadDeleteAlert() async {
    final p = await SharedPreferences.getInstance();
    if (mounted) setState(() => _deleteAlert = p.getBool('bookInfoDeleteAlert') ?? true);
  }

  /// 加载当前书源，供「登录 / 源变量 / 书籍变量」菜单判断可见性（对齐 E onMenuOpened）
  Future<void> _loadDetailSource() async {
    final origin = widget.book.origin;
    if (origin == null || origin.isEmpty) return;
    try {
      final sources = await _db.getAllSources();
      for (final s in sources) {
        if (s.bookSourceUrl == origin) {
          if (mounted) setState(() => _detailSource = s);
          break;
        }
      }
    } catch (_) {}
  }

  /// 对齐 E BookInfoActivity.setSourceVariable / setBookVariable：变量持久化到 SharedPreferences
  Future<void> _editVariable(String prefKey, String title) async {
    final p = await SharedPreferences.getInstance();
    final ctrl = TextEditingController(text: p.getString(prefKey) ?? '');
    if (!mounted) return;
    final v = await showDialog<String>(context: context, builder: (d) => AlertDialog(
      title: Text(title),
      content: TextField(controller: ctrl, maxLines: 4, decoration: const InputDecoration(hintText: '变量内容（JSON 或文本）')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(d, ctrl.text), child: const Text('保存')),
      ],
    ));
    if (v == null) return;
    await p.setString(prefKey, v);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('变量已保存')));
  }

  /// 对齐 E BookInfoActivity.menu_log（AppLogDialog）：展示本书诊断信息
  void _showBookLog() {
    showDialog(context: context, builder: (c) => AlertDialog(
      title: const Text('日志'),
      content: SingleChildScrollView(child: Text(
        '书名：${widget.book.name}\n作者：${widget.book.author}\n'
        '来源：${widget.book.originName ?? widget.book.origin ?? '本地'}\n'
        '书籍地址：${widget.book.bookUrl ?? ''}\n目录地址：${widget.book.noteUrl ?? ''}\n'
        '章节数：${_chapters.length}\n最新章节：${widget.book.lastChapter ?? ''}',
        style: const TextStyle(fontSize: 12, height: 1.5),
      )),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭'))],
    ));
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
    if (mounted) {
      setState(() {
      _isLoading = false;
      if (_chapters.isNotEmpty) _tocError = null;
    });
    }
  }

  Future<void> _fetchTocFromNetwork() async {
    if (mounted) setState(() => _tocError = null);
    try {
      final sources = await _db.getAllSources(enabled: true);
      final source = sources.where((s) => s.bookSourceUrl == widget.book.origin).firstOrNull;
      if (source == null) {
        if (mounted) setState(() => _tocError = '未找到匹配的书源（${widget.book.origin ?? '未知'}），无法获取目录');
        return;
      }
      final engine = BookSourceEngine();

      // legado 约定：目录地址 = noteUrl，为空时回退 bookUrl。绝大多数书源
      // 搜索结果给的 bookUrl 本身就是目录页地址，并没有独立的 noteUrl /
      // ruleBookInfo。旧实现把目录获取绑死在 getBookInfo 成功上，详情解析
      // 失败（无规则 / JS 抛异常）就直接放弃，导致「能搜到却无目录无正文」。
      final bookUrl = widget.book.bookUrl ?? '';
      var noteUrl = (widget.book.noteUrl ?? '').isNotEmpty
          ? widget.book.noteUrl!
          : bookUrl;

      // 详情规则仅作为可选增强：补全封面/简介/独立 tocUrl，绝不因失败放弃目录。
      if ((source.ruleBookInfo?.isNotEmpty ?? false) && bookUrl.isNotEmpty) {
        try {
          final info = await engine.getBookInfo(source, bookUrl,
              presetName: widget.book.name, presetAuthor: widget.book.author);
          if (info != null) {
            if ((info.noteUrl ?? '').isNotEmpty) noteUrl = info.noteUrl!;
            if ((info.intro ?? '').isNotEmpty &&
                (widget.book.intro ?? '').isEmpty) {
              widget.book.intro = info.intro;
            }
            if ((info.coverUrl ?? '').isNotEmpty &&
                (widget.book.coverUrl ?? '').isEmpty) {
              widget.book.coverUrl = info.coverUrl;
            }
          }
        } catch (_) {
          // 详情失败不影响目录：忽略，继续用 bookUrl 兜底
        }
      }

      // 把最终目录地址回写，供阅读页 / 换源 / 二次进入复用
      widget.book.noteUrl = noteUrl;
      await _db.updateBook(widget.book);

      if (noteUrl.isEmpty) {
        if (mounted) {
          setState(() => _tocError = '书籍缺少目录地址（bookUrl 为空），请换源或重新搜索');
        }
        return;
      }

      var chapters = await engine.getToc(source, noteUrl,
          bookInfo: widget.book.jsContext());
      // 独立 tocUrl 取不到章节时，回退用书址本身再取一次目录
      if (chapters.isEmpty && bookUrl.isNotEmpty && bookUrl != noteUrl) {
        chapters = await engine.getToc(source, bookUrl,
            bookInfo: widget.book.jsContext());
        if (chapters.isNotEmpty) {
          widget.book.noteUrl = bookUrl;
          await _db.updateBook(widget.book);
        }
      }
      if (chapters.isNotEmpty) {
        await _db.saveChapters(widget.book.name, widget.book.author, chapters);
        _chapters = chapters;
        widget.book.lastChapter = chapters.last.title;
        widget.book.lastChapterIndex = chapters.length - 1;
        await _db.updateBook(widget.book);
      } else if (mounted) {
        setState(() => _tocError = '已访问目录地址但未解析到章节（该书源 toc 规则未匹配，或需要登录会话）');
      }
    } catch (e) {
      if (mounted) setState(() => _tocError = '获取目录失败：${e.toString().split('\n').first}');
    }
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
        const SizedBox(height: AppSpacing.s),
        TextField(controller: authorController, decoration: const InputDecoration(labelText: '作者')),
        const SizedBox(height: AppSpacing.s),
        TextField(controller: coverController, decoration: const InputDecoration(labelText: '封面URL')),
        const SizedBox(height: AppSpacing.s),
        TextField(controller: kindController, decoration: const InputDecoration(labelText: '分类')),
        const SizedBox(height: AppSpacing.s),
        TextField(controller: introController, maxLines: 4, decoration: const InputDecoration(labelText: '简介')),
        const SizedBox(height: AppSpacing.s),
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
          if (mounted && context.mounted) { setState(() {}); Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存'))); }
        }, child: const Text('保存')),
      ],
    ));
  }

  // 对齐 E book_info.xml：详情页菜单无「更新书籍 / 缓存全部」项
  // （「刷新」统一走 _refreshBookInfo；离线缓存在阅读页顶部栏与缓存页），故删除无入口方法。

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
    try {
      await runWithBusyDialog<void>(
        context,
        message: '正在重新解析目录...',
        task: (() async {
          await ImportBookService.toggleSplitLongChapter(book, _db);
          await _loadChapters();
        })(),
      );
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
      final ok = await showAppConfirmDialog(
        context,
        title: '上传书籍',
        content: '远程 WebDAV 链接已存在，是否继续（将覆盖远程文件）？',
        confirmText: '继续',
      );
      if (!ok) return;
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
    try {
      if (!mounted || !context.mounted) return;
      await runWithBusyDialog<void>(
        context,
        message: '上传中...',
        task: (() async {
          final dav = WebDavService()
            ..configure(baseUrl: url.trim(), username: user, password: pass);
          final ok = await dav.uploadBook(localPath, bookDir: bookDir);
          if (!ok) throw '上传失败（请检查网络与 WebDAV 配置）';
          // 标记远程地址，使远程书库/同步可知该书已上传（E: BookType.webDavTag）
          book.origin = WebDavService.remoteBookUrl(url.trim(), bookDir, localPath.split('/').last);
          // 让本地最后检查时间新于远程，便于后续同步判断
          book.lastCheckTime = DateTime.now().millisecondsSinceEpoch;
          await _db.updateBook(book);
        })(),
      );
      if (mounted) setState(() {});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('上传成功')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('上传失败: $e')));
    }
  }

  void _showMoreMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 对齐 E res/menu/book_info.xml 的 showAsAction="never" 项与顺序
            // 1. 上传到远程（E: menu_upload，仅本地书可见，对齐 A10 书籍上传 WebDAV）
            if (widget.book.local && (widget.book.fileName?.isNotEmpty ?? false))
              ListTile(
                leading: const Icon(Icons.cloud_upload_outlined),
                title: const Text('上传到远程'),
                subtitle: const Text('上传到 WebDAV 远程书库'),
                onTap: () { Navigator.pop(context); _uploadBook(); },
              ),
            // 2. 刷新（E: menu_refresh）
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('刷新'),
              onTap: () { Navigator.pop(context); _refreshBookInfo(); },
            ),
            // 3. 登录（E: menu_login，书源有 loginUrl 时可见）
            if (_detailSource != null && (_detailSource!.loginUrl?.isNotEmpty ?? false))
              ListTile(
                leading: const Icon(Icons.login),
                title: const Text('登录'),
                onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => SourceLoginScreen(source: _detailSource!))); },
              ),
            // 4. 置顶（E: menu_top）
            ListTile(
              leading: const Icon(Icons.push_pin_outlined),
              title: Text((widget.book.customOrder ?? 0) < 0 ? '取消置顶' : '置顶'),
              onTap: () async { Navigator.pop(context); widget.book.customOrder = (widget.book.customOrder ?? 0) < 0 ? 0 : -1; await _db.updateBook(widget.book); if (mounted) setState(() {}); },
            ),
            // 5. 设置源变量（E: menu_set_source_variable，有书源时可见）
            if (_detailSource != null)
              ListTile(
                leading: const Icon(Icons.data_object),
                title: const Text('设置源变量'),
                onTap: () { Navigator.pop(context); _editVariable('sourceVar::${widget.book.origin}', '设置源变量'); },
              ),
            // 6. 设置书籍变量（E: menu_set_book_variable，有书源时可见）
            if (_detailSource != null)
              ListTile(
                leading: const Icon(Icons.data_object),
                title: const Text('设置书籍变量'),
                onTap: () { Navigator.pop(context); _editVariable('bookVar::${widget.book.bookUrl}', '设置书籍变量'); },
              ),
            // 7. 复制书籍URL（E: menu_copy_book_url）
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('复制书籍URL'),
              onTap: () async { Navigator.pop(context); await Clipboard.setData(ClipboardData(text: widget.book.bookUrl ?? '')); if (mounted && context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制'))); },
            ),
            // 8. 复制目录URL（E: menu_copy_toc_url）
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('复制目录URL'),
              onTap: () async { Navigator.pop(context); await Clipboard.setData(ClipboardData(text: widget.book.noteUrl ?? '')); if (mounted && context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制'))); },
            ),
            // 9. 允许更新（E: menu_can_update，checkable）
            ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('允许更新'),
              trailing: Icon(widget.book.allowUpdate ? Icons.check_box : Icons.check_box_outline_blank),
              onTap: () async { Navigator.pop(context); widget.book.allowUpdate = !widget.book.allowUpdate; await _db.updateBook(widget.book); if (mounted) setState(() {}); },
            ),
            // 10. 长章节拆分（E: menu_split_long_chapter，checkable，仅本地 TXT）
            if (_isLocalTxt)
              ListTile(
                leading: Icon(widget.book.splitLongChapter ? Icons.check_box : Icons.check_box_outline_blank),
                title: const Text('长章节拆分'),
                subtitle: const Text('正文超过 100KB 的章节自动拆分，提升翻页流畅度'),
                onTap: () { Navigator.pop(context); _toggleSplitLongChapter(); },
              ),
            // 11. 删除提醒（E: menu_delete_alert，checkable）
            ListTile(
              leading: Icon(_deleteAlert ? Icons.check_box : Icons.check_box_outline_blank),
              title: const Text('删除提醒'),
              onTap: () async {
                Navigator.pop(context);
                final next = !_deleteAlert;
                final p = await SharedPreferences.getInstance();
                await p.setBool('bookInfoDeleteAlert', next);
                if (mounted) setState(() => _deleteAlert = next);
              },
            ),
            // 12. 清理缓存（E: menu_clear_cache）
            ListTile(
              leading: const Icon(Icons.cleaning_services),
              title: const Text('清理缓存'),
              onTap: () async {
                Navigator.pop(context);
                final chapters = await _db.getChapters(widget.book.name, widget.book.author);
                for (final ch in chapters) {
                  await _db.updateChapterContent(widget.book.name, widget.book.author, ch.index, '');
                }
                if (mounted && context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('缓存已清除')));
              },
            ),
            // 13. 日志（E: menu_log）
            ListTile(
              leading: const Icon(Icons.receipt_long),
              title: const Text('日志'),
              onTap: () { Navigator.pop(context); _showBookLog(); },
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
                      // 对齐 E book_info.xml showAsAction="ifRoom"：编辑（仅书架）/ 分享
                      if (_inShelf)
                        IconButton(icon: const Icon(Icons.edit), tooltip: '编辑', onPressed: _showEditBookDialog),
                      IconButton(icon: const Icon(Icons.share), tooltip: '分享',
                        onPressed: () => Share.share('《${book.name}》 - ${book.author}\n${book.intro ?? ''}')),
                      IconButton(tooltip: '更多', icon: const Icon(Icons.more_vert), onPressed: _showMoreMenu),
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
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l, vertical: AppSpacing.s),
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

                        const SizedBox(height: AppSpacing.s),

                        // 简介（默认 4 行，可展开）
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
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

                        const SizedBox(height: AppSpacing.s),

                        // 最新章节列表
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
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
                                const Padding(padding: EdgeInsets.all(AppSpacing.l), child: AppLoadingIndicator())
                              else if (_chapters.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.all(AppSpacing.l),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(_tocError ?? '暂无章节', style: TextStyle(color: cs.onSurfaceVariant)),
                                      if (_tocError != null) ...[
                                        const SizedBox(height: AppSpacing.s),
                                        FilledButton.icon(
                                          icon: const Icon(Icons.refresh, size: 16),
                                          label: const Text('重新获取目录'),
                                          onPressed: () {
                                            setState(() => _isLoading = true);
                                            _fetchTocFromNetwork().then((_) {
                                              if (mounted) setState(() => _isLoading = false);
                                            });
                                          },
                                        ),
                                      ],
                                    ],
                                  ),
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

                        const SizedBox(height: AppSpacing.xl),
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
            // 对齐 E ivCover.setOnClickListener → ChangeCoverDialog：点击封面换封面
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChangeCoverScreen(book: book))),
              child: _buildCover(book, large: true),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: Text(book.name,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 6),
            if (book.kind?.isNotEmpty == true || (book.wordCount ?? 0) > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
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
          if (trailing != null) ...[const SizedBox(width: AppSpacing.s), trailing],
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
      if (mounted && context.mounted) await Provider.of<BookProvider>(context, listen: false).loadBooks();
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
    // 对齐 E LocalConfig.bookInfoDeleteAlert：关闭删除提醒时直接移出书架，不弹确认框
    if (!_deleteAlert) {
      await _db.deleteBook(book.name, book.author);
      if (mounted && context.mounted) await Provider.of<BookProvider>(context, listen: false).loadBooks();
      if (mounted) {
        setState(() => _inShelf = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已移出书架')));
      }
      return;
    }
    final confirmed = await showAppConfirmDialog(
      context,
      title: '移除书籍',
      content: '确定要从书架移除《${book.name}》吗？',
      confirmText: '移除',
      danger: true,
    );
    if (confirmed) {
      await _db.deleteBook(book.name, book.author);
      if (mounted && context.mounted) await Provider.of<BookProvider>(context, listen: false).loadBooks();
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
              const SizedBox(height: AppSpacing.m),
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
    return DefaultCover(
      name: book.name,
      width: width,
      height: height,
      radius: 5,
      fontSize: 12,
    );
  }

  Widget _buildTag(String text) => AppTag(text);
}
