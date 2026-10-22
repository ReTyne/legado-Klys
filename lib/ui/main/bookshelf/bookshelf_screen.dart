import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/bookmark.dart';
import 'package:legado_md3/di/book_provider.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/help/source/source_engine.dart';
import 'package:legado_md3/help/storage/export_book_service.dart';
import 'package:legado_md3/ui/book/detail/book_detail_screen.dart';
import 'package:legado_md3/ui/book/reader_router.dart';
import 'package:legado_md3/ui/book/local_import_screen.dart';
import 'package:legado_md3/ui/book/search/search_screen.dart';
import 'package:legado_md3/ui/book/detail/change_source_screen.dart';
import 'package:legado_md3/ui/book/detail/change_cover_screen.dart';
import 'package:legado_md3/ui/bookmark/book_marking_screen.dart';
import 'package:legado_md3/ui/main/bookshelf/group_manage_screen.dart';
import 'package:legado_md3/ui/main/bookshelf/bookshelf_config_screen.dart';
import 'package:legado_md3/ui/main/home/home_screen.dart';
import 'package:legado_md3/ui/book/source/source_manage_screen.dart';
import 'package:legado_md3/ui/stats/read_record_screen.dart';
import 'package:legado_md3/ui/config/settings_screen.dart';

/// 书架视图配置（来自 SharedPreferences，由书架配置页写入）
class _ViewCfg {
  int columnCount;
  double coverWidth;
  bool compactTitle;
  bool centerTitle;
  bool showDivider;
  bool compactDetails;
  bool showLatestChapter;
  bool showSynopsis;
  int synopsisLines;
  bool showTags;
  int maxTitleLines;
  bool coverShadow;
  int groupStyle; // 0:折叠(标签) 1:平铺(分区)
  bool hideEmptyGroups;
  int sortType; // 0最近阅读 1书名 2作者 3添加时间 4手动
  bool sortAscending;
  bool showUnread;
  bool showUnreadNew;
  bool showBookCount;
  bool showLastUpdateTime;
  bool searchFilterFirst;
  bool showTabMenu;
  int updateLimit;
  /// bs_showLocalBook：书架是否显示本地导入书籍（默认值与设置页一致：false）
  bool showLocalBook;
  /// bs_showWaitUpdateCount：分组页签是否显示待更新数量
  bool showWaitUpdateCount;
  /// bs_showFastScroller：书架是否显示快速滚动条
  bool showFastScroller;

  _ViewCfg({
    this.columnCount = 3,
    this.coverWidth = 100,
    this.compactTitle = false,
    this.centerTitle = false,
    this.showDivider = false,
    this.compactDetails = false,
    this.showLatestChapter = true,
    this.showSynopsis = false,
    this.synopsisLines = 2,
    this.showTags = false,
    this.maxTitleLines = 2,
    this.coverShadow = true,
    this.groupStyle = 0,
    this.hideEmptyGroups = false,
    this.sortType = 0,
    this.sortAscending = false,
    this.showUnread = false,
    this.showUnreadNew = true,
    this.showBookCount = true,
    this.showLastUpdateTime = false,
    this.searchFilterFirst = false,
    this.showTabMenu = true,
    this.updateLimit = 0,
    this.showLocalBook = false,
    this.showWaitUpdateCount = false,
    this.showFastScroller = true,
  });

  static Future<_ViewCfg> load() async {
    final p = await SharedPreferences.getInstance();
    return _ViewCfg(
      columnCount: p.getInt('bs_columnCount') ?? 3,
      coverWidth: p.getDouble('bs_coverWidth') ?? 100,
      compactTitle: p.getBool('bs_compactTitle') ?? false,
      centerTitle: p.getBool('bs_centerTitle') ?? false,
      showDivider: p.getBool('bs_showDivider') ?? false,
      compactDetails: p.getBool('bs_compactDetails') ?? false,
      showLatestChapter: p.getBool('bs_showLatestChapter') ?? true,
      showSynopsis: p.getBool('bs_showSynopsis') ?? false,
      synopsisLines: p.getInt('bs_synopsisLines') ?? 2,
      showTags: p.getBool('bs_showTags') ?? false,
      maxTitleLines: p.getInt('bs_maxTitleLines') ?? 2,
      coverShadow: p.getBool('bs_coverShadow') ?? true,
      groupStyle: p.getInt('bs_groupStyle') ?? 0,
      hideEmptyGroups: p.getBool('bs_hideEmptyGroups') ?? false,
      sortType: p.getInt('bs_sortType') ?? 0,
      sortAscending: p.getBool('bs_sortAscending') ?? false,
      showUnread: p.getBool('bs_showUnread') ?? false,
      showUnreadNew: p.getBool('bs_showUnreadNew') ?? true,
      showBookCount: p.getBool('bs_showBookCount') ?? true,
      showLastUpdateTime: p.getBool('bs_showLastUpdateTime') ?? false,
      searchFilterFirst: p.getBool('bs_searchFilterFirst') ?? false,
      showTabMenu: p.getBool('bs_showTabMenu') ?? true,
      updateLimit: p.getInt('bs_updateLimit') ?? 0,
      showLocalBook: p.getBool('bs_showLocalBook') ?? false,
      showWaitUpdateCount: p.getBool('bs_showWaitUpdateCount') ?? false,
      showFastScroller: p.getBool('bs_showFastScroller') ?? true,
    );
  }

  /// 配置排序索引 -> 书架内部排序索引
  /// 配置: 0最近阅读 1书名 2作者 3添加时间 4手动
  /// 内部: 0智能/手动 1书名 2作者 3最近阅读 4添加时间 5字数
  static const sortMap = [3, 1, 2, 4, 0];
}

