
import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_chapter.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/data/model/bookmark.dart';
import 'package:legado_md3/data/model/db_models.dart';
import 'package:legado_md3/data/model/read_config.dart';
import 'package:legado_md3/di/book_provider.dart';
import 'package:legado_md3/help/config/read_menu_config.dart';
import 'package:legado_md3/help/http/cookie_manager.dart';
import 'package:legado_md3/help/readaloud/reading_record.dart';
import 'package:legado_md3/help/readaloud/tts_service.dart';
import 'package:legado_md3/help/source/content_services.dart';
import 'package:legado_md3/help/source/content_services.dart';
import 'package:legado_md3/help/source/replace_rule_service.dart';
import 'package:legado_md3/help/source/source_engine.dart';
import 'package:legado_md3/help/storage/local_book_parser.dart';
import 'package:legado_md3/help/translate/translation_service.dart';
import 'package:legado_md3/ui/book/chapter/chapter_list_screen.dart';
import 'package:legado_md3/ui/book/detail/book_detail_screen.dart';
import 'package:legado_md3/ui/book/read/config/reading_settings_screen.dart';
import 'package:legado_md3/ui/book/read/tts_player_screen.dart';
import 'package:legado_md3/ui/book/read/widgets/download_sheet.dart';
import 'package:legado_md3/ui/book/search/search_content_screen.dart';
import 'package:legado_md3/ui/book/source/source_login_screen.dart';
import 'package:legado_md3/ui/browser/browser_screen.dart';
import 'package:legado_md3/ui/config/replace_rule_screen.dart';
import 'package:legado_md3/ui/config/txt_toc_rule_screen.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
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
  int _currentPage = 0;
  List<String> _pages = [];
  List<String> _toolbarOrder = List.of(ReadMenuConfig.defaultToolBar);
  List<String> _moreMenuOrder = List.of(ReadMenuConfig.defaultMoreMenu);
  List<String> _selectMenuOrder = List.of(ReadMenuConfig.defaultSelectMenu);
  List<String> _floatingBarOrder = List.of(ReadMenuConfig.defaultFloatingBar);
  bool _floatingBarVisible = true;
  // 实验室开关：正文是否允许自由选择复制（默认开启）
  bool _textSelectable = true;
  // 实验室开关：分页估算诊断（输出分页计算过程到控制台）
  bool _pageDiag = false;
  // 实验室开关：加速下载（预缓存时多章节并发拉取）
  bool _accelerateDownload = false;
  // 下载缓存配置：阅读时向后预缓存的章节数（0 表示关闭）
  int _preDownload = 5;
  // 正在预缓存的章节下标，避免重复请求
  final Set<int> _prefetching = {};
  // 书源开启 customButton 时缓存的来源书源，用于「书源操作」菜单
  BookSource? _customButtonSource;

  /// 加载当前书籍来源书源；若其启用 customButton，则在更多菜单暴露「书源操作」
  Future<void> _loadCustomButtonSource() async {
    final origin = widget.book.origin;
    if (origin == null || origin.isEmpty) return;
    try {
      final sources = await _db.getAllSources();
      BookSource? s;
      for (final e in sources) {
        if (e.bookSourceUrl == origin) { s = e; break; }
      }
      if (mounted) setState(() => _customButtonSource = (s != null && s.customButton) ? s : null);
    } catch (_) {}
  }

  /// 书源操作面板（设置变量 / 登录 / 清 Cookie / 打开主页）
  void _showSourceActions() {
    final source = _customButtonSource;
    if (source == null) return;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.edit_note), title: const Text('设置书源变量'),
              subtitle: Text(source.variableComment?.isNotEmpty == true ? source.variableComment! : 'variableComment 未提示', maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () async {
                Navigator.pop(ctx);
                final ctrl = TextEditingController(text: source.variable ?? '');
                final v = await showDialog<String>(context: context, builder: (d) => AlertDialog(
                  title: const Text('设置书源变量'),
                  content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: '变量内容（JSON 或文本）'), maxLines: 4),
                  actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('取消')),
                    FilledButton(onPressed: () => Navigator.pop(d, ctrl.text), child: const Text('保存'))],
                ));
                if (v != null) {
                  await _db.updateSourceVariable(source.bookSourceUrl, v);
                  source.variable = v;
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('书源变量已保存')));
                }
              }),
            ListTile(leading: const Icon(Icons.login), title: const Text('书源登录'),
              onTap: () { Navigator.pop(ctx); Navigator.push(context, MaterialPageRoute(builder: (_) => SourceLoginScreen(source: source))); }),
            ListTile(leading: const Icon(Icons.cookie_outlined), title: const Text('清除书源 Cookie'),
              onTap: () {
                Navigator.pop(ctx);
                final host = Uri.tryParse(source.bookSourceUrl)?.host ?? '';
                if (host.isNotEmpty) CookieManager().removeHost(host);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已清除该书源 Cookie')));
              }),
            ListTile(leading: const Icon(Icons.language), title: const Text('打开书源主页'),
              onTap: () { Navigator.pop(ctx); Navigator.push(context, MaterialPageRoute(builder: (_) => BrowserScreen(url: source.bookSourceUrl, title: source.bookSourceName))); }),
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
    final cached = await _db.getChapters(widget.book.name, widget.book.author);
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
      final already = i < cached.length && cached[i].content != null;
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
      });
    }
  }

  Future<void> _loadMenuConfig() async {
    final tb = await ReadMenuConfig.load(ReadMenuConfig.kToolBar, ReadMenuConfig.defaultToolBar);
    final mm = await ReadMenuConfig.load(ReadMenuConfig.kMoreMenu, ReadMenuConfig.defaultMoreMenu);
    final sm = await ReadMenuConfig.load(ReadMenuConfig.kSelectMenu, ReadMenuConfig.defaultSelectMenu);
    final fb = await ReadMenuConfig.load(ReadMenuConfig.kFloatingBar, ReadMenuConfig.defaultFloatingBar);
    if (mounted) setState(() { _toolbarOrder = tb; _moreMenuOrder = mm; _selectMenuOrder = sm; _floatingBarOrder = fb; });
  }

  @override
  void initState() {
    super.initState();
    _loadClickActions();
    _loadCustomButtonSource();
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
    _loadData();
    // 时钟：每分钟更新一次时间显示
    _currentTime = _formatTime(DateTime.now());
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _currentTime = _formatTime(DateTime.now()));
    });
    // 屏幕常亮：延迟到第一帧后读取 config
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyWakeLock(context.read<ReadProvider>().config.keepScreenOn);
    });
  }

  @override
  void dispose() {
    _autoReadTimer?.cancel();
    _clockTimer?.cancel();
    _menuController.dispose();
    _pageController.dispose();
    _recordService.endSession(
      chapterIndex: _currentChapterIndex,
      chapterTitle: _chapters.isNotEmpty ? _chapters[_currentChapterIndex].title : null,
    );
    _ttsService.dispose();
    _applyWakeLock(false);
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

  Future<void> _loadChapterContent(int index, {int? targetPage}) async {
    if (index < 0 || index >= _chapters.length) return;
    setState(() => _isLoadingChapter = true);

    final chapter = _chapters[index];
    // 先尝试从数据库读取缓存
    final cachedChapters = await _db.getChapters(widget.book.name, widget.book.author);
    if (index < cachedChapters.length && cachedChapters[index].content != null && cachedChapters[index].content!.isNotEmpty) {
      _content = cachedChapters[index].content;
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
        final source = sources.where((s) => s.bookSourceUrl == widget.book.origin).firstOrNull;
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

    // 应用替换净化规则（确保本地缓存内容也能被净化）
    if (_content != null && _content!.isNotEmpty) {
      try {
        final replaceRules = await _db.getReplaceRules();
        if (replaceRules.isNotEmpty) {
          final svc = ReplaceRuleService();
          _content = svc.applyRules(_content!, replaceRules);
        }
      } catch (_) {}
    }

    _paginateContent();
    _currentChapterIndex = index;
    // 跳转到指定页码（书签跳转或恢复阅读进度）
    if (targetPage != null && targetPage >= 0 && targetPage < _pages.length) {
      _currentPage = targetPage;
    } else if (widget.initialChapter == null && index == widget.book.durChapterIndex) {
      // 恢复上次阅读页码（仅首次加载时）
      final savedPos = widget.book.durChapterPos ?? 0;
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

  void _paginateContent() {
    if (_content == null || _content!.isEmpty) {
      _pages = ['暂无内容'];
      return;
    }
    final config = context.read<ReadProvider>().config;
    // 首行缩进：textIndent 单位为字符（0-4）
    final indent = config.textIndent > 0 ? ' ' * (config.textIndent * 2) : '';
    // 段间距：paragraphSpacing 单位为空行（0-4）
    final paraGap = '\n' * (config.paragraphSpacing + 1);
    // 每页字数上限：根据字体大小动态调整
    final charsPerPage = (config.textSize <= 14 ? 1000 : config.textSize <= 18 ? 800 : 600);

    final paragraphs = _content!.split(RegExp(r'\n+')).where((p) => p.trim().isNotEmpty).toList();
    final List<String> pages = [];
    StringBuffer currentPage = StringBuffer();
    int charCount = 0;

    for (var i = 0; i < paragraphs.length; i++) {
      final para = '$indent${paragraphs[i].trim()}';
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

  Future<void> _dictLookup(String word) async {
    final w = word.trim();
    if (w.isEmpty) return;
    final rules = await _db.getDictRules();
    final rule = rules.firstWhere((r) => r.enabled == 1 && r.url.contains('{word}'), orElse: () => DictRule(name: '在线词典', url: 'https://www.baidu.com/s?wd={word}'));
    final url = rule.url.replaceAll('{word}', Uri.encodeComponent(w));
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => BrowserScreen(url: url, title: '${rule.name}: $w')));
  }

  @override
  Widget build(BuildContext context) {
    final readProvider = context.watch<ReadProvider>();
    final config = readProvider.config;
    // 屏幕常亮设置变化时实时生效
    if (_wakeEnabled != config.keepScreenOn) {
      _applyWakeLock(config.keepScreenOn);
    }

    return Focus(
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
                    switch (action) {
                      case 1: _prevChapter(); break;
                      case 2: _nextChapter(); break;
                      case 3: _toggleMenu(); break;
                      case 4: _prevPage(); break;
                      case 5: _nextPage(); break;
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
                          if (config.pageNumberVisibility || config.timeVisibility)
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
                      _buildFloatingBar(),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildHeader(ReadConfig config) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: config.paddingLeft.toDouble(),
        vertical: 4,
      ),
      height: config.headerHeight.toDouble(),
      alignment: config.headerAlignCenter ? Alignment.center : Alignment.centerLeft,
      child: Text(
        _chapters.isNotEmpty ? _chapters[_currentChapterIndex].title : widget.book.name,
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

  Widget _pageText(ReadConfig config, int index) {
    final style = TextStyle(
      fontSize: config.textSize.toDouble(),
      color: Color(config.textColor),
      height: config.lineSpacing * 0.5 + 1.0,
      letterSpacing: config.letterSpacing,
      wordSpacing: config.wordSpacing,
      fontWeight: config.boldText ? FontWeight.bold : FontWeight.normal,
      fontFamily: config.fontFamily,
    );
    final align = config.textAlign == 1
        ? TextAlign.center
        : config.textAlign == 2
            ? TextAlign.justify
            : TextAlign.left;
    // 命中高亮标签规则时用 Text.rich 上色，否则退回普通 Text
    final spans = HighlightService.spansFor(_pages[index], style);
    if (spans != null) {
      return Text.rich(TextSpan(children: spans), textAlign: align);
    }
    return Text(_pages[index], style: style, textAlign: align);
  }

  Widget _buildReadingContent(ReadConfig config) {
    // 翻页动画：0覆盖 1仿真 2滑动 3滚动 4无动画 5上下
    final isVertical = config.pageAnim == 5;
    final noAnim = config.pageAnim == 4;
    final scrollMode = config.pageAnim == 3;

    if (scrollMode) {
      // 滚动模式：连续滚动，不分页
      return SingleChildScrollView(
        scrollDirection: isVertical ? Axis.horizontal : Axis.vertical,
        padding: EdgeInsets.fromLTRB(
          config.paddingLeft.toDouble(),
          config.paddingTop.toDouble(),
          config.paddingRight.toDouble(),
          config.paddingBottom.toDouble(),
        ),
        child: _textSelectable
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
                child: _pageText(config, 0),
              )
            : _pageText(config, 0),
      );
    }

    return PageView.builder(
      controller: _pageController,
      scrollDirection: isVertical ? Axis.vertical : Axis.horizontal,
      physics: noAnim ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
      itemCount: _pages.length,
      onPageChanged: (page) => setState(() => _currentPage = page),
      itemBuilder: (context, index) {
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            config.paddingLeft.toDouble(),
            config.paddingTop.toDouble(),
            config.paddingRight.toDouble(),
            config.paddingBottom.toDouble(),
          ),
          child: _textSelectable
              ? SelectionArea(
                  contextMenuBuilder: (context, state) {
                    // 兼容 Flutter 3.24：先复制选区，再从剪贴板读取选中文字（不依赖 currentTextSelection/currentSelectable）
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
                  child: _pageText(config, index),
                )
              : _pageText(config, index),
        );
      },
    );
  }

  Widget _buildFooter(ReadConfig config) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: config.paddingLeft.toDouble(),
        vertical: 4,
      ),
      height: config.footerHeight.toDouble(),
      child: Row(
        mainAxisAlignment: config.footerAlignCenter ? MainAxisAlignment.center : MainAxisAlignment.spaceBetween,
        children: [
          if (config.timeVisibility)
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
          if (config.batteryVisibility)
            Icon(Icons.battery_full, size: 14, color: Color(config.footerColor)),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildTopMenu() {
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
        title: Text(widget.book.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt),
            onPressed: () async {
              _menuController.reverse();
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChapterListScreen(
                    chapters: _chapters,
                    currentIndex: _currentChapterIndex,
                  ),
                ),
              );
              if (result != null && result is int) {
                _loadChapterContent(result);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () => _showMoreMenu(),
          ),
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
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 进度条
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.skip_previous),
                    onPressed: _currentChapterIndex > 0 ? () => _loadChapterContent(_currentChapterIndex - 1) : null,
                  ),
                  Expanded(
                    child: Slider(
                      value: _chapters.length <= 1 ? 0 : _currentChapterIndex / (_chapters.length - 1),
                      onChanged: _chapters.length <= 1
                          ? null
                          : (value) {
                              final index = (value * (_chapters.length - 1)).round();
                              _loadChapterContent(index);
                            },
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next),
                    onPressed: _currentChapterIndex < _chapters.length - 1
                        ? () => _loadChapterContent(_currentChapterIndex + 1)
                        : null,
                  ),
                ],
              ),
            ),
            // 字号和行距
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Text('字号'),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () => readProvider.setTextSize(config.textSize - 1),
                  ),
                  Text('${config.textSize}'),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () => readProvider.setTextSize(config.textSize + 1),
                  ),
                  const Spacer(),
                  const Text('行距'),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () => readProvider.setLineSpacing(config.lineSpacing - 1),
                  ),
                  Text('${config.lineSpacing}'),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () => readProvider.setLineSpacing(config.lineSpacing + 1),
                  ),
                ],
              ),
            ),
            // 背景色选择
            SizedBox(
              height: 60,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: ReadConfig.presets.length,
                itemBuilder: (context, index) {
                  final preset = ReadConfig.presets[index];
                  final isSelected = config.bgColor == preset['bg'];
                  return GestureDetector(
                    onTap: () {
                      readProvider.setBgColor(preset['bg'] as int);
                      readProvider.setTextColor(preset['text'] as int);
                    },
                    child: Container(
                      width: 56,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        color: Color(preset['bg'] as int),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected ? Theme.of(context).colorScheme.primary : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          preset['name'] as String,
                          style: TextStyle(
                            color: Color(preset['text'] as int),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            // 底部操作按钮（显示与顺序可在「阅读菜单配置」中自定义）
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final key in _toolbarOrder)
                    if (_toolAction(key) != null)
                      _buildBottomAction(_toolAction(key)!.$1, _toolAction(key)!.$2, _toolAction(key)!.$3),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 悬浮快捷栏（右侧竖排，可点击手柄收起/展开）
  Widget _buildFloatingBar() {
    if (_floatingBarOrder.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Positioned(
      right: 4,
      top: MediaQuery.of(context).size.height * 0.3,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        child: Container(
          decoration: BoxDecoration(
            color: cs.surface.withOpacity(0.85),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 6)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () => setState(() => _floatingBarVisible = !_floatingBarVisible),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Icon(_floatingBarVisible ? Icons.chevron_right : Icons.chevron_left, size: 18, color: cs.onSurfaceVariant),
                ),
              ),
              if (_floatingBarVisible)
                for (final key in _floatingBarOrder)
                  if (_floatingAction(key) != null)
                    IconButton(
                      icon: Icon(_floatingAction(key)!.$1, size: 20),
                      tooltip: _floatingAction(key)!.$2,
                      onPressed: _floatingAction(key)!.$3,
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  (IconData, String, VoidCallback)? _floatingAction(String key) {
    switch (key) {
      case 'prev': return (Icons.skip_previous, '上一章', () => _currentChapterIndex > 0 ? _loadChapterContent(_currentChapterIndex - 1) : null);
      case 'next': return (Icons.skip_next, '下一章', () => _currentChapterIndex < _chapters.length - 1 ? _loadChapterContent(_currentChapterIndex + 1) : null);
      case 'toc': return (Icons.list_alt, '目录', () => _showChapterList());
      case 'search': return (Icons.search, '搜索', () => _showSearchInBook());
      case 'tts': return (Icons.headphones, '朗读', () => _startTTS());
      case 'more': return (Icons.more_horiz, '更多', () => _showMoreMenu());
      default: return null;
    }
  }

  (IconData, String, VoidCallback)? _toolAction(String key) {    switch (key) {
      case 'font': return (Icons.font_download, '字体', () => _showFontPicker());
      case 'pageanim': return (Icons.animation, '翻页', () => _showPageAnimPicker());
      case 'brightness': return (Icons.brightness_6, '亮度', () => _showBrightnessSlider());
      case 'settings': return (Icons.settings, '设置', () => _showReadingSettings());
      case 'tts': return (Icons.headphones, '朗读', () => _startTTS());
      default: return null;
    }
  }

  Widget _buildBottomAction(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }

  void _showMoreMenu() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final key in _moreMenuOrder) ...[
              if (key == 'detail' || key == 'reverse') const Divider(),
              if (_moreMenuItem(key, ctx) != null) _moreMenuItem(key, ctx)!,
            ],
          ],
        ),
      ),
    );
  }

  /// 更多菜单项（显示由 _moreMenuOrder 控制）
  Widget? _moreMenuItem(String key, BuildContext ctx) {
    void close() => Navigator.pop(ctx);
    switch (key) {
      case 'toc': return ListTile(leading: const Icon(Icons.list_alt), title: const Text('目录'), onTap: () { close(); _showChapterList(); });
      case 'search': return ListTile(leading: const Icon(Icons.search), title: const Text('搜索'), onTap: () { close(); _showSearchInBook(); });
      case 'translate': return ListTile(leading: const Icon(Icons.translate), title: const Text('翻译'), onTap: () { close(); _showTranslateDialog(); });
      case 'autoread': return ListTile(leading: Icon(_autoReadOn ? Icons.pause_circle : Icons.play_circle_outline), title: Text(_autoReadOn ? '停止自动阅读' : '自动阅读'), onTap: () { close(); _toggleAutoRead(); });
      case 'changesource': return ListTile(leading: const Icon(Icons.swap_horiz), title: const Text('章节换源'), onTap: () async {
          close();
          final source = await showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => ChangeChapterSourceSheet(bookName: widget.book.name, author: widget.book.author));
          if (source != null) { widget.book.origin = source.bookSourceUrl; widget.book.originName = source.bookSourceName; _loadChapterContent(_currentChapterIndex); }
        });
      case 'copypage': return ListTile(leading: const Icon(Icons.content_copy), title: const Text('复制当前页'), onTap: () async {
          close();
          if (_chapters.isNotEmpty && _currentChapterIndex < _chapters.length) {
            await Clipboard.setData(ClipboardData(text: _chapters[_currentChapterIndex].content ?? ''));
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
          }
        });
      case 'summary': return ListTile(leading: const Icon(Icons.subject), title: const Text('章节摘要'), onTap: () { close(); _showChapterSummary(); });
      case 'contentedit': return ListTile(leading: const Icon(Icons.edit_note), title: const Text('内容编辑'), onTap: () { close(); _showContentEditor(); });
      case 'replace': return ListTile(leading: const Icon(Icons.find_replace), title: const Text('生效替换'), onTap: () { close(); _showReplaceRules(); });
      case 'detail': return ListTile(leading: const Icon(Icons.info_outline), title: const Text('书籍详情'), onTap: () { close(); Navigator.push(context, MaterialPageRoute(builder: (_) => BookDetailScreen(book: widget.book))); });
      case 'refreshtoc': return ListTile(leading: const Icon(Icons.refresh), title: const Text('刷新目录'), onTap: () { close(); _fetchTocFromNetwork(); });
      case 'cache': return ListTile(leading: const Icon(Icons.download), title: const Text('离线缓存'), onTap: () async {
          close();
          final range = await showModalBottomSheet<List<int>>(context: context, builder: (_) => DownloadSheet(chapters: _chapters, currentIndex: _currentChapterIndex));
          if (range != null) _cacheChapters(range[0], range[1]);
        });
      case 'addbookmark': return ListTile(leading: const Icon(Icons.bookmark_border), title: const Text('添加书签'), onTap: () { close(); _addBookmark(); });
      case 'bookmarklist': return ListTile(leading: const Icon(Icons.bookmarks), title: const Text('书签列表'), onTap: () { close(); _showBookmarks(); });
      case 'share': return ListTile(leading: const Icon(Icons.share), title: const Text('分享书籍'), onTap: () { close(); Share.share('《${widget.book.name}》- ${widget.book.author}'); });
      case 'reverse': return ListTile(leading: const Icon(Icons.swap_vert), title: const Text('反转内容'), onTap: () { close(); _reverseContent(); });
      case 'resegment': return ListTile(leading: const Icon(Icons.format_align_left), title: const Text('重新分段'), onTap: () { close(); _reSegment(); });
      case 'delruby': return ListTile(leading: const Icon(Icons.text_fields), title: const Text('删除注音(ruby)'), onTap: () { close(); _cleanContent('ruby'); });
      case 'delh': return ListTile(leading: const Icon(Icons.title), title: const Text('删除标题标签'), onTap: () { close(); _cleanContent('h'); });
      case 'charset': return ListTile(leading: const Icon(Icons.code), title: const Text('选择编码'), onTap: () { close(); _selectCharset(); });
      case 'txttoc': return ListTile(leading: const Icon(Icons.list_alt), title: const Text('TXT目录规则'), onTap: () { close(); Navigator.push(context, MaterialPageRoute(builder: (_) => const TxtTocRuleScreen())); });
      case 'debug': return ListTile(leading: const Icon(Icons.receipt_long), title: const Text('调试日志'), onTap: () { close(); _showDebugLog(); });
      case 'sourceaction':
        if (_customButtonSource == null) return null;
        return ListTile(leading: const Icon(Icons.build_circle_outlined), title: const Text('书源操作'), onTap: () { close(); _showSourceActions(); });
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
      }
    }
    return children;
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

  /// 重新分段：把粘连文本按句号/问号/叹号重新换行
  void _reSegment() {
    if (_content == null) return;
    var text = _content!.replaceAll(RegExp(r'\s+'), '');
    text = text.replaceAllMapped(RegExp(r'[。！？…](?!["”』」])'), (m) => '${m[0]}\n\n');
    setState(() {
      _content = text;
      _paginateContent();
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已重新分段')));
  }

  /// 清理内容标签：ruby=注音标签，h=标题标签
  void _cleanContent(String type) {
    if (_content == null) return;
    var text = _content!;
    if (type == 'ruby') {
      text = text.replaceAll(RegExp(r'<ruby[^>]*>'), '').replaceAll(RegExp(r'</ruby>'), '').replaceAll(RegExp(r'<rt[^>]*>.*?</rt>', dotAll: true), '');
    } else {
      text = text.replaceAll(RegExp(r'<h[1-6][^>]*>'), '').replaceAll(RegExp(r'</h[1-6]>'), '');
    }
    setState(() {
      _content = text;
      _paginateContent();
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(type == 'ruby' ? '已删除注音' : '已删除标题标签')));
  }

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
      // 检查是否已有缓存
      final cachedChapters = await _db.getChapters(widget.book.name, widget.book.author);
      if (i < cachedChapters.length && cachedChapters[i].content != null && cachedChapters[i].content!.isNotEmpty) {
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

  Future<void> _addBookmark() async {
    final currentPage = _pageController.hasClients ? _pageController.page?.round() ?? 0 : 0;
    final bookmark = {
      'bookName': widget.book.name,
      'bookAuthor': widget.book.author,
      'chapterIndex': _currentChapterIndex,
      'chapterTitle': _chapters.isNotEmpty ? _chapters[_currentChapterIndex].title : '',
      'pageIndex': currentPage,
      'content': _pages.isNotEmpty ? _pages[currentPage.clamp(0, _pages.length - 1)].substring(0, _pages[currentPage.clamp(0, _pages.length - 1)].length > 50 ? 50 : _pages[currentPage.clamp(0, _pages.length - 1)].length) : '',
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('亮度调节'),
        content: StatefulBuilder(
          builder: (context, setState) => Slider(
            value: readProvider.brightness,
            onChanged: (value) {
              readProvider.setBrightness(value);
              setState(() {});
            },
          ),
        ),
      ),
    );
  }

  Future<void> _showChapterList() async {
    final index = await Navigator.push<int>(context, MaterialPageRoute(builder: (_) => ChapterListScreen(book: widget.book, chapters: _chapters, currentIndex: _currentChapterIndex)));
    if (index != null && index >= 0 && index < _chapters.length) {
      _loadChapterContent(index);
    }
  }

  Future<void> _showSearchInBook() async {
    final chapterIndex = await Navigator.push<int>(context, MaterialPageRoute(builder: (_) => SearchContentScreen(book: widget.book)));
    if (chapterIndex != null) _loadChapterContent(chapterIndex);
  }

  Future<void> _showTranslateDialog() async {
    final p = await SharedPreferences.getInstance();
    bool auto = p.getBool('translate_enabled') ?? false;
    const langs = ['zh-CN','zh-TW','en','ja','ko','fr','de','es','ru'];
    const names = {'zh-CN':'简体中文','zh-TW':'繁体中文','en':'英语','ja':'日语','ko':'韩语','fr':'法语','de':'德语','es':'西班牙语','ru':'俄语'};
    String target = p.getString('tr_target') ?? 'zh-CN';
    if (!mounted) return;
    await showDialog(context: context, builder: (dctx) => StatefulBuilder(builder: (dctx, setD) => AlertDialog(
      title: const Text('翻译设置'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        SwitchListTile(
          title: const Text('本章自动翻译'),
          value: auto,
          onChanged: (v) async { await p.setBool('translate_enabled', v); await TranslationService.instance.loadPrefs(); setD(() => auto = v); },
        ),
        ListTile(
          leading: const Icon(Icons.swap_horiz), title: const Text('目标语言'),
          trailing: DropdownButton<String>(value: target, items: langs.map((l) => DropdownMenuItem(value: l, child: Text(names[l] ?? l))).toList(),
            onChanged: (v) async { await p.setString('tr_target', v ?? 'zh-CN'); await TranslationService.instance.loadPrefs(); setD(() => target = v ?? 'zh-CN'); }),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('关闭')),
        FilledButton(onPressed: () async { Navigator.pop(dctx); await _translateCurrentChapter(); }, child: const Text('立即翻译本章')),
      ],
    )));
  }

  Future<void> _translateCurrentChapter() async {
    if ((_content ?? '').isEmpty) return;
    await TranslationService.instance.loadPrefs();
    if (mounted) setState(() => _isLoadingChapter = true);
    final translated = await TranslationService.instance.translateParagraphs(_content!);
    if (mounted) setState(() { _content = translated; _paginateContent(); _isLoadingChapter = false; });
  }

  void _showChapterSummary() {
    final summary = _chapters.isNotEmpty && _currentChapterIndex < _chapters.length ? _chapters[_currentChapterIndex].title : '无';
    showDialog(context: context, builder: (context) => AlertDialog(
      title: const Text('章节摘要'),
      content: Text('当前章节: $summary\n\n共${_chapters.length}章\n当前第${_currentChapterIndex + 1}章'),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
    ));
  }

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
            await _db.saveChapters(widget.book.name, widget.book.author, _chapters);
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
/* ===== 由 change_chapter_source_sheet.dart 合并 ===== */

/// 章节换源 - 对齐原版ChangeChapterSourceSheet
/// 列出可用书源，选择后用指定源重新加载章节
class ChangeChapterSourceSheet extends StatefulWidget {
  final String bookName;
  final String author;
  const ChangeChapterSourceSheet({super.key, required this.bookName, required this.author});

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
    final sources = await _db.getAllSources(enabled: true);
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

