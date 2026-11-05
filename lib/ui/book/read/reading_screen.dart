
import 'dart:async';
import 'dart:io';
import 'dart:ui' show FontFeature;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_chapter.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/data/model/bookmark.dart';
import 'package:legado_md3/data/model/db_models.dart';
import 'package:legado_md3/data/model/read_config.dart';
import 'package:legado_md3/di/book_provider.dart';
import 'package:legado_md3/ui/book/read/text_paginator.dart';
import 'package:legado_md3/help/config/read_menu_config.dart';
import 'package:legado_md3/help/readaloud/chinese_converter.dart';
import 'package:legado_md3/help/readaloud/reading_record.dart';
import 'package:legado_md3/help/readaloud/tts_service.dart';
import 'package:legado_md3/help/source/content_services.dart';
import 'package:legado_md3/help/source/replace_rule_service.dart';
import 'package:legado_md3/help/source/source_engine.dart';
import 'package:legado_md3/help/storage/local_book_parser.dart';
import 'package:legado_md3/help/translate/translation_service.dart';
import 'package:legado_md3/ui/book/chapter/chapter_list_screen.dart';
import 'package:legado_md3/ui/book/detail/book_detail_screen.dart';
import 'package:legado_md3/ui/book/read/config/reading_settings_screen.dart';
import 'package:legado_md3/ui/book/read/dict_lookup_sheet.dart';
import 'package:legado_md3/ui/book/read/tts_player_screen.dart';
import 'package:legado_md3/ui/book/read/widgets/download_sheet.dart';
import 'package:legado_md3/ui/book/search/search_content_screen.dart';
import 'package:legado_md3/ui/book/source/source_login_screen.dart';
import 'package:legado_md3/ui/book/source/source_edit_screen.dart';
import 'package:legado_md3/ui/browser/browser_screen.dart';
import 'package:legado_md3/ui/config/replace_rule_screen.dart';
import 'package:legado_md3/ui/config/txt_toc_rule_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReadingScreen extends StatefulWidget {
  final Book book;
  final int? initialChapter;
  const ReadingScreen({super.key, required this.book, this.initialChapter});

  @override
  State<ReadingScreen> createState() => _ReadingScreenState();
}