/// 封面配置（来自 SharedPreferences，由封面配置页 CoverConfigScreen 写入）
class _CoverCfg {
  /// cover_onlyWifi：仅 WiFi 下加载封面。
  /// Flutter 端无轻量 WiFi 判断方式（不新增依赖），此处降级为仅记录、不阻断加载。
  final bool onlyWifi;
  /// cover_useDefault：无封面/封面加载失败时使用默认占位
  final bool useDefault;
  /// cover_showName：封面区域叠加显示书名
  final bool showName;
  /// cover_showAuthor：封面区域叠加显示作者
  final bool showAuthor;
  /// cover_defaultColor：默认占位背景色
  final int defaultColor;
  /// cover_dayTextColor / cover_nightTextColor：叠加文字颜色（按日夜间取用）
  final int dayTextColor;
  final int nightTextColor;
  /// 默认封面图片路径（可选键 cover_defaultImage，本版本配置页未提供，读取仅作容错扩展）
  final String? defaultImage;

  const _CoverCfg({
    this.onlyWifi = false,
    this.useDefault = false,
    this.showName = true,
    this.showAuthor = true,
    this.defaultColor = 0xFF607D8B,
    this.dayTextColor = 0xFFFFFFFF,
    this.nightTextColor = 0xFFB0BEC5,
    this.defaultImage,
  });

  static Future<_CoverCfg> load() async {
    final p = await SharedPreferences.getInstance();
    return _CoverCfg(
      onlyWifi: p.getBool('cover_onlyWifi') ?? false,
      useDefault: p.getBool('cover_useDefault') ?? false,
      showName: p.getBool('cover_showName') ?? true,
      showAuthor: p.getBool('cover_showAuthor') ?? true,
      defaultColor: p.getInt('cover_defaultColor') ?? 0xFF607D8B,
      dayTextColor: p.getInt('cover_dayTextColor') ?? 0xFFFFFFFF,
      nightTextColor: p.getInt('cover_nightTextColor') ?? 0xFFB0BEC5,
      defaultImage: p.getString('cover_defaultImage'),
    );
  }
}

class BookshelfScreen extends StatefulWidget {
  const BookshelfScreen({super.key});

  @override
  State<BookshelfScreen> createState() => _BookshelfScreenState();
}

class _BookshelfScreenState extends State<BookshelfScreen> {
  final DatabaseService _db = DatabaseService();
  final BookSourceEngine _engine = BookSourceEngine();
  bool _selectMode = false;
  final Set<Book> _selectedBooks = {};
  bool _isUpdating = false;
  bool _searching = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  _ViewCfg _cfg = _ViewCfg();
  _CoverCfg _coverCfg = const _CoverCfg();