class _ReadingScreenState extends State<ReadingScreen> with SingleTickerProviderStateMixin {
  final DatabaseService _db = DatabaseService();
  final BookSourceEngine _engine = BookSourceEngine();
  final TtsService _ttsService = TtsService();
  static const _wakeChannel = MethodChannel('legado/wakelock');
  bool _wakeEnabled = false;
  List<int> _clickActions = [1,3,2,1,3,2,1,3,2];
  Future<void> _loadClickActions() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('click_actions');
    if (raw != null) {
      final l = raw.split(',').map((e)=>int.tryParse(e)??2).toList();
      if (l.length==9) _clickActions = l;
    }
  }
  final ReadingRecordService _recordService = ReadingRecordService();
  List<BookChapter> _chapters = [];
  int _currentChapterIndex = 0;
  String? _content;
  bool _isLoading = true;
  bool _isLoadingChapter = false;
  late AnimationController _menuController;
  final PageController _pageController = PageController();
  Timer? _autoReadTimer;
  bool _autoReadOn = false;
  Timer? _clockTimer;
  String _currentTime = '';
  // 系统电量读数（0-100）。当前 pubspec 无 battery 插件且离线环境不允许新增依赖，
  // 暂无真实读数来源，保持 null：电量类槽位统一降级为图标显示。
  // 后续如接入 battery_plus，只需在 initState 中异步赋值即可自动启用百分比显示。
  int? _batteryLevel;
  int _currentPage = 0;
  // 真实分页所用可用文本区域（宽/高），由 LayoutBuilder 测量后回填
  double? _pageW;
  double? _pageH;
  // 替换净化开关（点击区域/菜单可切换，默认跟随 oc_replaceDefault）
  bool _purifyEnabled = true;
  List<String> _pages = [];
  // 重排防抖：连续触发（布局变化等）时 100ms 内只做最后一次
  Timer? _repaginateTimer;
  // 章节进度滑块拖动中的局部下标（null 表示未在拖动，跟随 _currentChapterIndex）
  int? _dragChapterIndex;
  // 正文搜索命中其他章时的章内偏移：章节加载分页完成后按此定位页码
  int? _pendingPosInChapter;
  // 文本选择菜单沿用可配置顺序（对齐 E TextActionMenu）；其余菜单按 E 的 ReadMenu 硬编码顺序，
  // 不再使用 Klys 自有的「阅读菜单配置」默认列表（E 无可配置阅读菜单）。
  List<String> _selectMenuOrder = List.of(ReadMenuConfig.defaultSelectMenu);
  // 对齐 E res/menu/book_read.xml 的 overflow 菜单（showAsAction="never"）项与顺序。
  static const List<String> _eMoreMenuOrder = [
    'addbookmark',       // 添加书签
    'contentedit',       // 编辑内容
    'pageanim',          // 翻页动画
    'reverse',           // 内容倒序
    'simulated',         // 模拟阅读（checkable）
    'replace',           // 启用替换（checkable）
    'sametitle',         // 同名章节去除（checkable）
    'resegment',         // 重新分段（checkable）
    'delruby',           // 删除注音标签（checkable，E epub 组）
    'delh',              // 删除标题标签（checkable，E epub 组）
    'imagestyle',        // 图片样式
    'updatetoc',         // 更新目录
    'effectivereplace',  // 生效替换
    'log',               // 日志
    'help',              // 帮助
  ];
  // 对齐 E book_read.xml 的 checkable 菜单项：持久作用于章节内容后处理（非一次性操作）。
  bool _reSegmentEnabled = false;
  bool _delRubyEnabled = false;
  bool _delHEnabled = false;
  bool _removeSameTitle = false;
  // 实验室开关：正文是否允许自由选择复制（默认开启）
  bool _textSelectable = true;
  // 实验室开关：分页估算诊断（输出分页计算过程到控制台）
  bool _pageDiag = false;
  // 实验室开关：加速下载（预缓存时多章节并发拉取）
  bool _accelerateDownload = false;
  // 设置项：禁用水平滑动翻页（read_disableHorizontalSwipe）。
  // 只禁横向 PageView 的手势翻页，纵向滚动模式与代码跳页（点击/音量键/菜单）不受影响。
  bool _disableHorizontalSwipe = false;
  // 文字抗锯齿（oc_antiAlias，Flutter 引擎限制，用禁用字距/连字近似）
  bool _antiAlias = true;
  // 下载缓存配置：阅读时向后预缓存的章节数（0 表示关闭）
  int _preDownload = 5;
  // 正在预缓存的章节下标，避免重复请求
  final Set<int> _prefetching = {};
  // 当前书籍来源书源（对齐 E ReadMenu.tvSourceAction：网络书显示「书源」操作菜单）
  BookSource? _currentBookSource;

  /// 加载当前书籍来源书源，供顶部「书源」操作菜单使用。
  Future<void> _loadCurrentSource() async {
    final origin = widget.book.origin;
    if (origin == null || origin.isEmpty) return;
    try {
      final sources = await _db.getAllSources();
      BookSource? s;
      for (final e in sources) {
        if (e.bookSourceUrl == origin) { s = e; break; }
      }
      if (mounted) setState(() => _currentBookSource = s);
    } catch (_) {}
  }

  /// 书源操作菜单（对齐 E res/menu/book_read_source.xml：登录 / 章节购买 / 编辑书源 / 禁用书源）
  void _showSourceMenu() {
    final source = _currentBookSource;
    if (source == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未找到当前书源')));
      return;
    }
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.login), title: const Text('书源登录'),
              onTap: () { Navigator.pop(ctx); Navigator.push(context, MaterialPageRoute(builder: (_) => SourceLoginScreen(source: source))); }),
            ListTile(leading: const Icon(Icons.payment), title: const Text('章节购买'),
              subtitle: const Text('在内置浏览器打开当前章节链接'),
              onTap: () {
                Navigator.pop(ctx);
                final url = _chapters.isNotEmpty ? _chapters[_currentChapterIndex].url : '';
                if (url.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('当前章节无链接')));
                  return;
                }
                Navigator.push(context, MaterialPageRoute(builder: (_) => BrowserScreen(url: url, title: _chapters[_currentChapterIndex].title)));
              }),
            ListTile(leading: const Icon(Icons.edit_note), title: const Text('编辑书源'),
              onTap: () { Navigator.pop(ctx); Navigator.push(context, MaterialPageRoute(builder: (_) => SourceEditScreen(source: source))); }),
            ListTile(leading: const Icon(Icons.block), title: const Text('禁用书源'),
              onTap: () async {
                Navigator.pop(ctx);
                source.enabled = false; // 对齐 E menu_disable_source：禁用当前书源
                await _db.updateSource(source);
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已禁用书源「${source.bookSourceName}」')));
              }),
          ],
        ),
      ),
    );
  }

  Future<void> _loadDownloadConfig() async {
    final cfg = context.read<ReadProvider>().config;
    if (mounted) setState(() => _preDownload = cfg.preDownloadCount > 0 ? cfg.preDownloadCount : 5);
  }

  /// 后台预缓存当前章之后的 [_preDownload] 章，失败静默，不影响阅读
  Future<void> _prefetch(int fromIndex) async {
    if (_preDownload <= 0) return;
    List<BookSource> sources = [];
    try {
      sources = await _db.getAllSources(enabled: true);
    } catch (_) { return; }
    final source = sources.where((s) => s.bookSourceUrl == widget.book.origin).firstOrNull;
    if (source == null) return;

    Future<void> fetchOne(int i) async {
      if (_prefetching.contains(i)) return;
      _prefetching.add(i);
      try {
        final content = await _engine.getContent(source, _chapters[i].url,
            bookInfo: widget.book.jsContext(),
            chapter: _chapters[i].jsContext(widget.book.bookUrl));
        if (content != null && content.isNotEmpty) {
          await _db.updateChapterContent(widget.book.name, widget.book.author, i, content);
        }
      } catch (_) {
      } finally {
        _prefetching.remove(i);
      }
    }

    final todo = <int>[];
    for (int i = fromIndex + 1; i <= fromIndex + _preDownload && i < _chapters.length; i++) {
      // 单章查询判断是否已缓存，避免把全书正文读进内存
      final cached = await _db.getChapter(widget.book.name, widget.book.author, i);
      final already = cached != null && cached.content != null && cached.content!.isNotEmpty;
      if (already || _prefetching.contains(i)) continue;
      if (_chapters[i].url.isEmpty) continue;
      todo.add(i);
    }
    if (todo.isEmpty) return;
    if (_accelerateDownload) {
      // 加速下载：多章节并发
      await Future.wait(todo.map(fetchOne));
    } else {
      for (final i in todo) {
        await fetchOne(i);
      }
    }
  }

  Future<void> _loadLabFlags() async {
    final p = await SharedPreferences.getInstance();
    final labOn = p.getBool('lab_enabled') ?? false;
    if (mounted) {
      setState(() {
        _textSelectable = !labOn || (p.getBool('lab_selectable') ?? true);
        _pageDiag = labOn && (p.getBool('lab_pageDiag') ?? false);
        _accelerateDownload = labOn && (p.getBool('lab_accDownload') ?? false);
        _antiAlias = p.getBool('oc_antiAlias') ?? true;
        // 阅读页禁用水平滑动翻页（read_disableHorizontalSwipe）
        _disableHorizontalSwipe = p.getBool('read_disableHorizontalSwipe') ?? false;
      });
    }
  }

  Future<void> _loadMenuConfig() async {
    // 对齐 E：只保留文本选择菜单（TextActionMenu）的可配置顺序；其余菜单硬编码为 E 的顺序。
    final sm = await ReadMenuConfig.load(ReadMenuConfig.kSelectMenu, ReadMenuConfig.defaultSelectMenu);
    final p = await SharedPreferences.getInstance();
    if (mounted) setState(() {
      _selectMenuOrder = sm;
      // 对齐 E book_read.xml checkable 菜单项：读取持久化的内容处理开关
      _reSegmentEnabled = p.getBool('read_reSegment') ?? false;
      _delRubyEnabled = p.getBool('read_delRuby') ?? false;
      _delHEnabled = p.getBool('read_delH') ?? false;
      _removeSameTitle = p.getBool('read_removeSameTitle') ?? false;
    });
  }

  @override
  void initState() {
    super.initState();
    _loadClickActions();
    _loadCurrentSource();
    _restoreCharset();
    _loadMenuConfig();
    _loadLabFlags();
    _loadDownloadConfig();
    ContentDictService.reload();
    HighlightService.reload().then((_) { if (mounted) setState(() {}); });
    _menuController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _currentChapterIndex = widget.initialChapter ?? widget.book.durChapterIndex;
    _recordService.startSession(widget.book.name, widget.book.author);
    _ttsService.init();
    // 净化开关默认跟随「其它设置-替换默认启用」
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() => _purifyEnabled = p.getBool('oc_replaceDefault') ?? true);
    });
    _loadData();
    // 时钟：每分钟更新一次时间显示
    _currentTime = _formatTime(DateTime.now());
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _currentTime = _formatTime(DateTime.now()));
    });
    // 屏幕常亮 + 沉浸/全屏/方向：延迟到第一帧后读取 config
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cfg = context.read<ReadProvider>().config;
      _applyWakeLock(cfg.keepScreenOn);
      _applyScreenMode(cfg);
    });
  }

  /// 应用沉浸式/全屏/屏幕方向设置
  void _applyScreenMode(ReadConfig config) {
    try {
      if (config.immersiveMode || config.fullScreen) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
      if (config.screenOrientation == 1) {
        SystemChrome.setPreferredOrientations(
            [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
      } else if (config.screenOrientation == 2) {
        SystemChrome.setPreferredOrientations(
            [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      } else {
        SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _autoReadTimer?.cancel();
    _clockTimer?.cancel();
    _repaginateTimer?.cancel();
    _menuController.dispose();
    _pageController.dispose();
    _recordService.endSession(
      chapterIndex: _currentChapterIndex,
      chapterTitle: _chapters.isNotEmpty ? _chapters[_currentChapterIndex].title : null,
    );
    _ttsService.dispose();
    _applyWakeLock(false);
    // 恢复系统 UI 与屏幕方向
    try {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    } catch (_) {}
    super.dispose();
  }

  Future<void> _applyWakeLock(bool enable) async {
    if (_wakeEnabled == enable) return;
    _wakeEnabled = enable;
    try {
      await _wakeChannel.invokeMethod(enable ? 'enable' : 'disable');
    } catch (_) {}
  }

  Future<void> _restoreCharset() async {
    final p = await SharedPreferences.getInstance();
    final cs = p.getString('force_charset');
    if (cs != null && cs != 'UTF-8') _engine.setCharset(cs.toLowerCase());
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    _chapters = await _db.getChapters(widget.book.name, widget.book.author);

    if (_chapters.isEmpty && widget.book.origin != null) {
      // 尝试从网络获取目录
      await _fetchTocFromNetwork();
    }

    if (_chapters.isNotEmpty) {
      if (_currentChapterIndex >= _chapters.length) _currentChapterIndex = 0;
      await _loadChapterContent(_currentChapterIndex);
    } else {
      // 没有章节，显示书籍信息
      _content = widget.book.intro ?? '暂无内容';
      _pages = [_content!];
    }

    if (mounted) setState(() => _isLoading = false);

    // 自动翻页 / 实验室「模拟阅读」：进入阅读页后自动开始翻页
    try {
      final cfg = context.read<ReadProvider>().config;
      if (cfg.autoNextPage || cfg.simulatedReading) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_autoReadOn) _startAutoRead();
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchTocFromNetwork() async {
    try {
      final sources = await _db.getAllSources(enabled: true);
      final source = sources.where((s) => s.bookSourceUrl == widget.book.origin).firstOrNull;
      if (source != null && widget.book.noteUrl != null) {
        final chapters = await _engine.getToc(source, widget.book.noteUrl!,
            bookInfo: widget.book.jsContext());
        if (chapters.isNotEmpty) {
          _chapters = chapters;
          await _db.saveChapters(widget.book.name, widget.book.author, chapters);
        }
      }
    } catch (_) {}
  }

  /// 加载章节正文。
  /// [forceSource] 章节换源时传入新书源：跳过本地旧源缓存，强制用新源的章节 URL 走网络拉取。
  Future<void> _loadChapterContent(int index, {int? targetPage, BookSource? forceSource}) async {
    if (index < 0 || index >= _chapters.length) return;
    setState(() => _isLoadingChapter = true);

    final chapter = _chapters[index];
    // 先尝试从数据库读取缓存（换源时缓存属于旧源，必须跳过强制走网络）
    // 单章查询：只取当前章一行，避免「读一章 = getChapters 读全书」
    final cached = forceSource == null
        ? await _db.getChapter(widget.book.name, widget.book.author, index)
        : null;
    if (cached != null && cached.content != null && cached.content!.isNotEmpty) {
      _content = cached.content;
    } else if (widget.book.local && widget.book.fileName != null) {
      // 本地书：从文件读取章节内容
      try {
        final content = await LocalBookParser.readChapter(widget.book.fileName!, index, _chapters);
        if (content != null && content.isNotEmpty) {
          _content = content;
          await _db.updateChapterContent(widget.book.name, widget.book.author, index, content);
        } else {
          _content = '无法读取本地文件内容';
        }
      } catch (e) {
        _content = '读取本地文件失败: $e';
      }
    } else if (widget.book.origin != null) {
      // 从网络获取
      try {
        final sources = await _db.getAllSources(enabled: true);
        // 换源时优先使用传入的新书源，否则按书籍当前 origin 查找
        final source = forceSource ??
            sources.where((s) => s.bookSourceUrl == widget.book.origin).firstOrNull;
        if (source != null && chapter.url.isNotEmpty) {
          // 加载替换净化规则
          final replaceRules = await _db.getReplaceRules();
          final content = await _engine.getContent(source, chapter.url,
              replaceRules: replaceRules,
              bookInfo: widget.book.jsContext(),
              chapter: chapter.jsContext(widget.book.bookUrl));
          if (content != null) {
            _content = content;
            await _db.updateChapterContent(widget.book.name, widget.book.author, index, content);
          }
        }
      } catch (_) {
        _content = '加载失败，请检查网络';
      }
    } else {
      _content = chapter.content ?? '暂无内容';
    }

    // 应用「字典规则」内容替换词典（关闭或无规则时原样返回）
    if (_content != null) _content = await ContentDictService.apply(_content!);

    // 应用替换净化规则（净化开关控制是否应用；确保本地缓存内容也能被净化）
    if (_content != null && _content!.isNotEmpty) {
      try {
        if (_purifyEnabled) {
          final replaceRules = await _db.getReplaceRules();
          if (replaceRules.isNotEmpty) {
            final svc = ReplaceRuleService();
            _content = svc.applyRules(_content!, replaceRules);
          }
        }
      } catch (_) {}
    }

    // 简繁转换（chineseConverter: 0不转换 1转简 2转繁）
    if (_content != null && _content!.isNotEmpty) {
      final mode = context.read<ReadProvider>().config.chineseConverter;
      if (mode != 0) {
        _content = ChineseConverter.convert(_content!, mode);
      }
    }

    // 对齐 E res/menu/book_read.xml 的 checkable 菜单项：这些开关持久作用于正文后处理，
    // 而非一次性文本操作；切换后重新加载当前章即可生效。
    if (_content != null && _content!.isNotEmpty) {
      var text = _content!;
      if (_delRubyEnabled) {
        text = text
            .replaceAll(RegExp(r'<ruby[^>]*>'), '')
            .replaceAll('</ruby>', '')
            .replaceAll(RegExp(r'<rt[^>]*>.*?</rt>', dotAll: true), '');
      }
      if (_delHEnabled) {
        text = text
            .replaceAll(RegExp(r'<h[1-6][^>]*>'), '')
            .replaceAll(RegExp(r'</h[1-6]>'), '');
      }
      if (_removeSameTitle && index < _chapters.length) {
        // 同名章节去除：正文首行与章节标题重复时去掉该行（对齐 E same_title_removed）
        final title = _chapters[index].title.trim();
        final lines = text.split('\n');
        if (title.isNotEmpty && lines.isNotEmpty && lines.first.trim() == title) {
          text = lines.sublist(1).join('\n');
        }
      }
      if (_reSegmentEnabled) {
        var re = text.replaceAll(RegExp(r'\s+'), '');
        re = re.replaceAllMapped(RegExp(r'[。！？…](?!["”』」])'), (m) => '${m[0]}\n\n');
        text = re;
      }
      _content = text;
    }

    _paginateContent();
    _currentChapterIndex = index;
    // 跳转到指定页码（书签跳转或恢复阅读进度）
    final pendingPos = _pendingPosInChapter;
    if (pendingPos != null) {
      // 正文搜索跳转：按章内字符偏移定位到具体页
      _pendingPosInChapter = null;
      _currentPage = _pageForOffset(pendingPos);
    } else if (targetPage != null && targetPage >= 0 && targetPage < _pages.length) {
      _currentPage = targetPage;
    } else if (widget.initialChapter == null && index == widget.book.durChapterIndex) {
      // 恢复上次阅读页码（仅首次加载时）
      // durChapterPos 是非空 int（默认 0），无需再做空判断
      final savedPos = widget.book.durChapterPos;
      if (savedPos > 0 && savedPos < _pages.length) {
        _currentPage = savedPos;
      }
    }
    // 后台预缓存后续章节（不 await，不阻塞当前阅读）
    unawaited(_prefetch(index));
    // 保存阅读进度
    final provider = Provider.of<BookProvider>(context, listen: false);
    await provider.saveReadingProgress(widget.book, index, _currentPage);

    if (mounted) setState(() => _isLoadingChapter = false);
  }

  /// 章节换源：切换到新书源后，在新源目录中重新定位当前章节，
  /// 用新源的章节 URL 重新拉取正文（而非沿用旧源的章节地址）。
  /// 返回 null 表示换源成功，非 null 为错误提示。
  Future<String?> _changeChapterSource(BookSource source) async {
    // 记录换源前的章节标题与下标，用于在新源目录中定位
    final oldTitle = (_chapters.isNotEmpty && _currentChapterIndex < _chapters.length)
        ? _chapters[_currentChapterIndex].title
        : '';
    final oldIndex = _currentChapterIndex;
    setState(() => _isLoadingChapter = true);
    try {
      // 1) 切换书籍来源并落库
      widget.book.origin = source.bookSourceUrl;
      widget.book.originName = source.bookSourceName;
      await _db.updateBook(widget.book);

      // 2) 用新书源拉取目录（目录地址沿用书籍的 noteUrl，缺省回退 bookUrl）
      final tocUrl = widget.book.noteUrl ?? widget.book.bookUrl ?? '';
      if (tocUrl.isEmpty) {
        if (mounted) setState(() => _isLoadingChapter = false);
        return '该书缺少书籍地址，无法换源';
      }
      final newChapters =
          await _engine.getToc(source, tocUrl, bookInfo: widget.book.jsContext());
      if (newChapters.isEmpty) {
        if (mounted) setState(() => _isLoadingChapter = false);
        return '新书源未获取到目录，换源失败';
      }

      // 3) 在新源目录中重新定位当前章节：先按标题匹配，失败回退为原下标
      var newIndex = _matchChapterIndex(newChapters, oldTitle);
      if (newIndex < 0) newIndex = oldIndex < newChapters.length ? oldIndex : 0;
      _chapters = newChapters;
      await _db.saveChapters(widget.book.name, widget.book.author, newChapters);
      _currentChapterIndex = newIndex;
    } catch (e) {
      if (mounted) setState(() => _isLoadingChapter = false);
      return '换源失败: $e';
    }

    // 4) 用新源章节 URL 强制走网络拉正文（复用既有后处理：字典/替换/简繁/分页）
    await _loadChapterContent(_currentChapterIndex, forceSource: source);
    final c = _content;
    if (c == null || c.trim().isEmpty || c == '加载失败，请检查网络') {
      return '换源后未获取到正文，请检查新书源';
    }
    return null;
  }

  /// 在新书源目录中按章节标题重新定位当前章节；找不到返回 -1
  int _matchChapterIndex(List<BookChapter> chapters, String title) {
    if (title.trim().isEmpty) return -1;
    final t = title.trim();
    // 1) 标题精确匹配
    var i = chapters.indexWhere((c) => c.title.trim() == t);
    if (i >= 0) return i;
    // 2) 标题互相包含的模糊匹配（跳过卷标，容忍前缀/后缀差异）
    i = chapters.indexWhere((c) {
      final ct = c.title.trim();
      if (ct.isEmpty || c.isVolume) return false;
      return ct.contains(t) || t.contains(ct);
    });
    return i;
  }

  void _paginateContent() {
    if (_content == null || _content!.isEmpty) {
      _pages = ['暂无内容'];
      return;
    }
    final config = context.read<ReadProvider>().config;
    final paragraphs = _content!.split(RegExp(r'\n+')).where((p) => p.trim().isNotEmpty).toList();
    final indent = TextPaginator.indentFor(config.textIndent);
    final w = _pageW;
    final h = _pageH;
    if (w != null && h != null && w > 0 && h > 0) {
      // 真实分页：按实际可用宽高与正文样式逐行测量
      final pages = TextPaginator.paginate(
        paragraphs: paragraphs,
        indent: indent,
        paraGapLines: config.paragraphSpacing < 0 ? 0 : config.paragraphSpacing,
        maxWidth: w,
        maxHeight: h,
        style: _textStyle(config),
      );
      _pages = pages;
    } else {
      // 尚未测量到可用区域时的回退：按字数估算
      final indentStr = config.textIndent > 0 ? ' ' * (config.textIndent * 2) : '';
      final paraGap = '\n' * (config.paragraphSpacing + 1);
      final charsPerPage = (config.textSize <= 14 ? 1000 : config.textSize <= 18 ? 800 : 600);
      final pages = <String>[];
      StringBuffer currentPage = StringBuffer();
      int charCount = 0;
      for (var i = 0; i < paragraphs.length; i++) {
        final para = '$indentStr${paragraphs[i].trim()}';
        final gap = i < paragraphs.length - 1 ? paraGap : '\n';
        if (charCount + para.length > charsPerPage && currentPage.isNotEmpty) {
          pages.add(currentPage.toString().trimRight());
          currentPage = StringBuffer();
          charCount = 0;
        }
        currentPage.write(para);
        currentPage.write(gap);
        charCount += para.length + gap.length;
      }
      if (currentPage.isNotEmpty) pages.add(currentPage.toString().trimRight());
      _pages = pages.isEmpty ? [_content!] : pages;
    }
    if (_pageDiag) {
      final total = _pages.length;
      final chars = _pages.fold<int>(0, (s, p) => s + p.length);
      final per = total == 0 ? 0 : chars ~/ total;
      final mode = (w != null && h != null && w > 0 && h > 0) ? '真实测量' : '字数估算';
      debugPrint('[分页诊断] 《${widget.book.name}》页=$total 总字数=$chars '
          '均字/页=$per 视口=${_pageW?.toStringAsFixed(1)}x${_pageH?.toStringAsFixed(1)} '
          '字号=${config.textSize} 行距=${config.lineSpacing} 段距=${config.paragraphSpacing} 模式=$mode');
    }
    // 修复：PageView跳转到当前页（可能是恢复的页码）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients) {
        _pageController.jumpToPage(_currentPage.clamp(0, _pages.length - 1));
      }
    });
  }

  void _toggleMenu() {
    if (_menuController.isDismissed) {
      _menuController.forward();
    } else {
      _menuController.reverse();
    }
  }

  void _nextPage() {
    final config = context.read<ReadProvider>().config;
    final noAnim = config.pageAnim == 4;
    if (_currentPage < _pages.length - 1) {
      final next = _currentPage + 1;
      if (noAnim) {
        _pageController.jumpToPage(next);
      } else {
        _pageController.animateToPage(next, duration: const Duration(milliseconds: 200), curve: Curves.easeInOut);
      }
      setState(() => _currentPage = next);
      _saveCurrentProgress();
    } else if (_currentChapterIndex < _chapters.length - 1) {
      _loadChapterContent(_currentChapterIndex + 1);
    }
  }

  void _prevPage() {
    final config = context.read<ReadProvider>().config;
    final noAnim = config.pageAnim == 4;
    if (_currentPage > 0) {
      final prev = _currentPage - 1;
      if (noAnim) {
        _pageController.jumpToPage(prev);
      } else {
        _pageController.animateToPage(prev, duration: const Duration(milliseconds: 200), curve: Curves.easeInOut);
      }
      setState(() => _currentPage = prev);
      _saveCurrentProgress();
    } else if (_currentChapterIndex > 0) {
      _loadChapterContent(_currentChapterIndex - 1);
    }
  }

  Future<void> _saveCurrentProgress() async {
    try {
      final provider = context.read<BookProvider>();
      await provider.saveReadingProgress(widget.book, _currentChapterIndex, _currentPage);
    } catch (_) {}
  }

  void _nextChapter() {
    if (_currentChapterIndex < _chapters.length - 1) _loadChapterContent(_currentChapterIndex + 1);
  }

  void _prevChapter() {
    if (_currentChapterIndex > 0) _loadChapterContent(_currentChapterIndex - 1);
  }

  void _startAutoRead() {
    final cfg = context.read<ReadProvider>().config;
    final secs = cfg.autoNextPageSpeed < 1 ? 3 : cfg.autoNextPageSpeed;
    _autoReadTimer?.cancel();
    _autoReadTimer = Timer.periodic(Duration(seconds: secs), (_) {
      if (!mounted) { _autoReadTimer?.cancel(); return; }
      // 读到最后一章最后一页则停止
      if (_currentChapterIndex >= _chapters.length - 1 && _currentPage >= _pages.length - 1) {
        _stopAutoRead();
      } else {
        _nextPage();
      }
    });
    setState(() => _autoReadOn = true);
  }

  void _stopAutoRead() {
    _autoReadTimer?.cancel();
    _autoReadTimer = null;
    if (mounted) setState(() => _autoReadOn = false);
  }

  void _toggleAutoRead() {
    if (_autoReadOn) { _stopAutoRead(); }
    else { _startAutoRead(); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('自动阅读已开启，再次点击菜单可关闭'), duration: Duration(seconds: 1))); }
  }

  Future<void> _addMarking(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    final marking = BookMarking(
      bookName: widget.book.name,
      author: widget.book.author,
      chapterIndex: _currentChapterIndex,
      chapterTitle: _chapters.isNotEmpty ? _chapters[_currentChapterIndex].title : '',
      pagePos: _currentPage,
      content: t,
      createTime: DateTime.now().millisecondsSinceEpoch,
    );
    await _db.insertBookMarking(marking);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已添加划线，可在 我的-书籍标记 查看'), duration: Duration(seconds: 2)));
  }

  /// 划词查词：弹出应用内词典面板（列出启用的词典规则，内嵌 WebView 展示结果），
  /// 不再跳出到外部浏览器。规则数据源与「设置 → 词典规则」共用数据库。
  Future<void> _dictLookup(String word) async {
    final w = word.trim();
    if (w.isEmpty) return;
    final rules = await _db.getDictRules();
    final usable = rules.where((r) => r.enabled == 1 && r.url.contains('{word}')).toList();
    if (!mounted) return;
    if (usable.isEmpty) {
      // 没有可用规则时给一次引导，避免用户以为点了没反应
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('还没有词典规则，可在 我的-词典规则 添加'),
        duration: Duration(seconds: 2),
      ));
    }
    await DictLookupSheet.open(context, w);
  }

  @override
  Widget build(BuildContext context) {
    final readProvider = context.watch<ReadProvider>();
    final config = readProvider.config;
    // 屏幕常亮设置变化时实时生效
    if (_wakeEnabled != config.keepScreenOn) {
      _applyWakeLock(config.keepScreenOn);
    }

    // 对齐 E pref_config_read.disableReturnKey：开启时由 PopScope 拦截系统返回键
    return PopScope(
      canPop: !config.disableReturnKey,
      child: Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (!config.volumeKeyPage) return KeyEventResult.ignored;
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.physicalKey == PhysicalKeyboardKey.audioVolumeUp) {
          config.volumeKeyReverse ? _nextPage() : _prevPage();
          return KeyEventResult.handled;
        }
        if (event.physicalKey == PhysicalKeyboardKey.audioVolumeDown) {
          config.volumeKeyReverse ? _prevPage() : _nextPage();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Color(config.bgColor),
          statusBarIconBrightness: ThemeData.estimateBrightnessForColor(Color(config.bgColor)) == Brightness.dark
              ? Brightness.light
              : Brightness.dark,
        ),
        child: Scaffold(
          backgroundColor: Color(config.bgColor),
          body: _isLoading
              ? Center(child: CircularProgressIndicator(color: Color(config.textColor)))
              : GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (details) {
                    final size = MediaQuery.of(context).size;
                    final col = details.globalPosition.dx < size.width / 3 ? 0 : (details.globalPosition.dx > size.width * 2 / 3 ? 2 : 1);
                    final row = details.globalPosition.dy < size.height / 3 ? 0 : (details.globalPosition.dy > size.height * 2 / 3 ? 2 : 1);
                    final action = _clickActions[row * 3 + col];
                    // 点击中央显示菜单开关关闭时，中央区域不响应菜单动作
                    if (action == 3 && !config.showMenuOnTap) return;
                    // 点击翻页开关关闭时，点击不翻页（仅菜单动作生效）
                    final canTurn = config.clickTurnPage;
                    switch (action) {
                      case 1: if (canTurn) _prevChapter(); break;
                      case 2: if (canTurn) _nextChapter(); break;
                      case 3: _toggleMenu(); break;
                      case 4: if (canTurn) _prevPage(); break;
                      case 5: if (canTurn) _nextPage(); break;
                      case 6: _showChapterList(); break; // 目录
                      case 7: _showSearchInBook(); break; // 全文搜索
                      case 8: _startTTS(); break; // 朗读
                      case 9: _addBookmark(); break; // 添加书签
                      case 10: _showContentEditor(); break; // 编辑正文
                      case 11: _showBookmarks(); break; // 书签列表
                      case 12: _saveCurrentProgress(); break; // 同步进度
                      case 13: _toggleTtsPause(); break; // 朗读暂停/恢复
                      case 14: _togglePurify(); break; // 切换净化
                      default: break;
                    }
                  },
                  child: Stack(
                    children: [
                      if (config.bgImage != null)
                        Positioned.fill(child: Image.file(File(config.bgImage!), fit: BoxFit.cover)),
                      Column(
                        children: [
                          if (config.statusBarVisibility)
                            SizedBox(height: MediaQuery.of(context).padding.top),
                          if (config.titleVisibility)
                            _buildHeader(config),
                          Expanded(
                            child: _isLoadingChapter
                                ? Center(child: CircularProgressIndicator(color: Color(config.textColor)))
                                : RotatedBox(
                                    quarterTurns: config.verticalLayout,
                                    child: Transform(
                                      alignment: Alignment.center,
                                      transform: config.invertPage ? (Matrix4.identity()..rotateZ(3.1415926535897932)) : Matrix4.identity(),
                                      child: _buildReadingContent(config),
                                    ),
                                  ),
                          ),
                          // 章节内阅读进度条（showProgress）
                          if (config.showProgress && _pages.length > 1)
                            LinearProgressIndicator(
                              value: (_currentPage + 1) / _pages.length,
                              minHeight: 2,
                              backgroundColor: Colors.transparent,
                              valueColor: AlwaysStoppedAnimation<Color>(Color(config.textColor).withOpacity(0.25)),
                            ),
                          if (config.pageNumberVisibility || config.timeVisibility || config.batteryVisibility)
                            _buildFooter(config),
                          SizedBox(height: MediaQuery.of(context).padding.bottom),
                        ],
                      ),
                      _buildTopMenu(),
                      _buildBottomMenu(),
                      // 护眼模式：暖黄色遮罩（不拦截点击）
                      if (config.eyeProtection)
                        IgnorePointer(
                          child: Positioned.fill(
                            child: Container(
                              color: const Color(0xFFFFF1D6).withOpacity((config.eyeProtectionLevel.clamp(0, 100) / 100) * 0.35),
                            ),
                          ),
                        ),
                      // 亮度调节：黑色半透明遮罩模拟屏幕变暗（不拦截点击）
                      if (readProvider.brightness < 1.0)
                        IgnorePointer(
                          child: Positioned.fill(
                            child: Container(
                              color: Colors.black.withOpacity((1 - readProvider.brightness) * 0.6),
                            ),
                          ),
                        ),
                      // 对齐 E view_read_menu.xml ll_floating_button：水平悬浮按钮行已并入底部设置面板；
                      // E 没有 Klys 的右侧竖排悬浮栏，故此处不再放置。
                    ],
                  ),
                ),
        ),
      ),
      ),
    );
  }

  Widget _buildHeader(ReadConfig config) {
    // 自定义页眉文本优先（customHeaderEnabled 且 headerString 非空）
    final customText = config.customHeaderEnabled ? (config.headerString ?? '') : '';
    final title = customText.isNotEmpty
        ? customText
        : (_chapters.isNotEmpty ? _chapters[_currentChapterIndex].title : widget.book.name);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: config.paddingLeft.toDouble(),
        vertical: 4,
      ),
      height: config.headerHeight.toDouble(),
      alignment: config.headerAlignCenter ? Alignment.center : Alignment.centerLeft,
      child: Text(
        title,
        style: TextStyle(
          fontSize: config.headerSize.toDouble(),
          color: Color(config.headerColor),
          fontWeight: config.headerBold ? FontWeight.bold : FontWeight.normal,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _pageText(ReadConfig config, int index) => _styledText(config, index < _pages.length ? _pages[index] : '');

  /// 正文样式（分页测量与渲染共用，保证两者一致）
  TextStyle _textStyle(ReadConfig config) {
    return TextStyle(
      fontSize: config.textSize.toDouble(),
      color: Color(config.textColor),
      height: config.lineSpacing * 0.5 + 1.0,
      letterSpacing: config.letterSpacing,
      wordSpacing: config.wordSpacing,
      // 对齐 E TextFontWeightConverter：字重设置真实作用于正文（粗体开关优先）
      fontWeight: config.boldText
          ? FontWeight.bold
          : FontWeight.values[((config.fontWeight ~/ 100) - 1).clamp(0, FontWeight.values.length - 1)],
      fontFamily: config.fontFamily,
      shadows: config.shadowLevel > 0
          ? [
              Shadow(
                color: Colors.black.withOpacity(0.06 * config.shadowLevel),
                blurRadius: config.shadowLevel * 1.5,
                offset: Offset(0, config.shadowLevel * 0.8),
              )
            ]
          : null,
      decoration: switch (config.underlineType) {
        1 => TextDecoration.underline,
        2 => TextDecoration.underline,
        3 => TextDecoration.underline,
        4 => TextDecoration.underline,
        _ => null,
      },
      decorationStyle: config.underlineType == 2
          ? TextDecorationStyle.dashed
          : config.underlineType == 3
              ? TextDecorationStyle.wavy
              : config.underlineType == 4
                  ? TextDecorationStyle.double
                  : null,
      fontFeatures: _antiAlias ? null : const [FontFeature.disable('kern'), FontFeature.disable('liga')],
    );
  }

  /// 渲染任意文本（滚动模式用于整章显示）
  Widget _styledText(ReadConfig config, String text) {
    final style = _textStyle(config);
    final align = config.textAlign == 1
        ? TextAlign.center
        : config.textAlign == 2
            ? TextAlign.justify
            : TextAlign.left;
    // 命中高亮标签规则时用 Text.rich 上色，否则退回普通 Text
    final spans = HighlightService.spansFor(text, style);
    if (spans != null) {
      return Text.rich(TextSpan(children: spans), textAlign: align);
    }
    return Text(text, style: style, textAlign: align);
  }

  Widget _buildReadingContent(ReadConfig config) {
    // 翻页动画：0覆盖 1仿真 2滑动 3滚动 4无动画 5上下
    final isVertical = config.pageAnim == 5;
    final noAnim = config.pageAnim == 4;
    final scrollMode = config.pageAnim == 3;

    // 用 LayoutBuilder 测量可用文本区域，尺寸变化时重新真实分页
    return LayoutBuilder(builder: (ctx, constraints) {
      final availW = constraints.maxWidth - config.paddingLeft - config.paddingRight;
      final availH = constraints.maxHeight - config.paddingTop - config.paddingBottom;
      _maybeRepaginate(availW, availH);
      return scrollMode
          ? _buildScrollMode(config, isVertical)
          : _buildPageView(config, isVertical, noAnim);
    });
  }

  /// 可用区域变化时重新分页（保持当前阅读锚点）
  void _maybeRepaginate(double w, double h) {
    if (w <= 0 || h <= 0) return;
    final pw = _pageW;
    final ph = _pageH;
    if (pw != null && ph != null && (pw - w).abs() < 0.5 && (ph - h).abs() < 0.5) return;
    _pageW = w;
    _pageH = h;
    // 重排防抖：连续布局变化只做最后一次，避免逐帧/逐次全文测量
    _scheduleRepaginate();
  }

  /// 防抖重排：取消待执行的重排，100ms 静默后执行（dispose 时 cancel）
  void _scheduleRepaginate() {
    _repaginateTimer?.cancel();
    _repaginateTimer = Timer(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      _paginateContent();
      if (mounted) setState(() {});
    });
  }

  Widget _buildScrollMode(ReadConfig config, bool isVertical) {
    final chapterText = _content ?? '加载中...';
    final child = _styledText(config, chapterText);
    return SingleChildScrollView(
      scrollDirection: isVertical ? Axis.horizontal : Axis.vertical,
      padding: EdgeInsets.fromLTRB(
        config.paddingLeft.toDouble(),
        config.paddingTop.toDouble(),
        config.paddingRight.toDouble(),
        config.paddingBottom.toDouble(),
      ),
      child: (_textSelectable && config.longPressSelect)
          ? SelectionArea(
              contextMenuBuilder: (context, state) {
                Future<String> grab() async {
                  state.copySelection(SelectionChangedCause.toolbar);
                  await Future.delayed(const Duration(milliseconds: 30));
                  final d = await Clipboard.getData(Clipboard.kTextPlain);
                  return d?.text ?? '';
                }
                return AdaptiveTextSelectionToolbar(
                  anchors: state.contextMenuAnchors,
                  children: _buildSelectMenuChildren(state, grab),
                );
              },
              child: child,
            )
          : child,
    );
  }

  Widget _buildPageView(ReadConfig config, bool isVertical, bool noAnim) {
    final cover = config.pageAnim == 0; // 覆盖
    final simulate = config.pageAnim == 1; // 仿真
    // 无动画翻页或用户禁用了水平滑动时，禁掉手势翻页（代码跳页仍然可用）
    final lockGesture = noAnim || (_disableHorizontalSwipe && !isVertical);
    final physics =
        lockGesture ? const NeverScrollableScrollPhysics() : const PageScrollPhysics();
    // MediaQuery 在动画外只取一次，翻页每帧不再重复读取
    final mq = MediaQuery.of(context);
    final advance = isVertical ? mq.size.height : mq.size.width;
    // 静态 PageView：不再整体包进 AnimatedBuilder，每帧不重建整棵页面树
    return PageView.builder(
      controller: _pageController,
      scrollDirection: isVertical ? Axis.vertical : Axis.horizontal,
      physics: physics,
      itemCount: _pages.length,
      onPageChanged: (page) => setState(() => _currentPage = page),
      itemBuilder: (context, index) {
        final item = _pageItem(config, index);
        // 覆盖 / 仿真：动画层只包住当前页项，静态页内容作为 child 不参与每帧重建
        if (!cover && !simulate) return item;
        return _PageAnimLayer(
          controller: _pageController,
          fallbackPage: _currentPage,
          index: index,
          advance: advance,
          vertical: isVertical,
          simulate: simulate,
          child: item,
        );
      },
    );
  }

  /// 单页内容（含长按选择）；最外层 RepaintBoundary 隔离翻页时的逐页重绘
  Widget _pageItem(ReadConfig config, int index) {
    final child = _pageText(config, index);
    return RepaintBoundary(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          config.paddingLeft.toDouble(),
          config.paddingTop.toDouble(),
          config.paddingRight.toDouble(),
          config.paddingBottom.toDouble(),
        ),
        child: (_textSelectable && config.longPressSelect)
            ? SelectionArea(
                contextMenuBuilder: (context, state) {
                  Future<String> grab() async {
                    state.copySelection(SelectionChangedCause.toolbar);
                    await Future.delayed(const Duration(milliseconds: 30));
                    final d = await Clipboard.getData(Clipboard.kTextPlain);
                    return d?.text ?? '';
                  }
                  return AdaptiveTextSelectionToolbar(
                    anchors: state.contextMenuAnchors,
                    children: _buildSelectMenuChildren(state, grab),
                  );
                },
                child: child,
              )
            : child,
      ),
    );
  }

  Widget _buildFooter(ReadConfig config) {
    // 自定义页脚文本优先（customFooterEnabled 且 footerString 非空）
    final customText = config.customFooterEnabled ? (config.footerString ?? '') : '';
    if (customText.isNotEmpty) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: config.paddingLeft.toDouble(), vertical: 4),
        height: config.footerHeight.toDouble(),
        alignment: config.footerAlignCenter ? Alignment.center : Alignment.centerLeft,
        child: Text(
          customText,
          style: TextStyle(
            fontSize: config.footerSize.toDouble(),
            color: Color(config.footerColor),
            fontWeight: config.footerBold ? FontWeight.bold : FontWeight.normal,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    final slots = config.footerSlots;
    if (slots != null && slots.length == 3) {
      // 三槽位页脚：左 / 中 / 右，每槽内容由 FooterSlot 枚举配置
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: config.paddingLeft.toDouble(),
          vertical: 4,
        ),
        height: config.footerHeight.toDouble(),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(3, (i) {
            // 左槽左对齐、中槽居中、右槽右对齐
            final alignment = i == 0
                ? Alignment.centerLeft
                : i == 1
                    ? Alignment.center
                    : Alignment.centerRight;
            return Flexible(
              child: Align(alignment: alignment, child: _footerSlotWidget(i, config)),
            );
          }),
        ),
      );
    }
    // 回退：旧版单行页脚（时间 / 页码 / 电量图标）
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: config.paddingLeft.toDouble(),
        vertical: 4,
      ),
      height: config.footerHeight.toDouble(),
      child: Row(
        mainAxisAlignment: config.footerAlignCenter ? MainAxisAlignment.center : MainAxisAlignment.spaceBetween,
        children: [
          if (config.timeVisibility && config.showTimeBattery)
            Text(
              _currentTime,
              style: TextStyle(
                fontSize: config.footerSize.toDouble(),
                color: Color(config.footerColor),
                fontWeight: config.footerBold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          if (config.pageNumberVisibility && _pages.length > 1)
            Text(
              '${_currentPage + 1}/${_pages.length}',
              style: TextStyle(
                fontSize: config.footerSize.toDouble(),
                color: Color(config.footerColor),
                fontWeight: config.footerBold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          if (config.batteryVisibility && config.showTimeBattery)
            Icon(Icons.battery_full, size: 14, color: Color(config.footerColor)),
        ],
      ),
    );
  }

  /// 全书阅读进度百分比：「当前章 + 章内当前页/本章页数」/ 全书章节数
  double get _bookProgress {
    if (_chapters.isEmpty) return 0;
    final pagesInChapter = _pages.isNotEmpty ? _pages.length : 1;
    final withinChapter = (_currentPage + 1) / pagesInChapter;
    final progress = (_currentChapterIndex + withinChapter) / _chapters.length * 100;
    return progress.clamp(0.0, 100.0);
  }

  /// 页脚第 slotIndex 个槽位（0左 1中 2右）的文本内容
  /// 电量类槽位无真实读数时返回空串，由 _footerSlotWidget 降级渲染图标
  String _footerSlotText(int slotIndex, ReadConfig config) {
    final slots = config.footerSlots;
    if (slots == null || slotIndex < 0 || slotIndex >= slots.length) return '';
    switch (slots[slotIndex]) {
      case FooterSlot.chapterTitle:
        return _chapters.isNotEmpty ? _chapters[_currentChapterIndex].title : '';
      case FooterSlot.bookName:
        return widget.book.name;
      case FooterSlot.pageNumber:
        // 章内仅一页时不显示页码（与旧版行为一致）
        return _pages.length > 1 ? '${_currentPage + 1}' : '';
      case FooterSlot.totalPages:
        return '${_pages.length}';
      case FooterSlot.progress:
        return '${_bookProgress.toStringAsFixed(1)}%';
      case FooterSlot.time:
        return _currentTime;
      case FooterSlot.batteryPercent:
        // 无真实电量读数时返回空串，由 _footerSlotWidget 渲染图标
        return _batteryLevel != null ? '$_batteryLevel%' : '';
      case FooterSlot.battery:
      case FooterSlot.none:
        return '';
    }
  }

  /// 页脚槽位控件：文本槽位用 Text；电量槽位在无真实读数时降级为图标
  Widget _footerSlotWidget(int slotIndex, ReadConfig config) {
    final slots = config.footerSlots;
    final slot = (slots != null && slotIndex < slots.length) ? slots[slotIndex] : FooterSlot.none;
    // 电量图标槽位：无 battery 插件（离线环境禁新增依赖），保留静态图标
    if (slot == FooterSlot.battery || (slot == FooterSlot.batteryPercent && _batteryLevel == null)) {
      return Icon(_batteryIcon(_batteryLevel), size: 14, color: Color(config.footerColor));
    }
    return Text(
      _footerSlotText(slotIndex, config),
      style: TextStyle(
        fontSize: config.footerSize.toDouble(),
        color: Color(config.footerColor),
        fontWeight: config.footerBold ? FontWeight.bold : FontWeight.normal,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// 电量图标：有读数时按电量分段选择，无读数时用满电量图标占位
  IconData _batteryIcon(int? level) {
    if (level == null) return Icons.battery_full;
    if (level <= 15) return Icons.battery_alert;
    if (level <= 60) return Icons.battery_std;
    return Icons.battery_full;
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildTopMenu() {
    final config = context.read<ReadProvider>().config;
    // 对齐 E ReadMenu.immersiveMenu：阅读栏背景/文字跟随当前页面背景
    final barBg = config.readBarStyleFollowPage ? Color(config.bgColor) : null;
    final barFg = config.readBarStyleFollowPage ? Color(config.textColor) : null;
    return AnimatedBuilder(
      animation: _menuController,
      builder: (context, child) {
        return Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Transform.translate(
            offset: Offset(0, -(1 - _menuController.value) * 120),
            child: Opacity(
              opacity: _menuController.value,
              child: child,
            ),
          ),
        );
      },
      child: AppBar(
        backgroundColor: barBg,
        foregroundColor: barFg,
        title: GestureDetector(
          // 对齐 E ReadMenu：点击标题栏打开书籍详情
          onTap: () {
            _menuController.reverse();
            Navigator.push(context, MaterialPageRoute(builder: (_) => BookDetailScreen(book: widget.book)));
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.book.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              // 对齐 E showReadTitleBarAddition：标题附加区显示章节名 / 书源
              if (config.showReadTitleAddition)
                Text(
                  _chapters.isNotEmpty
                      ? _chapters[_currentChapterIndex].title
                      : (widget.book.originName ?? ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: barFg?.withOpacity(0.75)),
                ),
            ],
          ),
        ),
        // 对齐 E res/menu/book_read.xml：showAsAction="always" 的工具栏项与本地书附加项
        actions: [
          IconButton(tooltip: '换源', icon: const Icon(Icons.swap_horiz), onPressed: _showChangeSourceMenu),
          IconButton(tooltip: '刷新', icon: const Icon(Icons.refresh), onPressed: _refreshCurrentChapter),
          IconButton(tooltip: '离线缓存', icon: const Icon(Icons.download), onPressed: _showCacheSheet),
          // 本地书：TXT目录规则 / 设置编码（对齐 E menu_group_text / menu_group_local）
          if (widget.book.local) ...[
            IconButton(tooltip: 'TXT目录规则', icon: const Icon(Icons.list_alt),
              onPressed: () { _menuController.reverse(); Navigator.push(context, MaterialPageRoute(builder: (_) => const TxtTocRuleScreen())); }),
            IconButton(tooltip: '设置编码', icon: const Icon(Icons.translate), onPressed: _selectCharset),
          ],
          // 对齐 E ReadMenu.tvSourceAction：网络书的书源操作菜单
          if (!widget.book.local)
            TextButton(onPressed: _showSourceMenu, child: Text('书源', style: TextStyle(color: barFg))),
          // 更多菜单（对齐 E overflow showAsAction="never"）
          IconButton(icon: const Icon(Icons.more_vert), onPressed: _showMoreMenu),
        ],
      ),
    );
  }

  Widget _buildBottomMenu() {
    return AnimatedBuilder(
      animation: _menuController,
      builder: (context, child) {
        return Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Transform.translate(
            offset: Offset(0, (1 - _menuController.value) * 500),
            child: Opacity(
              opacity: _menuController.value,
              child: IgnorePointer(
                ignoring: _menuController.value < 0.5,
                child: child,
              ),
            ),
          ),
        );
      },
      child: _buildReadingSettingsPanel(),
    );
  }

  Widget _buildReadingSettingsPanel() {
    final readProvider = context.read<ReadProvider>();
    final config = readProvider.config;
    // 对齐 E ReadMenu.immersiveMenu：底部设置栏背景/文字跟随页面背景
    final barBg = config.readBarStyleFollowPage
        ? Color(config.bgColor)
        : Theme.of(context).colorScheme.surface;
    final barFg = config.readBarStyleFollowPage
        ? Color(config.textColor)
        : Theme.of(context).colorScheme.onSurface;
    return Container(
      decoration: BoxDecoration(
        color: barBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 对齐 E view_read_menu.xml ll_floating_button：水平悬浮按钮行（搜索/自动翻页/替换/夜间）
            _buildFloatingButtonRow(barFg),
            // 章节进度行（对齐 E tv_pre / seek_read_page / tv_next）
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.skip_previous, color: barFg),
                    onPressed: _currentChapterIndex > 0 ? () => _loadChapterContent(_currentChapterIndex - 1) : null,
                  ),
                  Expanded(
                    child: Slider(
                      activeColor: barFg,
                      value: _chapters.length <= 1 ? 0 : (_dragChapterIndex ?? _currentChapterIndex) / (_chapters.length - 1),
                      // 拖动中只更新局部状态，不触发章节加载/落库/重排
                      onChanged: _chapters.length <= 1
                          ? null
                          : (value) {
                              final index = (value * (_chapters.length - 1)).round();
                              if (index != (_dragChapterIndex ?? _currentChapterIndex)) {
                                setState(() => _dragChapterIndex = index);
                              }
                            },
                      // 松手才加载章节（加载内部完成进度保存与重排）
                      onChangeEnd: _chapters.length <= 1
                          ? null
                          : (value) {
                              final index = (value * (_chapters.length - 1)).round();
                              setState(() => _dragChapterIndex = index);
                              _loadChapterContent(index).whenComplete(() {
                                if (mounted) setState(() => _dragChapterIndex = null);
                              });
                            },
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.skip_next, color: barFg),
                    onPressed: _currentChapterIndex < _chapters.length - 1
                        ? () => _loadChapterContent(_currentChapterIndex + 1)
                        : null,
                  ),
                ],
              ),
            ),
            // 字号 / 行距（对齐 E「界面」ReadStyleDialog 的字号调节，常驻便于快捷调整）
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text('字号', style: TextStyle(color: barFg)),
                  IconButton(icon: Icon(Icons.remove_circle_outline, color: barFg), onPressed: () => readProvider.setTextSize(config.textSize - 1)),
                  Text('${config.textSize}', style: TextStyle(color: barFg)),
                  IconButton(icon: Icon(Icons.add_circle_outline, color: barFg), onPressed: () => readProvider.setTextSize(config.textSize + 1)),
                  const Spacer(),
                  Text('行距', style: TextStyle(color: barFg)),
                  IconButton(icon: Icon(Icons.remove_circle_outline, color: barFg), onPressed: () => readProvider.setLineSpacing(config.lineSpacing - 1)),
                  Text('${config.lineSpacing}', style: TextStyle(color: barFg)),
                  IconButton(icon: Icon(Icons.add_circle_outline, color: barFg), onPressed: () => readProvider.setLineSpacing(config.lineSpacing + 1)),
                ],
              ),
            ),
            // 配色预设（对齐 E ReadStyleDialog 的背景选择；不使用「背景」文字标题）
            SizedBox(
              height: 60,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: ReadConfig.presets.length,
                itemBuilder: (context, index) {
                  final preset = ReadConfig.presets[index];
                  final bg = preset['bgColor'] as int;
                  final fg = preset['textColor'] as int;
                  final isSelected = config.bgColor == bg;
                  return GestureDetector(
                    onTap: () {
                      readProvider.setBgColor(bg);
                      readProvider.setTextColor(fg);
                    },
                    child: Container(
                      width: 56,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        color: Color(bg),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected ? Theme.of(context).colorScheme.primary : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: Text(preset['name'] as String, style: TextStyle(color: Color(fg), fontSize: 12)),
                      ),
                    ),
                  );
                },
              ),
            ),
            // 对齐 E view_read_menu.xml ll_bottom_bg 的四个按钮：目录 / 朗读 / 界面 / 设置
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildBottomAction(Icons.list_alt, '目录', barFg, _showChapterList),
                  _buildReadAloudAction(barFg),
                  _buildBottomAction(Icons.text_format, '界面', barFg, _showInterfaceSettings),
                  _buildBottomAction(Icons.settings, '设置', barFg, _showReadingSettings),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 对齐 E view_read_menu.xml ll_floating_button：搜索 / 自动翻页 / 替换 / 夜间 水平行
  Widget _buildFloatingButtonRow(Color fg) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(tooltip: '搜索', icon: Icon(Icons.search, color: fg), onPressed: _showSearchInBook),
          IconButton(
            tooltip: _autoReadOn ? '停止自动翻页' : '自动翻页',
            icon: Icon(_autoReadOn ? Icons.pause_circle_filled : Icons.play_circle_outline, color: fg),
            onPressed: _toggleAutoRead,
          ),
          IconButton(tooltip: '替换规则', icon: Icon(Icons.find_replace, color: fg), onPressed: _showReplaceRules),
          IconButton(tooltip: '夜间模式', icon: Icon(Icons.brightness_4, color: fg), onPressed: _toggleNightTheme),
        ],
      ),
    );
  }

  /// 对齐 E fabNightTheme：切换日/夜间阅读配色（真实改变正文背景与文字色）
  void _toggleNightTheme() {
    final rp = context.read<ReadProvider>();
    final isNight = rp.config.bgColor == 0xFF1A1A2E;
    if (isNight) {
      rp.setBgColor(0xFFFFF8E1);
      rp.setTextColor(0xFF333333);
    } else {
      rp.setBgColor(0xFF1A1A2E);
      rp.setTextColor(0xFFE0E0E0);
    }
  }

  /// 对齐 E llReadAloud：点击朗读、长按弹出朗读配置
  Widget _buildReadAloudAction(Color fg) {
    return GestureDetector(
      onLongPress: _showReadAloudConfig,
      child: _buildBottomAction(Icons.headphones, '朗读', fg, _startTTS),
    );
  }

  // 对齐 E：删除 Klys 的右侧竖排悬浮栏与可配置工具栏/悬浮栏映射。
  // E 的浮动按钮为底部栏上方的水平行（_buildFloatingButtonRow），底部按钮固定为四项。

  /// 对齐 E menu_change_source：换源（章节换源）
  Future<void> _showChangeSourceMenu() async {
    _menuController.reverse();
    final source = await showModalBottomSheet<BookSource>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ChangeChapterSourceSheet(
        bookName: widget.book.name, author: widget.book.author, currentOrigin: widget.book.origin),
    );
    if (source == null) return;
    final err = await _changeChapterSource(source);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(err ?? '已换源：${source.bookSourceName}'),
      duration: const Duration(seconds: 2),
    ));
  }

  /// 对齐 E menu_refresh：清当前章缓存并强制从网络重新加载正文
  Future<void> _refreshCurrentChapter() async {
    _menuController.reverse();
    if (_chapters.isEmpty) return;
    await _db.updateChapterContent(widget.book.name, widget.book.author, _currentChapterIndex, '');
    await _loadChapterContent(_currentChapterIndex, targetPage: _currentPage);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已刷新当前章节')));
  }

  /// 对齐 E menu_download：离线缓存（选择章节范围）
  Future<void> _showCacheSheet() async {
    _menuController.reverse();
    final range = await showModalBottomSheet<List<int>>(
      context: context,
      builder: (_) => DownloadSheet(chapters: _chapters, currentIndex: _currentChapterIndex),
    );
    if (range != null) _cacheChapters(range[0], range[1]);
  }

  /// 对齐 E llFont（showReadStyle）：界面设置（字体 / 翻页动画 / 亮度 / 简繁）
  void _showInterfaceSettings() {
    _menuController.reverse();
    showModalBottomSheet(context: context, builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: const Icon(Icons.font_download), title: const Text('字体'), onTap: () { Navigator.pop(ctx); _showFontPicker(); }),
      ListTile(leading: const Icon(Icons.animation), title: const Text('翻页动画'), onTap: () { Navigator.pop(ctx); _showPageAnimPicker(); }),
      ListTile(leading: const Icon(Icons.brightness_6), title: const Text('亮度'), onTap: () { Navigator.pop(ctx); _showBrightnessSlider(); }),
      ListTile(leading: const Icon(Icons.translate), title: const Text('简繁转换'), onTap: () { Navigator.pop(ctx); _showChineseConverter(); }),
    ])));
  }

  /// 对齐 E llReadAloud 长按（showReadAloudDialog）：朗读配置
  void _showReadAloudConfig() {
    _menuController.reverse();
    showModalBottomSheet(context: context, builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: const Icon(Icons.headphones), title: const Text('开始朗读'), onTap: () { Navigator.pop(ctx); _startTTS(); }),
      ListTile(leading: const Icon(Icons.pause_circle_outline), title: const Text('暂停 / 继续'), onTap: () { Navigator.pop(ctx); _toggleTtsPause(); }),
      ListTile(leading: const Icon(Icons.play_circle_outline), title: const Text('自动翻页'), onTap: () { Navigator.pop(ctx); _toggleAutoRead(); }),
    ])));
  }

  /// 切换对齐 E 的内容开关：持久化并重新加载当前章使其生效
  void _flipContentToggle(String prefKey, void Function(bool) assign, bool current) {
    final next = !current;
    assign(next);
    setState(() {});
    SharedPreferences.getInstance().then((p) => p.setBool(prefKey, next));
    _loadChapterContent(_currentChapterIndex, targetPage: _currentPage);
  }

  /// 对齐 E menu_image_style：图片样式（消费 clickImgWay 死开关）
  void _showImageStylePicker() {
    final rp = context.read<ReadProvider>();
    const names = ['无', '预览', '浏览器'];
    showModalBottomSheet(context: context, builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Padding(padding: EdgeInsets.all(16), child: Text('图片样式', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
      for (var i = 0; i < names.length; i++)
        RadioListTile<int>(title: Text(names[i]), value: i, groupValue: rp.config.clickImgWay,
          onChanged: (v) { rp.updateConfig((c) => c.clickImgWay = v ?? 0); Navigator.pop(ctx); }),
    ])));
  }

  /// 对齐 E menu_help：阅读菜单帮助（点击区域与菜单入口说明）
  void _showHelp() {
    showDialog(context: context, builder: (c) => AlertDialog(
      title: const Text('阅读帮助'),
      content: const SingleChildScrollView(child: Text(
        '· 点击正文中央：唤出/收起菜单\n'
        '· 点击左右区域：上/下一章（可在「设置-翻页-点击区域设置」调整）\n'
        '· 顶部栏：换源 / 刷新 / 离线缓存 / 书源 / 更多\n'
        '· 底部栏：目录 / 朗读（长按为朗读配置）/ 界面 / 设置\n'
        '· 更多菜单：书签、内容编辑、翻页动画、内容处理开关、更新目录、生效替换、日志等',
        style: TextStyle(fontSize: 13, height: 1.6),
      )),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('知道了'))],
    ));
  }

  Widget _buildBottomAction(IconData icon, String label, Color fg, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: fg),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 11, color: fg)),
          ],
        ),
      ),
    );
  }

  void _showMoreMenu() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 严格按 E res/menu/book_read.xml 的 overflow 项与顺序展示
                for (final key in _eMoreMenuOrder)
                  if (_moreMenuItem(key, ctx) != null) _moreMenuItem(key, ctx)!,
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 更多菜单项（对齐 E book_read.xml 的 showAsAction="never" 项）
  Widget? _moreMenuItem(String key, BuildContext ctx) {
    void close() => Navigator.pop(ctx);
    // checkable 项：右侧勾选框表示当前开关状态（对齐 E 的 android:checkable）
    Widget checkable(String title, IconData icon, bool value, VoidCallback onTap) => ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: Icon(value ? Icons.check_box : Icons.check_box_outline_blank),
      onTap: () { close(); onTap(); },
    );
    final cfg = context.read<ReadProvider>().config;
    switch (key) {
      case 'addbookmark':
        return ListTile(leading: const Icon(Icons.bookmark_border), title: const Text('添加书签'), onTap: () { close(); _addBookmark(); });
      case 'contentedit':
        return ListTile(leading: const Icon(Icons.edit_note), title: const Text('编辑内容'), onTap: () { close(); _showContentEditor(); });
      case 'pageanim':
        return ListTile(leading: const Icon(Icons.animation), title: const Text('翻页动画'), onTap: () { close(); _showPageAnimPicker(); });
      case 'reverse':
        return ListTile(leading: const Icon(Icons.swap_vert), title: const Text('内容倒序'), onTap: () { close(); _reverseContent(); });
      case 'simulated':
        return checkable('模拟阅读', Icons.play_circle_outline, cfg.simulatedReading, () {
          final next = !cfg.simulatedReading;
          context.read<ReadProvider>().updateConfig((c) => c.simulatedReading = next);
          if (next && !_autoReadOn) _startAutoRead();
        });
      case 'replace':
        return checkable('启用替换', Icons.find_replace, _purifyEnabled, _togglePurify);
      case 'sametitle':
        return checkable('同名章节去除', Icons.playlist_remove, _removeSameTitle,
          () => _flipContentToggle('read_removeSameTitle', (v) => _removeSameTitle = v, _removeSameTitle));
      case 'resegment':
        return checkable('重新分段', Icons.format_align_left, _reSegmentEnabled,
          () => _flipContentToggle('read_reSegment', (v) => _reSegmentEnabled = v, _reSegmentEnabled));
      case 'delruby':
        return checkable('删除注音标签', Icons.text_fields, _delRubyEnabled,
          () => _flipContentToggle('read_delRuby', (v) => _delRubyEnabled = v, _delRubyEnabled));
      case 'delh':
        return checkable('删除标题标签', Icons.title, _delHEnabled,
          () => _flipContentToggle('read_delH', (v) => _delHEnabled = v, _delHEnabled));
      case 'imagestyle':
        return ListTile(leading: const Icon(Icons.image), title: const Text('图片样式'), onTap: () { close(); _showImageStylePicker(); });
      case 'updatetoc':
        return ListTile(leading: const Icon(Icons.refresh), title: const Text('更新目录'), onTap: () {
          close();
          _fetchTocFromNetwork();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在更新目录')));
        });
      case 'effectivereplace':
        return ListTile(leading: const Icon(Icons.rule), title: const Text('生效替换'), onTap: () { close(); _showReplaceRules(); });
      case 'log':
        return ListTile(leading: const Icon(Icons.receipt_long), title: const Text('日志'), onTap: () { close(); _showDebugLog(); });
      case 'help':
        return ListTile(leading: const Icon(Icons.help_outline), title: const Text('帮助'), onTap: () { close(); _showHelp(); });
      default: return null;
    }
  }

  List<Widget> _buildSelectMenuChildren(dynamic state, Future<String> Function() grab) {
    final children = <Widget>[];
    for (final key in _selectMenuOrder) {
      switch (key) {
        case 'copy':
          children.add(InkWell(onTap: () {
            state.copySelection(SelectionChangedCause.toolbar);
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)));
          }, child: const Padding(padding: EdgeInsets.all(12), child: Text('复制'))));
          break;
        case 'marking':
          children.add(InkWell(onTap: () async {
            final text = await grab();
            if (context.mounted) Navigator.pop(context);
            _addMarking(text);
          }, child: const Padding(padding: EdgeInsets.all(12), child: Text('划线'))));
          break;
        case 'dict':
          children.add(InkWell(onTap: () async {
            final w = await grab();
            if (context.mounted) Navigator.pop(context);
            _dictLookup(w);
          }, child: const Padding(padding: EdgeInsets.all(12), child: Text('查词'))));
          break;
        case 'translate':
          children.add(InkWell(onTap: () async {
            final w = await grab();
            if (context.mounted) Navigator.pop(context);
            _translateSelection(w);
          }, child: const Padding(padding: EdgeInsets.all(12), child: Text('翻译'))));
          break;
        case 'bookmark':
          children.add(InkWell(onTap: () async {
            final w = await grab();
            if (context.mounted) Navigator.pop(context);
            _addBookmark(note: w);
          }, child: const Padding(padding: EdgeInsets.all(12), child: Text('加书签'))));
          break;
        case 'tts':
          children.add(InkWell(onTap: () async {
            final w = await grab();
            if (context.mounted) Navigator.pop(context);
            if (w.trim().isNotEmpty) _speakSelection(w);
          }, child: const Padding(padding: EdgeInsets.all(12), child: Text('朗读'))));
          break;
        case 'search':
          children.add(InkWell(onTap: () async {
            final w = await grab();
            if (context.mounted) Navigator.pop(context);
            _showSearchInBook(initialKeyword: w.trim());
          }, child: const Padding(padding: EdgeInsets.all(12), child: Text('搜索正文'))));
          break;
        case 'browser':
          children.add(InkWell(onTap: () async {
            final w = await grab();
            if (context.mounted) Navigator.pop(context);
            _openInBrowser(w.trim());
          }, child: const Padding(padding: EdgeInsets.all(12), child: Text('浏览器'))));
          break;
        case 'share':
          children.add(InkWell(onTap: () async {
            final w = await grab();
            if (context.mounted) Navigator.pop(context);
            _shareSelection(w);
          }, child: const Padding(padding: EdgeInsets.all(12), child: Text('分享'))));
          break;
        case 'replace':
          children.add(InkWell(onTap: () async {
            final w = await grab();
            if (context.mounted) Navigator.pop(context);
            _previewReplace(w);
          }, child: const Padding(padding: EdgeInsets.all(12), child: Text('替换'))));
          break;
      }
    }
    return children;
  }

  /// 朗读选中文本（用当前 TTS 服务合成单段）
  Future<void> _speakSelection(String text) async {
    if (text.trim().isEmpty) return;
    try {
      await _ttsService.speakOnce(text);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('当前引擎不支持朗读选中文本')));
    }
  }

  /// 在浏览器打开选中内容（URL 直接打开，否则搜索引擎搜索）
  Future<void> _openInBrowser(String text) async {
    if (text.isEmpty) return;
    final isUrl = RegExp(r'^(https?://|www\.)\S+$', caseSensitive: false).hasMatch(text);
    final url = isUrl
        ? (text.toLowerCase().startsWith('www.') ? 'https://$text' : text)
        : 'https://www.bing.com/search?q=${Uri.encodeComponent(text)}';
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('无法打开: $e')));
    }
  }

  /// 分享选中文本
  Future<void> _shareSelection(String text) async {
    if (text.trim().isEmpty) return;
    try {
      await Share.share(text);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('分享失败')));
    }
  }

  /// 预览选中文本经过替换规则后的结果
  Future<void> _previewReplace(String text) async {
    if (text.trim().isEmpty) return;
    try {
      final rules = await _db.getReplaceRules();
      final enabled = rules.where((r) => r.enable == true).toList();
      final svc = ReplaceRuleService();
      final out = enabled.isEmpty ? text : svc.applyRules(text, enabled);
      if (!mounted) return;
      showDialog(context: context, builder: (_) => AlertDialog(
        title: const Text('替换预览'),
        content: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('原文：$text', style: const TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 8),
          Text('结果：$out', style: const TextStyle(fontSize: 15)),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
      ));
    } catch (_) {}
  }

  Future<void> _translateSelection(String text) async {
    if (text.trim().isEmpty) return;
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    try {
      await TranslationService.instance.loadPrefs();
      final out = await TranslationService.instance.translate(text);
      if (mounted) { Navigator.pop(context); showDialog(context: context, builder: (_) => AlertDialog(
        title: const Text('翻译'),
        content: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('原文：$text', style: const TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 8),
          Text('译文：$out', style: const TextStyle(fontSize: 15)),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
      )); }
    } catch (e) {
      if (mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('翻译失败: $e'))); }
    }
  }

  /// 反转章节内容（每段倒序）
  void _reverseContent() {
    if (_content == null) return;
    final paras = _content!.split(RegExp(r'\n+'));
    setState(() {
      _content = paras.reversed.map((p) => p.split('').reversed.join()).join('\n\n');
      _paginateContent();
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已反转内容')));
  }

  // 对齐 E book_read.xml：重新分段 / 删除注音 / 删除标题改为持久开关
  // （见 _loadChapterContent 的内容后处理与 _flipContentToggle），故删除原一次性操作方法。

  void _selectCharset() {
    const charsets = ['UTF-8', 'GBK', 'GB2312', 'GB18030', 'Big5', 'ISO-8859-1'];
    showModalBottomSheet(context: context, builder: (c) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Padding(padding: EdgeInsets.all(16), child: Text('选择编码', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
      ...charsets.map((cs) => ListTile(title: Text(cs), onTap: () async {
        Navigator.pop(c);
        _engine.setCharset(cs == 'UTF-8' ? null : cs.toLowerCase());
        final p = await SharedPreferences.getInstance();
        await p.setString('force_charset', cs);
        context.read<ReadProvider>().updateConfig((c) => c.charset = cs);
        _loadChapterContent(_currentChapterIndex);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已切换编码 $cs 并重新加载')));
      })),
    ])));
  }

  /// 简繁转换（0不转换 1转简体 2转繁体），对齐 legado-E 的 ChineseConverter。
  void _showChineseConverter() {
    final current = context.read<ReadProvider>().config.chineseConverter;
    const names = ['不转换', '转为简体', '转为繁体'];
    showModalBottomSheet(context: context, builder: (c) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Padding(padding: EdgeInsets.all(16), child: Text('简繁转换', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
      for (var i = 0; i < names.length; i++)
        RadioListTile<int>(
          title: Text(names[i]),
          value: i,
          groupValue: current,
          onChanged: (v) {
            Navigator.pop(c);
            if (v == null) return;
            context.read<ReadProvider>().updateConfig((cfg) => cfg.chineseConverter = v);
            _loadChapterContent(_currentChapterIndex);
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已${names[v]}并重新加载')));
          },
        ),
    ])));
  }

  void _showDebugLog() {
    showDialog(context: context, builder: (c) => AlertDialog(
      title: const Text('调试日志'),
      content: SizedBox(
        width: double.maxFinite,
        child: StatefulBuilder(builder: (c, setD) {
          final logs = List<String>.from(_engine.debugLog.reversed);
          final head = '书源: ${widget.book.originName ?? widget.book.origin ?? "本地"}\n章节: ${_currentChapterIndex + 1}/${_chapters.length}\n分页: ${_currentPage + 1}/${_pages.length}\n';
          if (logs.isEmpty) {
            return SingleChildScrollView(child: Text('$head\n（暂无网络请求日志，切换章节或刷新目录后可见）'));
          }
          return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(head, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            const Divider(height: 8),
            Expanded(child: ListView(children: logs.map((l) => Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(l, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')))).toList())),
          ]);
        }),
      ),
      actions: [
        TextButton(onPressed: () { _engine.clearDebugLog(); Navigator.pop(c); }, child: const Text('清空')),
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭')),
      ],
    ));
  }

  Future<void> _cacheChapters(int start, int end) async {
    if (_chapters.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('暂无章节可缓存')));
      return;
    }
    final total = end - start + 1;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('开始缓存 $total 章...')));
    int cached = 0;
    for (int i = start; i <= end && i < _chapters.length; i++) {
      final chapter = _chapters[i];
      // 检查是否已有缓存（单章查询，避免每轮都读全书正文）
      final cachedChapter = await _db.getChapter(widget.book.name, widget.book.author, i);
      if (cachedChapter != null && cachedChapter.content != null && cachedChapter.content!.isNotEmpty) {
        cached++;
        continue;
      }
      // 从网络获取
      if (widget.book.origin != null && chapter.url.isNotEmpty && !chapter.url.startsWith('local_')) {
        try {
          final sources = await _db.getAllSources(enabled: true);
          final source = sources.where((s) => s.bookSourceUrl == widget.book.origin).firstOrNull;
          if (source != null) {
            final replaceRules = await _db.getReplaceRules();
            final content = await _engine.getContent(source, chapter.url,
                replaceRules: replaceRules,
                bookInfo: widget.book.jsContext(),
                chapter: chapter.jsContext(widget.book.bookUrl));
            if (content != null) {
              await _db.updateChapterContent(widget.book.name, widget.book.author, i, content);
              cached++;
            }
          }
        } catch (_) {}
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('缓存完成，共 $cached 章')));
    }
  }

  Future<void> _addBookmark({String? note}) async {
    final currentPage = _pageController.hasClients ? _pageController.page?.round() ?? 0 : 0;
    final snippet = _pages.isNotEmpty ? _pages[currentPage.clamp(0, _pages.length - 1)] : '';
    final bookmark = {
      'bookName': widget.book.name,
      'bookAuthor': widget.book.author,
      'chapterIndex': _currentChapterIndex,
      'chapterTitle': _chapters.isNotEmpty ? _chapters[_currentChapterIndex].title : '',
      'pageIndex': currentPage,
      // 划词加书签时以选中文本作为笔记，否则用当前页摘要
      'content': (note != null && note.trim().isNotEmpty)
          ? note.trim()
          : (snippet.length > 50 ? snippet.substring(0, 50) : snippet),
      'createTime': DateTime.now().millisecondsSinceEpoch,
    };
    await _db.addBookmark(Bookmark.fromMap(bookmark));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已添加书签')));
    }
  }

  Future<void> _showBookmarks() async {
    final bookmarks = await _db.getBookmarks(widget.book.name, widget.book.author);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('书签列表', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            if (bookmarks.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text('暂无书签', style: TextStyle(color: Colors.grey)),
              )
            else
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: bookmarks.length,
                  itemBuilder: (context, index) {
                    final bm = bookmarks[index];
                    return ListTile(
                      leading: const Icon(Icons.bookmark),
                      title: Text(bm.chapterTitle.isNotEmpty ? bm.chapterTitle : '第${bm.chapterIndex}章'),
                      subtitle: Text('第 ${(bm.pageIndex as int? ?? 0) + 1} 页'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          await _db.deleteBookmark(bm.id!);
                          Navigator.pop(context);
                          _showBookmarks();
                        },
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        final chIndex = bm.chapterIndex as int? ?? 0;
                        final pageIndex = bm.pageIndex as int? ?? 0;
                        if (chIndex != _currentChapterIndex) {
                          _loadChapterContent(chIndex, targetPage: pageIndex);
                        } else {
                          // 同章节直接跳转到对应页
                          if (pageIndex >= 0 && pageIndex < _pages.length) {
                            _currentPage = pageIndex;
                            _pageController.jumpToPage(pageIndex);
                            _saveCurrentProgress();
                            setState(() {});
                          }
                        }
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showFontPicker() {
    final readProvider = context.read<ReadProvider>();
    final fonts = ['系统默认', 'serif', 'sans-serif', 'monospace', 'cursive'];
    final fontNames = ['系统默认', '衬线体', '无衬线体', '等宽字体', '手写体'];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择字体'),
        content: Column(mainAxisSize: MainAxisSize.min, children: List.generate(fonts.length, (index) => RadioListTile<String>(
          title: Text(fontNames[index], style: index == 0 ? null : TextStyle(fontFamily: fonts[index])),
          value: fonts[index],
          groupValue: readProvider.config.fontFamily ?? '系统默认',
          onChanged: (value) {
            if (value != null) readProvider.updateConfig((c) => c.fontFamily = value == '系统默认' ? null : value);
            Navigator.pop(context);
          },
        ))),
      ),
    );
  }

  void _showPageAnimPicker() {
    final readProvider = context.read<ReadProvider>();
    final anims = ['覆盖', '仿真', '滑动', '滚动', '无动画', '上下'];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('翻页动画'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(anims.length, (index) {
            return RadioListTile<int>(
              title: Text(anims[index]),
              value: index,
              groupValue: readProvider.config.pageAnim,
              onChanged: (value) {
                if (value != null) readProvider.setPageAnim(value);
                Navigator.pop(context);
              },
            );
          }),
        ),
      ),
    );
  }

  void _showBrightnessSlider() {
    final readProvider = context.read<ReadProvider>();
    // 拖动中的局部亮度值：只更新局部状态，不写盘/不通知
    var dragging = readProvider.brightness;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('亮度调节'),
        content: StatefulBuilder(
          builder: (context, setState) => Slider(
            value: dragging,
            // 拖动中仅局部刷新滑块，不写 SharedPreferences、不 notify
            onChanged: (value) {
              dragging = value;
              setState(() {});
            },
            // 松手才持久化并通知阅读界面生效
            onChangeEnd: (value) {
              readProvider.setBrightness(value);
            },
          ),
        ),
      ),
    );
  }

  Future<void> _showChapterList() async {
    final result = await Navigator.push<(int, bool)>(context, MaterialPageRoute(builder: (_) => ChapterListScreen(book: widget.book, chapters: _chapters, currentIndex: _currentChapterIndex)));
    if (result != null) {
      final (index, tocChanged) = result;
      // 目录被重排（长章节拆分切换）后按新目录重载，索引才能对上
      if (tocChanged) {
        _chapters = await _db.getChapters(widget.book.name, widget.book.author);
      }
      if (index >= 0 && index < _chapters.length) {
        _loadChapterContent(index);
      }
    }
  }

  Future<void> _showSearchInBook({String? initialKeyword}) async {
    final hit = await Navigator.push<ContentSearchHit>(
        context, MaterialPageRoute(builder: (_) => SearchContentScreen(book: widget.book, initialKeyword: initialKeyword)));
    if (hit == null) return;
    if (hit.chapterIndex != _currentChapterIndex) {
      // 命中其他章：记录章内偏移，章节加载分页完成后按偏移定位到具体页
      _pendingPosInChapter = hit.posInChapter;
      _loadChapterContent(hit.chapterIndex);
    } else {
      // 命中当前章：直接按偏移定位页码
      _jumpToPosInChapter(hit.posInChapter);
    }
  }

  /// 线性查找字符偏移所在的页（_pages 为按序拼接的分页文本）
  int _pageForOffset(int pos) {
    if (_pages.isEmpty || pos <= 0) return 0;
    var acc = 0;
    for (var i = 0; i < _pages.length; i++) {
      final len = _pages[i].length;
      if (pos < acc + len) return i;
      acc += len;
    }
    return _pages.length - 1;
  }

  /// 按章内字符偏移定位并跳转到对应页（正文搜索命中当前章时使用）
  void _jumpToPosInChapter(int pos) {
    final page = _pageForOffset(pos);
    if (page >= _pages.length) return;
    _currentPage = page;
    if (_pageController.hasClients) {
      _pageController.jumpToPage(page);
    }
    _saveCurrentProgress();
    if (mounted) setState(() {});
  }

  // 对齐 E book_read.xml：更多菜单不含「翻译设置 / 章节摘要」入口，
  // 故删除无消费方的对话框方法；划词翻译（_translateSelection）仍由文本选择菜单提供。

  void _showContentEditor() {
    final controller = TextEditingController(text: _chapters.isNotEmpty ? (_chapters[_currentChapterIndex].content ?? '') : '');
    showDialog(context: context, builder: (context) => AlertDialog(
      title: const Text('内容编辑'),
      content: SizedBox(width: double.maxFinite, child: TextField(controller: controller, maxLines: 10, decoration: const InputDecoration(border: OutlineInputBorder()))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: () async {
          if (_chapters.isNotEmpty && _currentChapterIndex < _chapters.length) {
            _chapters[_currentChapterIndex].content = controller.text;
            // 仅更新当前章内容，避免全表重写清空其他章节
            await _db.updateChapterContent(widget.book.name, widget.book.author, _currentChapterIndex, controller.text);
            if (mounted) { setState(() {}); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('内容已保存'))); }
          }
          Navigator.pop(context);
        }, child: const Text('保存')),
      ],
    ));
  }

  Future<void> _showReplaceRules() async {
    final all = await _db.getReplaceRules();
    final enabled = all.where((r) => r.enable == true).toList();
    final scopeForBook = enabled.where((r) => r.scope == null || r.scope!.isEmpty || r.scope == 'all' || r.scope == widget.book.origin || (r.scope ?? '').contains(widget.book.name)).toList();
    if (!mounted) return;
    showDialog(context: context, builder: (d) => AlertDialog(
      title: const Text('生效替换规则'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.rule), title: const Text('全局替换规则'),
          subtitle: Text('${enabled.length} 条已启用'), trailing: const Icon(Icons.chevron_right),
          onTap: () { Navigator.pop(d); Navigator.push(context, MaterialPageRoute(builder: (_) => const ReplaceRuleScreen())); },
        ),
        ListTile(
          leading: const Icon(Icons.rule_folder), title: const Text('本书生效规则'),
          subtitle: Text('${scopeForBook.length} 条对本书生效'),
        ),
        if ((_content ?? '').isNotEmpty) ListTile(
          leading: const Icon(Icons.preview), title: const Text('预览当前章节替换效果'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            Navigator.pop(d);
            final svc = ReplaceRuleService();
            final preview = svc.applyRules(_content!, enabled, scope: widget.book.origin);
            if (!mounted) return;
            showDialog(context: context, builder: (p) => AlertDialog(
              title: const Text('替换预览'),
              content: SizedBox(width: double.maxFinite, child: SingleChildScrollView(child: Text(preview, style: const TextStyle(fontSize: 13)))),
              actions: [TextButton(onPressed: () => Navigator.pop(p), child: const Text('关闭'))],
            ));
          },
        ),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('关闭'))],
    ));
  }

  void _showReadingSettings() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ReadingSettingsScreen()));
  }

  /// 朗读暂停/恢复（未在朗读则启动朗读）
  void _toggleTtsPause() {
    if (!_ttsService.isPlaying && !_ttsService.isPaused) {
      _startTTS();
      return;
    }
    if (_ttsService.isPaused) {
      _ttsService.resume();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('继续朗读'), duration: Duration(seconds: 1)));
    } else {
      _ttsService.pause();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已暂停朗读'), duration: Duration(seconds: 1)));
    }
  }

  /// 切换替换净化开关，切换后重新加载当前章并重排
  void _togglePurify() {
    setState(() => _purifyEnabled = !_purifyEnabled);
    _loadChapterContent(_currentChapterIndex, targetPage: _currentPage);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(_purifyEnabled ? '替换净化：已开启' : '替换净化：已关闭'),
      duration: const Duration(seconds: 1),
    ));
  }

  Future<void> _startTTS() async {
    // 注入按需加载器：朗读到未缓存章节时自动联网取正文
    _ttsService.contentLoader = (index) async {
      if (index < 0 || index >= _chapters.length) return null;
      final ch = _chapters[index];
      if ((ch.content ?? '').isNotEmpty) return ch.content;
      if (widget.book.origin == null) return null;
      final sources = await _db.getAllSources(enabled: true);
      final source = sources.where((s) => s.bookSourceUrl == widget.book.origin).firstOrNull;
      if (source == null || ch.url.isEmpty) return null;
      final rules = await _db.getReplaceRules();
      final content = await _engine.getContent(source, ch.url,
          replaceRules: rules,
          bookInfo: widget.book.jsContext(),
          chapter: ch.jsContext(widget.book.bookUrl));
      if (content != null && content.isNotEmpty) {
        await _db.updateChapterContent(widget.book.name, widget.book.author, ch.index, content);
        ch.content = content;
      }
      return content;
    };
    _ttsService.setChapters(_chapters, startIndex: _currentChapterIndex);
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => TtsPlayerScreen(
      ttsService: _ttsService,
      chapters: _chapters,
      currentIndex: _currentChapterIndex,
      bookName: widget.book.name,
    )));
  }
}

/// 翻页动画包装层（覆盖 / 仿真）。
/// 监听 [_PageAnimLayer.controller]，每帧只重建 Transform 包装；
/// 静态页内容通过 child 传入，不参与每帧重建。MediaQuery 由调用方在动画外只取一次。
class _PageAnimLayer extends StatelessWidget {
  final PageController controller;
  /// 控制器尚无尺寸时的回退页码
  final int fallbackPage;
  final int index;
  /// 单页位移距离（横排取屏宽，竖排取屏高）
  final double advance;
  final bool vertical;
  final bool simulate;
  final Widget child;

  const _PageAnimLayer({
    required this.controller,
    required this.fallbackPage,
    required this.index,
    required this.advance,
    required this.vertical,
    required this.simulate,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      child: child,
      builder: (ctx, staticChild) {
        final page = (controller.hasClients && controller.position.haveDimensions)
            ? (controller.page ?? fallbackPage.toDouble())
            : fallbackPage.toDouble();
        final diff = (index - page).clamp(0.0, 1.0);
        var widget = staticChild!;
        if (simulate) {
          // 仿真：下层页轻微缩放 + 阴影折角，上层页滑入覆盖
          final scale = 1.0 - (1.0 - diff) * 0.04;
          widget = Transform.scale(scale: scale, child: widget);
          if (diff > 0.01) {
            widget = DecoratedBox(
              decoration: BoxDecoration(boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.18 * diff),
                    blurRadius: 12,
                    spreadRadius: 1)
              ]),
              child: widget,
            );
          }
        }
        return Transform.translate(
          offset: vertical ? Offset(0, diff * advance) : Offset(diff * advance, 0),
          child: widget,
        );
      },
    );
  }
}