  static const List<String> _sortOptions = ['智能排序', '书名', '作者', '最近阅读', '添加时间', '字数'];
  int _sortBy = 3;
  bool _sortAsc = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = Provider.of<BookProvider>(context, listen: false);
      try {
        await provider.loadViewPrefs();
      } catch (_) {}
      try {
        await provider.loadBooks();
      } catch (_) {}
      if (mounted) await _reloadCfg();
      // 进入自动刷新（oc_autoRefresh）
      try {
        if ((await SharedPreferences.getInstance()).getBool('oc_autoRefresh') ?? false) {
          _updateAllBooks();
        }
      } catch (_) {}
    });
  }

  Future<void> _reloadCfg() async {
    final cfg = await _ViewCfg.load();
    final coverCfg = await _CoverCfg.load();
    if (!mounted) return;
    setState(() {
      _cfg = cfg;
      _coverCfg = coverCfg;
      _sortBy = _ViewCfg.sortMap[cfg.sortType.clamp(0, 4)];
      _sortAsc = cfg.sortAscending;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 未读章节数
  int _unread(Book b) {
    final latest = b.lastChapterIndex ?? b.durChapterIndex;
    return (latest - b.durChapterIndex).clamp(0, 1 << 30);
  }

  List<Book> get _filteredBooks {
    final provider = Provider.of<BookProvider>(context, listen: false);
    // 搜索优先过滤：开启后搜索时跨全部分组
    var books = (_cfg.searchFilterFirst && _searchQuery.isNotEmpty)
        ? provider.books
        : provider.filteredBooks;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      books = books
          .where((b) =>
              b.name.toLowerCase().contains(q) ||
              b.author.toLowerCase().contains(q))
          .toList();
    }
    // bs_showLocalBook：关闭时书架不显示本地导入书籍（仅过滤视图，数据保留，
    // 长按菜单/书籍详情等其它入口不受影响）
    if (!_cfg.showLocalBook) {
      books = books.where((b) => !b.local).toList();
    }
    books = List.from(books);
    switch (_sortBy) {
      case 1:
        books.sort((a, b) =>
            _sortAsc ? a.name.compareTo(b.name) : b.name.compareTo(a.name));
        break;
      case 2:
        books.sort((a, b) => _sortAsc
            ? a.author.compareTo(b.author)
            : b.author.compareTo(a.author));
        break;
      case 3:
        books.sort((a, b) => _sortAsc
            ? a.durChapterTime.compareTo(b.durChapterTime)
            : b.durChapterTime.compareTo(a.durChapterTime));
        break;
      case 4:
        books.sort((a, b) => _sortAsc
            ? (a.lastCheckTime ?? 0).compareTo(b.lastCheckTime ?? 0)
            : (b.lastCheckTime ?? 0).compareTo(a.lastCheckTime ?? 0));
        break;
      case 5:
        books.sort((a, b) => _sortAsc
            ? (a.wordCount ?? 0).compareTo(b.wordCount ?? 0)
            : (b.wordCount ?? 0).compareTo(a.wordCount ?? 0));
        break;
      default:
        // 智能/手动：置顶(order<0)在前，其次按 order_num，再按最近阅读
        books.sort((a, b) {
          final pa = (a.order ?? 0) < 0 ? -1 : 0;
          final pb = (b.order ?? 0) < 0 ? -1 : 0;
          if (pa != pb) return pa.compareTo(pb);
          final oa = a.order ?? 0;
          final ob = b.order ?? 0;
          if (oa != ob) return oa.compareTo(ob);
          return b.durChapterTime.compareTo(a.durChapterTime);
        });
    }
    return books;
  }

  Future<void> _updateAllBooks() async {
    setState(() => _isUpdating = true);
    final provider = Provider.of<BookProvider>(context, listen: false);
    var toUpdate = provider.books
        .where((b) =>
            !b.local &&
            b.canUpdate &&
            b.origin != null &&
            b.noteUrl != null)
        .toList();
    if (_cfg.updateLimit > 0 && toUpdate.length > _cfg.updateLimit) {
      toUpdate = toUpdate.sublist(0, _cfg.updateLimit);
    }
    final sources = await _db.getAllSources(enabled: true);
    final sourceMap = {for (var s in sources) s.bookSourceUrl: s};
    int updated = 0;
    for (final book in toUpdate) {
      final source = sourceMap[book.origin];
      if (source == null) continue;
      try {
        final newChapters = await _engine.getToc(source, book.noteUrl!,
            bookInfo: book.jsContext());
        final oldChapters = await _db.getChapters(book.name, book.author);
        if (newChapters.length > oldChapters.length) {
          await _db.saveChapters(book.name, book.author, newChapters);
          book.lastChapter = newChapters.last.title;
          book.lastChapterIndex = newChapters.length - 1;
          book.latestChapterTime = DateTime.now().millisecondsSinceEpoch;
          book.lastCheckTime = DateTime.now().millisecondsSinceEpoch;
          await _db.updateBook(book);
          updated++;
        }
      } catch (_) {}
    }
    await provider.loadBooks();
    if (!mounted) return;
    setState(() => _isUpdating = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            '更新完成，共检查 ${toUpdate.length} 本，$updated 本有新章节')));
  }

  void _showSortDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('排序方式'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(_sortOptions.length, (index) {
            // 内部排序 -> 配置排序（用于持久化）
            const toCfg = {0: 4, 1: 1, 2: 2, 3: 0, 4: 3};
            return ListTile(
              title: Text(_sortOptions[index]),
              trailing: _sortBy == index
                  ? Icon(
                      _sortAsc ? Icons.arrow_upward : Icons.arrow_downward,
                      color: Colors.green)
                  : null,
              onTap: () async {
                setState(() {
                  if (_sortBy == index) {
                    _sortAsc = !_sortAsc;
                  } else {
                    _sortBy = index;
                  }
                });
                final prefs = await SharedPreferences.getInstance();
                final cfgIndex = toCfg[index];
                if (cfgIndex != null) {
                  await prefs.setInt('bs_sortType', cfgIndex);
                  await prefs.setBool('bs_sortAscending', _sortAsc);
                }
                if (mounted) Navigator.pop(context);
              },
            );
          }),
        ),
      ),
    );
  }

  void _showMoreMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(leading: const Icon(Icons.dashboard_outlined), title: const Text('首页模块视图'), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const HomeScreen())); }),
            ListTile(leading: const Icon(Icons.search), title: const Text('搜索书籍'), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen())); }),
            ListTile(leading: const Icon(Icons.refresh), title: const Text('一键更新'), onTap: () { Navigator.pop(context); _updateAllBooks(); }),
            const Divider(),
            ListTile(leading: const Icon(Icons.folder_open), title: const Text('本地导入'), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const LocalImportScreen())); }),
            ListTile(leading: const Icon(Icons.cloud_download), title: const Text('书源管理/网络导入'), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const SourceManageScreen())); }),
            const Divider(),
            ListTile(leading: const Icon(Icons.view_module), title: const Text('布局设置'), onTap: () async {
              Navigator.pop(context);
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const BookshelfConfigScreen()));
              await _reloadCfg();
            }),
            ListTile(leading: const Icon(Icons.sort), title: const Text('排序设置'), onTap: () { Navigator.pop(context); _showSortDialog(); }),
            ListTile(leading: const Icon(Icons.folder_special), title: const Text('分组管理'), onTap: () async {
              Navigator.pop(context);
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const GroupManageScreen()));
              await Provider.of<BookProvider>(context, listen: false).loadBooks();
            }),
            ListTile(leading: const Icon(Icons.select_all), title: const Text('多选模式'), onTap: () { Navigator.pop(context); setState(() => _selectMode = true); }),
            const Divider(),
            ListTile(leading: const Icon(Icons.bar_chart_outlined), title: const Text('阅读记录'), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const ReadRecordScreen())); }),
            ListTile(leading: const Icon(Icons.settings), title: const Text('设置'), onTap: () async {
              Navigator.pop(context);
              // 从设置页返回后重载配置，使 bs_showLocalBook 等开关即时生效
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
              await _reloadCfg();
            }),
            const Divider(),
            ListTile(leading: const Icon(Icons.delete_sweep, color: Colors.red), title: const Text('清空书架', style: TextStyle(color: Colors.red)), onTap: () async {
              Navigator.pop(context);
              final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('清空书架'), content: const Text('确定要清空所有书籍吗？此操作会同时删除已缓存章节。'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')), FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context, true), child: const Text('清空'))]));
              if (confirmed == true) {
                final provider = Provider.of<BookProvider>(context, listen: false);
                for (final book in provider.books) {
                  await _db.deleteBook(book.name, book.author);
                }
                await provider.loadBooks();
              }
            }),
          ]),
        ),
      ),
    );
  }

  /// 点击书籍：按「默认直接打开阅读」设置分流到阅读页或详情页
  Future<void> _openBook(Book book) async {
    bool defaultRead = false;
    try {
      defaultRead = (await SharedPreferences.getInstance()).getBool('oc_defaultRead') ?? false;
    } catch (_) {}
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) =>
        defaultRead ? readerForBook(book) : BookDetailScreen(book: book)));
  }

  void _showBookMenu(Book book) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(leading: const Icon(Icons.play_arrow), title: const Text('开始阅读'), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => readerForBook(book))); }),
            ListTile(leading: const Icon(Icons.info_outline), title: const Text('书籍详情'), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => BookDetailScreen(book: book))); }),
            ListTile(leading: const Icon(Icons.ios_share), title: const Text('导出书籍'), onTap: () async {
              Navigator.pop(context);
              final chapters = await _db.getChapters(book.name, book.author);
              if (chapters.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('暂无章节可导出'))); return; }
              try {
                final path = await ExportBookService.exportToTxt(book, chapters);
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已导出: $path')));
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导出失败: $e')));
              }
            }),
            const Divider(),
            ListTile(leading: const Icon(Icons.refresh), title: const Text('更新目录'), onTap: () async {
              Navigator.pop(context);
              if (book.local || book.origin == null || book.noteUrl == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('本地书籍无需更新'))); return; }
              final sources = await _db.getAllSources(enabled: true);
              final source = sources.where((s) => s.bookSourceUrl == book.origin).firstOrNull;
              if (source == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未找到对应书源或书源已停用'))); return; }
              try {
                final chapters = await _engine.getToc(source, book.noteUrl!,
                    bookInfo: book.jsContext());
                await _db.saveChapters(book.name, book.author, chapters);
                book.lastChapter = chapters.last.title;
                book.lastChapterIndex = chapters.length - 1;
                book.lastCheckTime = DateTime.now().millisecondsSinceEpoch;
                await _db.updateBook(book);
                await Provider.of<BookProvider>(context, listen: false).loadBooks();
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('更新完成，共${chapters.length}章')));
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('更新失败: $e')));
              }
            }),
            ListTile(leading: const Icon(Icons.swap_horiz), title: const Text('换源'), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => ChangeSourceScreen(book: book))); }),
            ListTile(leading: const Icon(Icons.image_outlined), title: const Text('换封面'), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => ChangeCoverScreen(book: book))); }),
            ListTile(leading: const Icon(Icons.download), title: const Text('缓存全部'), onTap: () { Navigator.pop(context); _cacheOneBook(book); }),
            ListTile(leading: const Icon(Icons.flag_outlined), title: const Text('书籍标记'), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => BookMarkingScreen(bookName: book.name, author: book.author))); }),
            ListTile(leading: const Icon(Icons.bookmark_border), title: const Text('添加书签'), onTap: () { Navigator.pop(context); _addBookmarkAtProgress(book); }),
            const Divider(),
            ListTile(leading: const Icon(Icons.move_down), title: const Text('移动到分组'), onTap: () { Navigator.pop(context); _showMoveGroupDialog(book); }),
            ListTile(leading: const Icon(Icons.push_pin_outlined), title: Text((book.order ?? 0) < 0 ? '取消置顶' : '置顶'), onTap: () async {
              Navigator.pop(context);
              book.order = (book.order ?? 0) < 0 ? 0 : -1;
              await _db.updateBook(book);
              await Provider.of<BookProvider>(context, listen: false).loadBooks();
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text((book.order ?? 0) < 0 ? '已置顶' : '已取消置顶')));
            }),
            ListTile(leading: const Icon(Icons.share), title: const Text('分享'), onTap: () async {
              Navigator.pop(context);
              await Share.share('《${book.name}》 - ${book.author}\n${book.intro ?? ''}', subject: book.name);
            }),
            const Divider(),
            ListTile(leading: const Icon(Icons.delete_outline, color: Colors.red), title: const Text('删除', style: TextStyle(color: Colors.red)), onTap: () async {
              Navigator.pop(context);
              final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: Text('删除《${book.name}》'), content: const Text('确定要删除这本书吗？将同时删除已缓存章节。'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')), FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context, true), child: const Text('删除'))]));
              if (confirmed == true) {
                await _db.deleteBook(book.name, book.author);
                await Provider.of<BookProvider>(context, listen: false).loadBooks();
              }
            }),
          ]),
        ),
      ),
    );
  }

  /// 在当前阅读进度处添加书签
  Future<void> _addBookmarkAtProgress(Book book) async {
    try {
      final chapters = await _db.getChapters(book.name, book.author)
        ..removeWhere((c) => c.isVolume);
      if (chapters.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('暂无章节，请先更新目录后再添加书签')));
        return;
      }
      final idx = book.durChapterIndex.clamp(0, chapters.length - 1);
      final ch = chapters[idx];
      final raw = (ch.content ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
      final excerpt = raw.length > 60 ? raw.substring(0, 60) : raw;
      await _db.addBookmark(Bookmark(
        bookName: book.name,
        bookAuthor: book.author,
        chapterIndex: ch.index,
        chapterTitle: ch.title,
        pageIndex: book.durChapterPos,
        content: excerpt.isEmpty ? null : excerpt,
      ));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已在《${ch.title}》添加书签')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('添加书签失败: $e')));
      }
    }
  }

  void _showMoveGroupDialog(Book book) {
    final provider = Provider.of<BookProvider>(context, listen: false);
    final controller = TextEditingController(text: book.group ?? '');
    // 移动分组仅支持用户自定义分组，虚拟分组（本地/音频/视频/未分组）不可作为目标
    final groups = provider.displayGroups()
        .where((g) => g != '全部' && !BookProvider.isVirtualGroup(g))
        .toList();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移动到分组'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (groups.isNotEmpty) Wrap(spacing: 8, runSpacing: 4, children: [
            for (final g in groups) ActionChip(label: Text(g), onPressed: () async {
              book.group = g;
              await _db.updateBook(book);
              await provider.loadBooks();
              if (mounted) Navigator.pop(context);
            }),
            ActionChip(label: const Text('未分组'), onPressed: () async {
              book.group = null;
              await _db.updateBook(book);
              await provider.loadBooks();
              if (mounted) Navigator.pop(context);
            }),
          ]),
          const SizedBox(height: 8),
          TextField(controller: controller, decoration: const InputDecoration(hintText: '输入新分组名称（留空为未分组）')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: () async {
            final t = controller.text.trim();
            book.group = t.isEmpty ? null : t;
            await _db.updateBook(book);
            await provider.loadBooks();
            if (mounted) Navigator.pop(context);
          }, child: const Text('确定')),
        ],
      ),
    );
  }

  String _fmtTime(int? ms) {
    if (ms == null || ms <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<BookProvider>(context);
    final books = _filteredBooks;
    final layout = provider.bookshelfLayout;
    return Scaffold(
      appBar: AppBar(
        title: !_searching
            ? const Text('书架')
            : TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                    hintText: '搜索书名/作者...', border: InputBorder.none),
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
        actions: [
          if (!_searching)
            IconButton(
                icon: const Icon(Icons.search),
                onPressed: () => setState(() => _searching = true)),
          if (_searching)
            IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _searching = false;
                    _searchQuery = '';
                  });
                }),
          if (_selectMode) ...[
            IconButton(icon: const Icon(Icons.select_all), tooltip: '全选', onPressed: () => setState(() { _selectedBooks..clear()..addAll(books); })),
            IconButton(icon: const Icon(Icons.flip), tooltip: '反选', onPressed: () => setState(() { final all = books.toSet(); final inverted = all.difference(_selectedBooks); _selectedBooks..clear()..addAll(inverted); })),
            IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() { _selectMode = false; _selectedBooks.clear(); })),
          ] else
            IconButton(icon: const Icon(Icons.more_vert), onPressed: _showMoreMenu),
        ],
        bottom: (_cfg.showTabMenu && !_selectMode)
            ? PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: _buildGroupTabs(provider))
            : null,
      ),
      body: _isUpdating
          ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(), SizedBox(height: 16), Text('正在更新...')]))
          : books.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.menu_book_outlined, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text('书架为空', style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                  const SizedBox(height: 8),
                  Text('去搜索或发现页面添加书籍', style: TextStyle(color: Colors.grey[500])),
                  const SizedBox(height: 24),
                  FilledButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen())), icon: const Icon(Icons.search), label: const Text('去搜索')),
                ]))
              : _wrapFastScroller(_buildBody(provider, books, layout)),
      bottomNavigationBar: _selectMode
          ? SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Divider(height: 1),
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                _batchBtn(Icons.drive_file_move_outline, '移动分组', _batchMoveGroup),
                _batchBtn(Icons.cloud_download_outlined, '缓存', _batchCache),
                _batchBtn(Icons.file_upload_outlined, '导出', _batchExport),
                _batchBtn(Icons.delete_sweep_outlined, '删除', _batchDelete, danger: true),
              ]),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: Align(alignment: Alignment.centerLeft, child: Text('已选 ${_selectedBooks.length} 本', style: const TextStyle(fontSize: 12, color: Colors.grey)))),
            ]))
          : null,
    );
  }

  Widget _buildGroupTabs(BookProvider provider) {
    final hideEmpty = _cfg.hideEmptyGroups && _searchQuery.isEmpty;
    var groups = provider.displayGroups(hideEmpty: hideEmpty);
    int Function(String) countOf = provider.bookCountOf;
    // bs_showLocalBook 关闭时本地书籍整体隐藏：页签计数与可见性按过滤后的集合计算，
    // 可见数为 0 的虚拟分组（如“本地”）不再展示，避免点进去是空书架
    if (!_cfg.showLocalBook) {
      int visibleOf(String g) => provider.books
          .where((b) => !b.local && BookProvider.bookInGroup(b, g))
          .length;
      groups = groups.where((g) => g == '全部' || visibleOf(g) > 0).toList();
      countOf = visibleOf;
    }
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (var i = 0; i < groups.length; i++) ...[
            FilterChip(
              label: Text(_chipLabel(groups[i], countOf(groups[i]), provider)),
              selected: provider.currentGroup == groups[i],
              onSelected: (_) => provider.setCurrentGroup(groups[i]),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  /// 分组页签文案：书籍数量（bs_showBookCount）与待更新数量（bs_showWaitUpdateCount）
  String _chipLabel(String group, int count, BookProvider provider) {
    var label = _cfg.showBookCount ? '$group $count' : group;
    if (_cfg.showWaitUpdateCount) {
      final wait = _waitUpdateCount(provider, group);
      if (wait > 0) label = '$label · 待更新$wait';
    }
    return label;
  }

  /// 待更新数量：可参与“一键更新”的网络书籍数（本地书、禁止更新、缺书源/目录地址的不计）
  int _waitUpdateCount(BookProvider provider, String group) => provider.books
      .where((b) =>
          BookProvider.bookInGroup(b, group) &&
          !b.local &&
          b.canUpdate &&
          b.origin != null &&
          b.noteUrl != null)
      .length;

  Widget _buildBody(BookProvider provider, List<Book> books, int layout) {
    // 平铺分组：全部视图且未搜索时，按分组分区
    if (_cfg.groupStyle == 1 &&
        provider.currentGroup == '全部' &&
        _searchQuery.isEmpty) {
      final groups = provider.displayGroups(hideEmpty: _cfg.hideEmptyGroups)
          .where((g) => g != '全部')
          .toList();
      final sections = <MapEntry<String, List<Book>>>[];
      for (final g in groups) {
        // 统一走分组判定：用户分组按 group 匹配，虚拟分组按属性匹配
        final gb = books.where((b) => BookProvider.bookInGroup(b, g)).toList();
        if (gb.isNotEmpty) sections.add(MapEntry(g, gb));
      }
      // 分组列表已含“未分组”虚拟分组时不再重复追加未分组分区
      if (!groups.contains(BookProvider.vGroupUngrouped)) {
        final ungrouped =
            books.where((b) => b.group == null || b.group!.isEmpty).toList();
        if (ungrouped.isNotEmpty) sections.add(MapEntry('未分组', ungrouped));
      }
      return ListView(
        controller: _scrollController,
        padding: const EdgeInsets.only(bottom: 12),
        children: [
          for (final sec in sections) ...[
            ListTile(
              dense: true,
              leading: const Icon(Icons.folder_outlined, size: 20),
              title: Text(sec.key,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              trailing: _cfg.showBookCount
                  ? Text('${sec.value.length}',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12))
                  : null,
            ),
            _shrinkLayout(sec.value, layout),
            const Divider(),
          ],
        ],
      );
    }
    return _buildBookList(books, layout);
  }

  /// 平铺分组下，单个分组内的布局（shrinkWrap，不独立滚动）
  Widget _shrinkLayout(List<Book> books, int layout) {
    switch (layout) {
      case 2:
      case 3:
      case 4:
        final cols = layout == 3
            ? (_cfg.columnCount + 1).clamp(2, 8)
            : _cfg.columnCount.clamp(1, 8);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            childAspectRatio: layout == 4 ? 0.6 : 0.65,
            crossAxisSpacing: layout == 3 ? 4 : 8,
            mainAxisSpacing: layout == 3 ? 4 : 8,
          ),
          itemCount: books.length,
          itemBuilder: (c, i) => layout == 4
              ? _buildCoverItem(books[i])
              : _buildGridItem(books[i], compact: layout == 3),
        );
      default:
        return Column(children: [for (final b in books) _buildListItem(b, compact: layout == 1 || _cfg.compactDetails)]);
    }
  }

  /// bs_showFastScroller：控制书架是否显示快速滚动条（常显滑块，可拖动快速定位）
  Widget _wrapFastScroller(Widget child) => _cfg.showFastScroller
      ? Scrollbar(controller: _scrollController, thumbVisibility: true, child: child)
      : child;

  Widget _buildBookList(List<Book> books, int layout) {
    switch (layout) {
      case 0:
      case 1:
        return ListView.separated(
          controller: _scrollController,
          padding: const EdgeInsets.all(8),
          itemCount: books.length,
          separatorBuilder: (_, __) => _cfg.showDivider
              ? const Divider(height: 1)
              : const SizedBox(height: 4),
          itemBuilder: (c, i) =>
              _buildListItem(books[i], compact: layout == 1 || _cfg.compactDetails),
        );
      case 2:
      case 3:
        final cols = layout == 3
            ? (_cfg.columnCount + 1).clamp(2, 8)
            : _cfg.columnCount.clamp(1, 8);
        return GridView.builder(
          controller: _scrollController,
          padding: EdgeInsets.all(layout == 3 ? 4 : 8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            childAspectRatio: 0.65,
            crossAxisSpacing: layout == 3 ? 4 : 8,
            mainAxisSpacing: layout == 3 ? 4 : 8,
          ),
          itemCount: books.length,
          itemBuilder: (c, i) =>
              _buildGridItem(books[i], compact: layout == 3),
        );
      case 4:
        return GridView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(12),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: _cfg.columnCount.clamp(1, 8),
            childAspectRatio: 0.6,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: books.length,
          itemBuilder: (c, i) => _buildCoverItem(books[i]),
        );
      default:
        return ListView.builder(
          controller: _scrollController,
          itemCount: books.length,
          itemBuilder: (c, i) => _buildListItem(books[i]),
        );
    }
  }

  Widget _buildListItem(Book book, {bool compact = false}) {
    final selected = _selectedBooks.contains(book);
    final coverW = compact ? 36.0 : (_cfg.coverWidth * 0.5).clamp(42.0, 90.0);
    final coverH = coverW * 1.4;
    final sub = <Widget>[
      Text(book.author, maxLines: 1, style: const TextStyle(fontSize: 12)),
    ];
    if (!compact) {
      if (_cfg.showLatestChapter) {
        sub.add(const SizedBox(height: 2));
        sub.add(Text(book.lastChapter ?? '暂无章节',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 11, color: Theme.of(context).colorScheme.primary)));
      }
      if (_cfg.showTags && (book.kind ?? '').isNotEmpty) {
        sub.add(const SizedBox(height: 2));
        sub.add(Text(book.kind!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: Colors.grey[600])));
      }
      if (_cfg.showSynopsis && (book.intro ?? '').isNotEmpty) {
        sub.add(const SizedBox(height: 2));
        sub.add(Text(book.intro!,
            maxLines: _cfg.synopsisLines,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: Colors.grey[600])));
      }
      if (_cfg.showLastUpdateTime) {
        final t = _fmtTime(book.lastCheckTime);
        if (t.isNotEmpty) {
          sub.add(const SizedBox(height: 2));
          sub.add(Text('更新于 $t',
              style: TextStyle(fontSize: 10, color: Colors.grey[500])));
        }
      }
    }
    return ListTile(
      leading: _buildCover(book, width: coverW, height: coverH),
      title: Text(book.name,
          maxLines: _cfg.maxTitleLines.clamp(1, 5),
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: compact
          ? Text('${book.author} · ${_cfg.showLatestChapter ? (book.lastChapter ?? '') : ''}',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11))
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: sub),
      trailing: _selectMode
          ? Checkbox(value: selected, onChanged: (_) => _toggleSelect(book))
          : (compact ? null : const Icon(Icons.chevron_right)),
      selected: selected,
      onTap: () => _selectMode
          ? _toggleSelect(book)
          : _openBook(book),
      onLongPress: () =>
          _selectMode ? _toggleSelect(book) : _showBookMenu(book),
    );
  }

  Widget _buildGridItem(Book book, {required bool compact}) {
    final selected = _selectedBooks.contains(book);
    return GestureDetector(
      onTap: () => _selectMode
          ? _toggleSelect(book)
          : _openBook(book),
      onLongPress: () =>
          _selectMode ? _toggleSelect(book) : _showBookMenu(book),
      child: Container(
        decoration: selected
            ? BoxDecoration(
                border: Border.all(
                    color: Theme.of(context).colorScheme.primary, width: 2),
                borderRadius: BorderRadius.circular(8))
            : null,
        child: Column(children: [
          Expanded(child: _buildCover(book, width: double.infinity, height: double.infinity, radius: 8)),
          Padding(
            padding: EdgeInsets.all(compact ? 4 : 8),
            child: Text(book.name,
                maxLines: _cfg.maxTitleLines.clamp(1, 5),
                textAlign: _cfg.centerTitle ? TextAlign.center : TextAlign.start,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: _cfg.compactTitle ? 11 : (compact ? 11 : 13))),
          ),
        ]),
      ),
    );
  }

  Widget _buildCoverItem(Book book) {
    final selected = _selectedBooks.contains(book);
    return GestureDetector(
      onTap: () => _selectMode
          ? _toggleSelect(book)
          : _openBook(book),
      onLongPress: () =>
          _selectMode ? _toggleSelect(book) : _showBookMenu(book),
      child: Container(
        decoration: selected
            ? BoxDecoration(
                border: Border.all(
                    color: Theme.of(context).colorScheme.primary, width: 3),
                borderRadius: BorderRadius.circular(12))
            : null,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: _buildCover(book,
              width: double.infinity, height: double.infinity, radius: 0),
        ),
      ),
    );
  }

  /// 未读角标。width/height 为有限值时用 SizedBox 固定，无限值（网格）时填满父级
  Widget _withBadge(Book book, Widget child, double width, double height) {
    final unread = _unread(book);
    bool badge = false;
    bool dot = false;
    if (_cfg.showUnread && unread > 0) {
      badge = true;
    } else if (_cfg.showUnreadNew && unread > 0) {
      dot = true;
    }
    if (!badge && !dot) return child;
    final badgeWidget = Positioned(
      right: 2,
      top: 2,
      child: badge
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(9)),
              child: Text(unread > 99 ? '99+' : '$unread',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold)),
            )
          : Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                  color: Colors.redAccent, shape: BoxShape.circle)),
    );
    final stack = Stack(fit: StackFit.expand, children: [child, badgeWidget]);
    if (width.isFinite && height.isFinite) {
      return SizedBox(width: width, height: height, child: stack);
    }
    return stack;
  }

  Widget _buildCover(Book book,
      {required double width, required double height, double radius = 4}) {
    final url = (book.customCoverUrl != null && book.customCoverUrl!.isNotEmpty)
        ? book.customCoverUrl
        : book.coverUrl;
    Widget img;
    if (url != null && url.isNotEmpty) {
      // 注意：cover_onlyWifi（仅 WiFi 加载封面）已降级为仅记录（见 _CoverCfg.onlyWifi），
      // 不阻断网络封面加载，避免新增依赖。
      img = Image.network(url,
          width: width,
          height: height,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              _buildDefaultCover(book, width, height, radius));
    } else {
      img = _buildDefaultCover(book, width, height, radius);
    }
    // 封面叠加书名/作者文字（cover_showName / cover_showAuthor）
    final overlay = _buildCoverTextOverlay(book);
    if (overlay != null) {
      img = Stack(fit: StackFit.expand, children: [img, overlay]);
    }
    final rounded = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: img,
    );
    final shadowed = _cfg.coverShadow
        ? Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 4,
                    offset: Offset(1, 2)),
              ],
            ),
            child: rounded,
          )
        : rounded;
    return _withBadge(book, shadowed, width, height);
  }

  /// 封面底部叠加的文字（书名/作者），受封面配置 cover_showName / cover_showAuthor 控制
  Widget? _buildCoverTextOverlay(Book book) {
    if (!_coverCfg.showName && !_coverCfg.showAuthor) return null;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final textColor = Color(dark ? _coverCfg.nightTextColor : _coverCfg.dayTextColor);
    final lines = <Widget>[
      if (_coverCfg.showName)
        Text(book.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: textColor,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                shadows: const [Shadow(blurRadius: 2)])),
      if (_coverCfg.showAuthor)
        Text(book.author,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: textColor,
                fontSize: 9,
                shadows: const [Shadow(blurRadius: 2)])),
    ];
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x00000000), Color(0x99000000)],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: lines,
        ),
      ),
    );
  }

  Widget _buildDefaultCover(
      Book book, double width, double height, double radius) {
    // 封面配置 cover_useDefault：无封面/加载失败时显示统一默认占位。
    // 本版本封面配置页仅提供默认颜色（cover_defaultColor）与可选的本地图片路径
    // （cover_defaultImage，配置页暂未提供入口），故：有图片路径则用 Image.file
    // 容错加载，否则用配置颜色 + Icons.book 图标占位。
    if (_coverCfg.useDefault) {
      final bg = Color(_coverCfg.defaultColor);
      final iconSize = (width.isFinite ? width : 48.0) * 0.4;
      final imgPath = _coverCfg.defaultImage;
      Widget placeholder = Container(
        width: width,
        height: height,
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(radius)),
        child: Center(
          child: Icon(Icons.book,
              size: iconSize.clamp(16.0, 64.0), color: Colors.white70),
        ),
      );
      if (imgPath != null && imgPath.isNotEmpty) {
        // 本地图片路径容错：文件不存在或解码失败时回退到图标占位
        return Image.file(
          File(imgPath),
          width: width,
          height: height,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => placeholder,
        );
      }
      return placeholder;
    }
    const colors = [
      Colors.blueGrey,
      Colors.brown,
      Colors.teal,
      Colors.indigo,
      Colors.deepOrange,
      Colors.purple
    ];
    final color = colors[book.name.hashCode.abs() % colors.length];
    return Container(
      width: width,
      height: height,
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(radius)),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Text(book.name,
              maxLines: 3,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _batchBtn(IconData icon, String label, VoidCallback onTap,
      {bool danger = false}) {
    final color = danger ? Colors.red : null;
    return TextButton.icon(
      onPressed: _selectedBooks.isEmpty ? null : onTap,
      icon: Icon(icon, size: 20, color: color),
      label: Text(label, style: TextStyle(color: color, fontSize: 13)),
    );
  }

  Future<void> _batchMoveGroup() async {
    final provider = Provider.of<BookProvider>(context, listen: false);
    // 移动分组仅支持用户自定义分组，虚拟分组（本地/音频/视频/未分组）不可作为目标
    final groups = provider.displayGroups()
        .where((g) => g != '全部' && !BookProvider.isVirtualGroup(g))
        .toList();
    final controller = TextEditingController();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移动到分组'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final g in groups)
              ActionChip(label: Text(g), onPressed: () async {
                for (final b in _selectedBooks) {
                  b.group = g;
                  await _db.updateBook(b);
                }
                if (mounted) {
                  Navigator.pop(context);
                  await provider.loadBooks();
                  setState(() {
                    _selectMode = false;
                    _selectedBooks.clear();
                  });
                }
              }),
            ActionChip(label: const Text('未分组'), onPressed: () async {
              for (final b in _selectedBooks) {
                b.group = null;
                await _db.updateBook(b);
              }
              if (mounted) {
                Navigator.pop(context);
                await provider.loadBooks();
                setState(() {
                  _selectMode = false;
                  _selectedBooks.clear();
                });
              }
            }),
          ]),
          const SizedBox(height: 12),
          TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: '新分组名称')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: () async {
            final g = controller.text.trim();
            if (g.isEmpty) return;
            for (final b in _selectedBooks) {
              b.group = g;
              await _db.updateBook(b);
            }
            if (mounted) {
              Navigator.pop(context);
              await provider.loadBooks();
              setState(() {
                _selectMode = false;
                _selectedBooks.clear();
              });
            }
          }, child: const Text('确定')),
        ],
      ),
    );
  }

  Future<void> _batchCache() async {
    final picked = List.of(_selectedBooks);
    setState(() {
      _selectMode = false;
      _selectedBooks.clear();
    });
    int totalOk = 0, totalFail = 0, done = 0;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (d) => StatefulBuilder(builder: (d, setP) {
        _cacheBooksWithProgress(picked, (ok, fail, d2, t2) {
          setP(() {
            totalOk = ok;
            totalFail = fail;
            done = d2;
          });
        });
        return AlertDialog(
          title: const Text('批量缓存'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            LinearProgressIndicator(
                value: picked.isEmpty ? 0 : done / picked.length),
            const SizedBox(height: 12),
            Text('进度 $done/${picked.length}，成功 $totalOk 章，失败 $totalFail 章'),
          ]),
        );
      }),
    );
  }

  Future<void> _cacheOneBook(Book book) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (d) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('正在缓存章节...'),
            ]),
          ),
        ),
      ),
    );
    final r = await _cacheBook(book);
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '缓存完成: 成功${r.ok}章${r.fail > 0 ? ', 失败${r.fail}章' : ''}')));
    }
  }

  /// 逐章缓存一本书，返回成功/失败计数
  Future<({int ok, int fail})> _cacheBook(Book book) async {
    int ok = 0, fail = 0;
    if (book.local || book.origin == null || book.noteUrl == null) {
      return (ok: ok, fail: fail);
    }
    final sources = await _db.getAllSources(enabled: true);
    final source =
        sources.where((s) => s.bookSourceUrl == book.origin).firstOrNull;
    if (source == null) return (ok: ok, fail: fail);
    final chapters = await _db.getChapters(book.name, book.author);
    final engine = BookSourceEngine();
    for (final ch in chapters) {
      if (ch.isVolume || (ch.content ?? '').isNotEmpty) continue;
      try {
        final content = await engine.getContent(source, ch.url,
            bookInfo: book.jsContext(),
            chapter: ch.jsContext(book.bookUrl));
        if (content != null && content.isNotEmpty) {
          await _db.updateChapterContent(
              book.name, book.author, ch.index, content);
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

  Future<void> _cacheBooksWithProgress(List<Book> books,
      void Function(int ok, int fail, int done, int total) onProgress) async {
    int ok = 0, fail = 0;
    for (var i = 0; i < books.length; i++) {
      final r = await _cacheBook(books[i]);
      ok += r.ok;
      fail += r.fail;
      onProgress(ok, fail, i + 1, books.length);
    }
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '批量缓存完成: 成功$ok章${fail > 0 ? ', 失败$fail章' : ''}')));
    }
  }

  Future<void> _batchDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除书籍'),
        content: Text('确定删除选中的 ${_selectedBooks.length} 本书吗？将同时删除已缓存章节。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('删除')),
        ],
      ),
    );
    if (confirmed == true) {
      for (final book in _selectedBooks) {
        await _db.deleteBook(book.name, book.author);
      }
      if (mounted) {
        final p = Provider.of<BookProvider>(context, listen: false);
        await p.loadBooks();
        setState(() {
          _selectMode = false;
          _selectedBooks.clear();
        });
      }
    }
  }

  Future<void> _batchExport() async {
    final picked = List.of(_selectedBooks);
    setState(() {
      _selectMode = false;
      _selectedBooks.clear();
    });
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
        // 文件名去除非法字符
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

  void _toggleSelect(Book book) => setState(() =>
      _selectedBooks.contains(book) ? _selectedBooks.remove(book) : _selectedBooks.add(book));
}