/* ===== 由 change_chapter_source_sheet.dart 合并 ===== */
/// 章节换源 - 对齐原版ChangeChapterSourceSheet
/// 列出可用书源，选择后用指定源重新加载章节
class ChangeChapterSourceSheet extends StatefulWidget {
  final String bookName;
  final String author;
  /// 当前书籍来源，列出时排除，避免重复选择
  final String? currentOrigin;
  const ChangeChapterSourceSheet({super.key, required this.bookName, required this.author, this.currentOrigin});

  @override
  State<ChangeChapterSourceSheet> createState() => _ChangeChapterSourceSheetState();
}

class _ChangeChapterSourceSheetState extends State<ChangeChapterSourceSheet> {
  final _db = DatabaseService();
  List<BookSource> _sources = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await _db.getAllSources(enabled: true);
    // 排除当前书源
    final sources = widget.currentOrigin == null || widget.currentOrigin!.isEmpty
        ? all
        : all.where((s) => s.bookSourceUrl != widget.currentOrigin).toList();
    setState(() { _sources = sources; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7, minChildSize: 0.4, maxChildSize: 0.95, expand: false,
      builder: (context, scrollController) => Column(children: [
        const Padding(padding: EdgeInsets.all(16), child: Text('章节换源', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('选择其他书源加载本章内容', style: TextStyle(fontSize: 12, color: Colors.grey))),
        const SizedBox(height: 8),
        Expanded(child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sources.isEmpty
            ? const Center(child: Text('没有可用书源'))
            : ListView.builder(
                controller: scrollController,
                itemCount: _sources.length,
                itemBuilder: (context, i) {
                  final s = _sources[i];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.source_outlined),
                    title: Text(s.bookSourceName, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(s.bookSourceGroup ?? s.bookSourceUrl, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                    onTap: () => Navigator.pop(context, s),
                  );
                },
              )),
      ]),
    );
  }
}

