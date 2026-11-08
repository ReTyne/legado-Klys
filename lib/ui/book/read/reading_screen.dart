
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_chapter.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/data/model/bookmark.dart';
import 'package:legado_md3/data/model/book_highlight.dart';
import 'package:legado_md3/data/model/db_models.dart';
import 'package:legado_md3/data/model/read_config.dart';
import 'package:legado_md3/di/book_provider.dart';
import 'package:legado_md3/ui/book/read/text_paginator.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';
import 'package:legado_md3/help/device/native_bridge.dart';
import 'package:legado_md3/help/storage/book_progress_sync.dart';
import 'package:legado_md3/ui/book/read/read_prefs.dart';
import 'package:legado_md3/ui/book/read/book_review_sheet.dart';
import 'package:legado_md3/ui/book/read/bottom_web_view_dialog.dart';
import 'package:legado_md3/ui/book/read/refresh_progress_sheet.dart';
import 'package:legado_md3/ui/book/read/pageestimate/page_estimator.dart';
import 'package:legado_md3/ui/book/read/pageestimate/whole_book_index.dart';
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
import 'package:legado_md3/ui/book/audio/bgm_panel.dart';
import 'package:legado_md3/ui/book/epub/epub_reader_screen.dart';
import 'package:legado_md3/ui/book/reader_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/ui/book/detail/book_detail_screen.dart';
import 'package:legado_md3/ui/book/read/config/reading_settings_screen.dart';
import 'package:legado_md3/ui/book/read/book_memo_dialog.dart';
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
part 'change_chapter_source_sheet.dart';


class ReadingScreen extends StatefulWidget {
  final Book book;
  final int? initialChapter;
  const ReadingScreen({super.key, required this.book, this.initialChapter});

  @override
  State<ReadingScreen> createState() => _ReadingScreenState();
}

class _ReadingScreenState extends State<ReadingScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
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
  // 系统电量读数（0-100）：由 NativeBridge.instance.batteryLevel 真实驱动
  // （原生 BatteryManager / battery_plus 通道），initState 监听后赋值；
  // 电量% 槽位显示真实百分比，电量图标按读数分段。
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

  /* ===== 第十轮 C 组：新增真实消费状态（全部只追加，不改动上方既有字段） ===== */
  // 电量/亮度：监听 NativeBridge 的 ValueNotifier，真实读数替代静态图标/假遮罩
  StreamSubscription<Map<dynamic, dynamic>>? _mediaButtonSub;
  bool _followSystemBrightness = false;
  double? _lastSystemBrightness;

  // 4 个额外阅读配置项（ReadPrefs 持久化，ReadConfig 归主代理独占，故不写模型）
  String _progressBarBehavior = 'chapter'; // 'page' | 'chapter'
  bool _showBrightnessView = true;
  bool _expandTextMenu = true;
  bool _mouseWheelPage = false;
  bool _twoFingerReplacePreview = false;
  bool _pageEstimateAuto = true;

  // 自定义翻页按键：{'prev': [...], 'next': [...]}，来自 ReadConfig.customPageKey JSON
  Map<String, List<String>> _customPageKeys = {};
  String? _customPageKeysRaw; // 上次解析的 customPageKey 原文，用于配置热更新
  int _lastKeyActionAt = 0; // 按键防抖（对齐 E keyPageOnLongPress 防抖）

  // 段评气泡计数 / 全书页数索引
  int _chapterReviewCount = 0;
  WholeBookPageIndex? _pageIndex;

  // 双指手势起始指针数与滚轮累计，供预览替换 / 滚轮翻页判定
  int _scalePointerCount = 0;
  bool _twoFingerDown = false;
  double _wheelAccum = 0;
  double _dragStartX = 0;
  double _dragDx = 0;

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
    if (mounted) {
      setState(() {
        _selectMenuOrder = sm;
        // 对齐 E book_read.xml checkable 菜单项：读取持久化的内容处理开关
        _reSegmentEnabled = p.getBool('read_reSegment') ?? false;
        _delRubyEnabled = p.getBool('read_delRuby') ?? false;
        _delHEnabled = p.getBool('read_delH') ?? false;
        _removeSameTitle = p.getBool('read_removeSameTitle') ?? false;
      });
    }
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
    // 第十轮：真实电量/亮度监听、额外配置项、媒体键、生命周期观察（来电暂停朗读）
    WidgetsBinding.instance.addObserver(this);
    _loadExtraPrefs();
    _initBatteryAndBrightness();
    _subscribeMediaButtons();
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
      _applyCustomPageKeys(cfg);
      _loadPageIndex();
    });
  }

  /* ================= 第十轮 C 组新增方法（追加，不改动既有逻辑） ================= */

  /// 读取不落在 ReadConfig 内的额外配置项（ReadPrefs）。
  Future<void> _loadExtraPrefs() async {
    final behavior = await ReadPrefs.getString(ReadPrefs.kProgressBarBehavior,
        fallback: 'chapter');
    final showBrightness =
        await ReadPrefs.getBool(ReadPrefs.kShowBrightnessView, fallback: true);
    final expandMenu =
        await ReadPrefs.getBool(ReadPrefs.kExpandTextMenu, fallback: true);
    final wheel =
        await ReadPrefs.getBool(ReadPrefs.kMouseWheelPage, fallback: false);
    final twoFinger = await ReadPrefs.getBool(
        ReadPrefs.kTwoFingerReplacePreview,
        fallback: false);
    final followSys = await ReadPrefs.getBool(
        ReadPrefs.kFollowSystemBrightness,
        fallback: false);
    final autoEstimate =
        await ReadPrefs.getBool(ReadPrefs.kPageEstimateAuto, fallback: true);
    if (!mounted) return;
    setState(() {
      _progressBarBehavior = behavior == 'page' ? 'page' : 'chapter';
      _showBrightnessView = showBrightness;
      _expandTextMenu = expandMenu;
      _mouseWheelPage = wheel;
      _twoFingerReplacePreview = twoFinger;
      _followSystemBrightness = followSys;
      _pageEstimateAuto = autoEstimate;
    });
  }

  /// 真实电量 + 跟随系统亮度：监听共享底座 ValueNotifier，拉取初值。
  void _initBatteryAndBrightness() {
    final bridge = NativeBridge.instance;
    bridge.batteryLevel.addListener(_onBatteryChanged);
    bridge.systemBrightness.addListener(_onSystemBrightnessChanged);
    _onBatteryChanged();
    bridge.refreshBattery();
    bridge.refreshBrightness().then((_) {
      if (_followSystemBrightness && mounted) _onSystemBrightnessChanged();
    });
  }

  void _onBatteryChanged() {
    final level = NativeBridge.instance.batteryLevel.value;
    if (mounted && _batteryLevel != level) setState(() => _batteryLevel = level);
  }

  void _onSystemBrightnessChanged() {
    final v = NativeBridge.instance.systemBrightness.value;
    if (v == _lastSystemBrightness) return;
    _lastSystemBrightness = v;
    if (!_followSystemBrightness || v == null || !mounted) return;
    // 系统亮度变化时同步应用内亮度状态（真实背光由原生通道处理）
    context.read<ReadProvider>().setBrightness(v.clamp(0.0, 1.0));
  }

  /// 真实亮度写入：跟随系统时调 setSystemBrightness / setWindowBrightness，
  /// 否则沿用阅读页的遮罩亮度（ReadProvider.brightness）。
  Future<void> _applyBrightness(double value, {bool system = false}) async {
    final v = value.clamp(0.0, 1.0);
    context.read<ReadProvider>().setBrightness(v);
    if (!_followSystemBrightness) return;
    final bridge = NativeBridge.instance;
    await bridge.setWindowBrightness(v);
    if (system) {
      final canWrite = await bridge.canWriteSettings();
      if (!canWrite) {
        await bridge.openWriteSettings();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('需授予「修改系统设置」权限才能跟随系统亮度')));
        }
      } else {
        await bridge.setSystemBrightness((v * 255).round());
      }
    }
  }

  /// 媒体按键（MediaSession）事件：mediaButtonPerNext 开启时 next/prev 切章。
  void _subscribeMediaButtons() {
    _mediaButtonSub = NativeBridge.instance.mediaButtonEvents.stream.listen((event) {
      if (!mounted) return;
      final cfg = context.read<ReadProvider>().config;
      final action = (event['action'] ?? '').toString();
      switch (action) {
        case 'next':
          cfg.mediaButtonPerNext ? _nextChapter() : _nextPage();
          break;
        case 'prev':
          cfg.mediaButtonPerNext ? _prevChapter() : _prevPage();
          break;
        case 'play':
          if (!_ttsService.isPlaying && !_ttsService.isPaused) _startTTS();
          break;
        case 'pause':
          if (_ttsService.isPlaying) _ttsService.pause();
          break;
      }
    });
  }

  /// 设置页改动 customPageKey 后返回阅读页，按键分发前即时重新解析。
  void _syncCustomPageKeys(ReadConfig cfg) {
    if (cfg.customPageKey != _customPageKeysRaw) _applyCustomPageKeys(cfg);
  }

  /// 解析 ReadConfig.customPageKey（JSON）为规范键名集合。
  void _applyCustomPageKeys(ReadConfig cfg) {
    final raw = cfg.customPageKey;
    _customPageKeysRaw = raw;
    if (raw == null || raw.trim().isEmpty) {
      _customPageKeys = {};
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        _customPageKeys = {
          'prev': (decoded['prev'] as List<dynamic>?)
                  ?.map((e) => '$e'.toLowerCase())
                  .toList() ??
              [],
          'next': (decoded['next'] as List<dynamic>?)
                  ?.map((e) => '$e'.toLowerCase())
                  .toList() ??
              [],
        };
      }
    } catch (_) {
      _customPageKeys = {};
    }
  }

  /// 把 LogicalKeyboardKey.keyLabel 归一化后与自定义键配置匹配。
  bool _matchCustomKey(String label, List<String> configured) {
    if (configured.isEmpty) return false;
    var norm = label
        .toLowerCase()
        .replaceAll(' ', '')
        .replaceAll('arrow', '')
        .replaceAll('key', '');
    // LogicalKeyboardKey.space.keyLabel 是单个空格，归一化后为空，映射到 'space'
    if (norm.isEmpty && label.isNotEmpty && label.trim().isEmpty) {
      norm = 'space';
    }
    for (final c in configured) {
      final k = c
          .replaceAll(' ', '')
          .replaceAll('arrow', '')
          .replaceAll('key', '');
      if (norm == k || norm.contains(k) || k.contains(norm)) return true;
    }
    return false;
  }

  /// 全书页数索引加载（v14 page_estimates）。
  Future<void> _loadPageIndex() async {
    final idx = await WholeBookPageIndex.load(
        widget.book.name, widget.book.author, _chapters.length);
    if (mounted) setState(() => _pageIndex = idx);
  }

  /// 章节加载后的附加工作：段评计数、页数估算、正文失效自动换源。
  Future<void> _postChapterLoaded(int index) async {
    await _loadChapterReviews();
    await _estimateChapterPages(index);
    await _maybeAutoChangeSource();
  }

  Future<void> _loadChapterReviews() async {
    try {
      final list = await _db.getBookReviews(
          widget.book.name, widget.book.author, _currentChapterIndex);
      if (mounted) setState(() => _chapterReviewCount = list.length);
    } catch (_) {}
  }

  /// 复用 TextPaginator 估算本章页数并落库（精确 / 启发式）。
  Future<void> _estimateChapterPages(int index) async {
    if (!_pageEstimateAuto || _chapters.isEmpty) return;
    final cfg = context.read<ReadProvider>().config;
    final w = _pageW;
    final h = _pageH;
    final chapter = _chapters[index];
    final result = ChapterPageEstimator.estimate(
      content: _content ?? chapter.content,
      config: cfg,
      // 后台估算用已测得的视口（不再在异步上下文读 MediaQuery）
      width: w ?? 0,
      height: h ?? 0,
    );
    final idx = _pageIndex ??
        await WholeBookPageIndex.load(
            widget.book.name, widget.book.author, _chapters.length);
    await idx.updateChapter(index, result.pages, result.mode);
    if (mounted) setState(() => _pageIndex = idx);
  }

  /// 有效文本宽度：双水平页按栏数折半、刘海屏 padding 扣减安全区。
  double _effectiveWidth(ReadConfig cfg, double rawW) {
    if (rawW <= 0) return rawW;
    // maybeOf：分页可能在异步回调中触发，避免 dispose 后读 MediaQuery 抛错
    final mq = MediaQuery.maybeOf(context);
    final cutout = cfg.paddingDisplayCutouts
        ? (mq?.padding ?? EdgeInsets.zero)
        : EdgeInsets.zero;
    var w = rawW - cutout.left - cutout.right;
    if (cfg.doubleHorizontalPage != 0) {
      final landscape = mq?.orientation == Orientation.landscape;
      if (cfg.doubleHorizontalPage == 1 || landscape) w /= 2;
    }
    return w > 0 ? w : rawW;
  }

  /// 有效文本高度：刘海屏上下安全区扣减。
  double _effectiveHeight(ReadConfig cfg, double rawH) {
    if (rawH <= 0) return rawH;
    final cutout = cfg.paddingDisplayCutouts
        ? (MediaQuery.maybeOf(context)?.padding ?? EdgeInsets.zero)
        : EdgeInsets.zero;
    final h = rawH - cutout.top - cutout.bottom;
    return h > 0 ? h : rawH;
  }

  /// 正文失效且 autoChangeSource 开启时，自动跨源检索并换源重载。
  Future<void> _maybeAutoChangeSource() async {
    final cfg = context.read<ReadProvider>().config;
    if (!cfg.autoChangeSource || widget.book.local) return;
    final c = _content;
    final invalid = c == null ||
        c.trim().isEmpty ||
        c == '加载失败，请检查网络' ||
        c.startsWith('读取本地文件失败');
    if (!invalid) return;
    try {
      final sources = await _db.getAllSources(enabled: true);
      final others = sources
          .where((s) => s.bookSourceUrl != widget.book.origin)
          .toList();
      for (final s in others) {
        final err = await _changeChapterSource(s);
        if (err == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('正文失效，已自动换源到「${s.bookSourceName}」')));
          }
          return;
        }
      }
    } catch (_) {}
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
    // 第十轮：解除共享底座监听与生命周期观察
    _mediaButtonSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    NativeBridge.instance.batteryLevel.removeListener(_onBatteryChanged);
    NativeBridge.instance.systemBrightness
        .removeListener(_onSystemBrightnessChanged);
    // 恢复系统 UI 与屏幕方向
    try {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    } catch (_) {}
    super.dispose();
  }

  /// 来电 / 切后台时按 pauseReadAloudWhilePhoneCalls 暂停朗读。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.paused &&
        state != AppLifecycleState.hidden) {
      return;
    }
    try {
      if (context.read<ReadProvider>().config.pauseReadAloudWhilePhoneCalls &&
          _ttsService.isPlaying) {
        _ttsService.pause();
      }
    } catch (_) {}
  }

  /// 统一按键分发：在原有音量键翻页基础上接入
  /// volumeKeyPageOnPlay / keyPageOnLongPress / customPageKey / 按键防抖。
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final cfg = context.read<ReadProvider>().config;
    _syncCustomPageKeys(cfg);
    final now = DateTime.now().millisecondsSinceEpoch;
    final isDown = event is KeyDownEvent;
    final isRepeat = event is KeyRepeatEvent;

    // 自定义翻页按键（ReadConfig.customPageKey JSON）
    if (_customPageKeys.isNotEmpty && (isDown || isRepeat)) {
      final label = event.logicalKey.keyLabel;
      if (_matchCustomKey(label, _customPageKeys['next'] ?? const [])) {
        if (now - _lastKeyActionAt > 120) {
          _lastKeyActionAt = now;
          _nextPage();
        }
        return KeyEventResult.handled;
      }
      if (_matchCustomKey(label, _customPageKeys['prev'] ?? const [])) {
        if (now - _lastKeyActionAt > 120) {
          _lastKeyActionAt = now;
          _prevPage();
        }
        return KeyEventResult.handled;
      }
    }

    // 音量键：常规开关，或「朗读播放时音量键也翻页」
    final allowVolume = cfg.volumeKeyPage ||
        (cfg.volumeKeyPageOnPlay &&
            (_ttsService.isPlaying || _ttsService.isPaused));
    final up = event.physicalKey == PhysicalKeyboardKey.audioVolumeUp;
    final down = event.physicalKey == PhysicalKeyboardKey.audioVolumeDown;
    if (allowVolume && (up || down)) {
      // keyPageOnLongPress 开启时短按不翻页，仅长按重复事件连续翻页
      final fire = cfg.keyPageOnLongPress ? isRepeat : isDown;
      if (fire) {
        final goNext = cfg.volumeKeyReverse ? up : !up;
        goNext ? _nextPage() : _prevPage();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// 鼠标/触控板滚轮翻页（mouseWheelPage）。
  void _onPointerSignal(PointerSignalEvent event) {
    if (!_mouseWheelPage || event is! PointerScrollEvent) return;
    _wheelAccum += event.scrollDelta.dy;
    if (_wheelAccum.abs() < 40) return;
    _wheelAccum > 0 ? _nextPage() : _prevPage();
    _wheelAccum = 0;
  }

  /// 双指点击预览替换（Listener 不与 GestureDetector 竞争手势竞技场）。
  void _onPointerDown(PointerDownEvent event) {
    _scalePointerCount++;
    if (_scalePointerCount >= 2) _twoFingerDown = true;
    _dragStartX = event.position.dx;
    _dragDx = 0;
  }

  void _onPointerMove(PointerMoveEvent event) {
    _dragDx = event.position.dx - _dragStartX;
  }

  void _onPointerUp(PointerUpEvent event) {
    _scalePointerCount = (_scalePointerCount - 1).clamp(0, 99);
    if (_twoFingerDown && _scalePointerCount == 0) {
      _twoFingerDown = false;
      if (_twoFingerReplacePreview) unawaited(_previewReplaceTwoFinger());
    }
    // pageTouchSlop：滚动模式下用水平拖动翻页，数值越大阈值越高（越迟钝）。
    // 仅在滚动模式生效，避免与 PageView 自带水平滑动手势重复翻页。
    try {
      final cfg = context.read<ReadProvider>().config;
      if (cfg.pageTouchSlop > 0 && cfg.pageAnim == 3) {
        final threshold = cfg.pageTouchSlop * 8.0 + 24.0;
        if (_dragDx.abs() > threshold) {
          _dragDx > 0 ? _prevPage() : _nextPage();
        }
      }
    } catch (_) {}
    _dragDx = 0;
  }

  /// 双指预览：显示当前页经过「生效替换规则」后的效果。
  Future<void> _previewReplaceTwoFinger() async {
    final src = _pages.isNotEmpty
        ? _pages[_currentPage.clamp(0, _pages.length - 1)]
        : (_content ?? '');
    if (src.trim().isEmpty || !mounted) return;
    final rules = await _db.getReplaceRules();
    final enabled = rules.where((r) => r.enable == true).toList();
    final out = enabled.isEmpty
        ? src
        : ReplaceRuleService().applyRules(src, enabled);
    if (!mounted) return;
    final cs = Theme.of(context).colorScheme;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('双指预览 · 替换效果'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('原文', style: TextStyle(fontSize: 12, color: cs.primary)),
                const SizedBox(height: 4),
                Text(src, style: const TextStyle(fontSize: 13)),
                const Divider(height: 16),
                Text('结果（${enabled.length} 条规则）',
                    style: TextStyle(fontSize: 12, color: cs.primary)),
                const SizedBox(height: 4),
                Text(out, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  /// adaptSpecialStyle：特殊样式适配时启用 CJK 排版特性（liga/kern/palt）。
  List<FontFeature>? _fontFeatures(ReadConfig config) {
    final features = <FontFeature>[];
    if (!_antiAlias) {
      features.addAll(const [
        FontFeature.disable('kern'),
        FontFeature.disable('liga'),
      ]);
    }
    if (config.adaptSpecialStyle) {
      features.addAll(const [
        FontFeature.enable('kern'),
        FontFeature.enable('liga'),
        FontFeature.enable('palt'),
      ]);
    }
    return features.isEmpty ? null : features;
  }

  /* ===== 第十轮：刷新三档 / 云进度 / 章节摘要 / 交互网页 / 段评 / 页数 / 亮度 ===== */

  /// 刷新三档（目录 / 当前章 / 全文），由 RefreshProgressSheet 注入调用，真实清缓存重载。
  Future<void> _onRefreshScope(RefreshScope scope) async {
    if (_chapters.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    switch (scope) {
      case RefreshScope.chapter:
        await _refreshCurrentChapter();
        break;
      case RefreshScope.all:
        for (var i = _currentChapterIndex; i < _chapters.length; i++) {
          await _db.updateChapterContent(
              widget.book.name, widget.book.author, i, '');
        }
        await _loadChapterContent(_currentChapterIndex,
            targetPage: _currentPage);
        messenger.showSnackBar(const SnackBar(
            content: Text('已刷新全文：清理当前章及之后全部缓存')));
        break;
      case RefreshScope.toc:
        await _fetchTocFromNetwork();
        for (var i = 0; i < _chapters.length; i++) {
          await _db.updateChapterContent(
              widget.book.name, widget.book.author, i, '');
        }
        if (_chapters.isNotEmpty) {
          await _loadChapterContent(
              _currentChapterIndex.clamp(0, _chapters.length - 1),
              targetPage: _currentPage);
        }
        messenger.showSnackBar(
            const SnackBar(content: Text('已刷新目录与全文缓存')));
        break;
    }
    await _loadPageIndex();
  }

  /// 云进度拉取后把本地书籍对象与阅读定位同步到较新的远端进度。
  Future<void> _onProgressPulled(int changed) async {
    if (changed <= 0) return;
    final updated = await _db.getBook(widget.book.name, widget.book.author);
    if (updated == null || !mounted) return;
    widget.book
      ..durChapterIndex = updated.durChapterIndex
      ..durChapterPos = updated.durChapterPos;
    final target = updated.durChapterIndex.clamp(
        0, _chapters.isEmpty ? 0 : _chapters.length - 1);
    await _loadChapterContent(target, targetPage: updated.durChapterPos);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('已按云端进度定位到最新章节'),
          duration: Duration(seconds: 2)));
    }
  }

  void _openRefreshProgressSheet() {
    unawaited(RefreshProgressSheet.open(
      context,
      bookName: widget.book.name,
      author: widget.book.author,
      onRefresh: _onRefreshScope,
      onProgressPulled: _onProgressPulled,
    ));
  }

  /// 更多菜单直接入口：获取云进度（真实拉取 + SnackBar）
  Future<void> _pullCloudProgress() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final n = await BookProgressSync.instance.pull();
      await _onProgressPulled(n);
      messenger.showSnackBar(SnackBar(
          content: Text(
              n > 0 ? '已拉取 $n 本书的云端进度' : '云端暂无更新进度')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('获取云进度失败：$e')));
    }
  }

  /// 更多菜单直接入口：覆盖云进度（真实上传 + SnackBar）
  Future<void> _pushCloudProgress() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ok = await BookProgressSync.instance.push();
      messenger.showSnackBar(SnackBar(
          content: Text(ok
              ? '已覆盖上传本地全部书籍进度'
              : '覆盖云进度失败，请检查 WebDAV 配置')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('覆盖云进度失败：$e')));
    }
  }

  /// 第十轮追加菜单项的统一构建（不触碰 E 固定 overflow 列表）
  Widget _extraMenuItem(
          BuildContext ctx, IconData icon, String title, VoidCallback onTap) =>
      ListTile(
        dense: true,
        leading: Icon(icon, size: 20),
        title: Text(title),
        onTap: () {
          Navigator.pop(ctx);
          onTap();
        },
      );

  /// 切换 EPUB 阅读方式（文本阅读器 ↔ 保版式 WebView 阅读器），
  /// 持久化到 `ui_epubLayoutReader` 并立即重建阅读页，让路由分流生效。
  Future<void> _toggleEpubReaderMode(BuildContext context) async {
    final next = !useEpubLayoutReader;
    useEpubLayoutReader = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('ui_epubLayoutReader', next);
    if (!context.mounted) return;
    if (next) {
      // 文本阅读器 → 保版式：直接用 EpubReaderScreen 替换当前路由。
      await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (_) => EpubReaderScreen(
          book: widget.book,
          initialChapter: _currentChapterIndex,
        ),
      ));
    } else {
      // 保版式 → 文本阅读器：由全局开关控制，重新进入阅读页即可分流到文本。
      // 这里刷新当前页以提示用户下次进入生效，避免破坏正在运行的播放器。
      if (mounted) setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('已切换为文本阅读方式，重新进入阅读页后生效'),
      ));
    }
  }

  /// 章节摘要在 kv_caches 表的持久化键（v14 表已就绪，不改主代理模型）。
  String get _chapterSummaryKey =>
      'chapter_summary_${widget.book.name}_${widget.book.author}_$_currentChapterIndex';

  /// 从章节内容提取真实摘要：首段优先，退化到去空白后的前 N 字。
  static String _extractSummary(String content) {
    final paragraphs = content
        .split(RegExp(r'\n+'))
        .where((p) => p.trim().isNotEmpty)
        .toList();
    final first = paragraphs.isNotEmpty ? paragraphs.first.trim() : '';
    final base = first.isNotEmpty
        ? first
        : content.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (base.isEmpty) return '（本章暂无正文内容）';
    return base.length > 120 ? '${base.substring(0, 120)}…' : base;
  }

  /// 章节摘要弹窗：真实摘要（可编辑保存）+ 章名 + 阅读进度。
  Future<void> _showChapterSummary() async {
    final saved = await _db.getKvCache(_chapterSummaryKey);
    final auto = _extractSummary(_content ?? '');
    final controller = TextEditingController(
        text: (saved != null && saved.isNotEmpty) ? saved : auto);
    if (!mounted) return;
    final cs = Theme.of(context).colorScheme;
    final title = _chapters.isNotEmpty
        ? _chapters[_currentChapterIndex].title
        : widget.book.name;
    final chapterTotal = _chapters.isEmpty ? 1 : _chapters.length;
    final progress =
        '第 ${_currentChapterIndex + 1}/$chapterTotal 章 · 第 ${_currentPage + 1}/${_pages.length} 页 · ${_bookProgress.toStringAsFixed(1)}%';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(progress,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              const SizedBox(height: 12),
              Text('章节摘要（从正文自动提取，可编辑保存）',
                  style: TextStyle(fontSize: 12, color: cs.primary)),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                maxLines: 6,
                decoration: const InputDecoration(
                  hintText: '输入本章摘要…',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              await _db.setKvCache(_chapterSummaryKey, controller.text.trim());
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('章节摘要已保存')));
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  /// 书源登录 / 章节购买 / 验证码：响应式底部 WebView 弹窗入口。
  Future<void> _showInteractiveWeb() async {
    var url = _chapters.isNotEmpty
        ? _chapters[_currentChapterIndex].url
        : '';
    if (url.isEmpty) {
      url = widget.book.bookUrl ?? widget.book.noteUrl ?? '';
    }
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('当前章节与书籍均无可用链接')));
      return;
    }
    final html = await BottomWebViewDialog.show(
      context,
      url: url,
      title: '书源交互（登录 / 购买 / 验证码）',
    );
    if (html != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('已回传页面 HTML（${html.length} 字符），可用于书源登录态解析')));
    }
  }

  /// 阅读设置按 sheet 分层组织（不改既有整页设置入口）。
  void _showSettingsSections() =>
      showReaderSettingsSectionsSheet(context, book: widget.book);

  /// 多套排版预设保存 / 切换（v14 read_presets）。
  void _showReadPresets() => unawaited(ReadPresetSheet.open(context));

  /// 打开段评面板（当前页段落），发表/点赞后刷新气泡计数。
  Future<void> _openReviewSheet() async {
    final pageText = _pages.isNotEmpty
        ? _pages[_currentPage.clamp(0, _pages.length - 1)]
        : (_content ?? '');
    final paragraphs = pageText
        .split(RegExp(r'\n+'))
        .where((p) => p.trim().isNotEmpty)
        .toList();
    final dirty = await BookReviewSheet.open(
      context,
      bookName: widget.book.name,
      author: widget.book.author,
      chapterIndex: _currentChapterIndex,
      chapterTitle: _chapters.isNotEmpty
          ? _chapters[_currentChapterIndex].title
          : widget.book.name,
      paragraphs: paragraphs.isEmpty ? const ['全文'] : paragraphs,
    );
    if (dirty) await _loadChapterReviews();
  }

  /// 正文每页右下角段评气泡（对齐 Sigma ReviewColumn）。
  Widget _reviewOverlay(ReadConfig config) {
    return Positioned(
      right: config.paddingRight.toDouble() + 8,
      bottom: 12,
      child: ReviewColumn(
        count: _chapterReviewCount,
        foreground: Color(config.textColor),
        onTap: _openReviewSheet,
        onLongPress: _openReviewSheet,
      ),
    );
  }

  /// 「本章 X 页 / 全书约 Y 页」+ 按页数校准的进度。
  Widget _buildPageEstimateRow(Color fg) {
    final idx = _pageIndex;
    if (idx == null) return const SizedBox.shrink();
    final pct =
        (idx.calibratedProgress(_currentChapterIndex, _currentPage) * 100)
            .toStringAsFixed(1);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Icon(Icons.menu_book_outlined, size: 14, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${idx.summary(_currentChapterIndex)} · 已读 $pct%',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: fg, fontSize: 12),
            ),
          ),
          IconButton(
            tooltip: '重新估算全书页数',
            icon: Icon(Icons.calculate_outlined, size: 18, color: fg),
            onPressed: () async {
              await idx.clear();
              await _estimateChapterPages(_currentChapterIndex);
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
    );
  }

  /// 真实亮度行（showBrightnessView）+「跟随系统亮度」开关 + 真实电量读数。
  Widget _buildBrightnessSystemRow(Color fg) {
    final rp = context.read<ReadProvider>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.brightness_6_outlined, size: 18, color: fg),
              const SizedBox(width: 8),
              Text('跟随系统亮度', style: TextStyle(color: fg, fontSize: 13)),
              Switch(
                value: _followSystemBrightness,
                onChanged: (v) async {
                  setState(() => _followSystemBrightness = v);
                  await ReadPrefs.setBool(
                      ReadPrefs.kFollowSystemBrightness, v);
                  if (v) await _applyBrightness(rp.brightness, system: true);
                },
              ),
              const Spacer(),
              if (_batteryLevel != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_batteryIcon(_batteryLevel), size: 14, color: fg),
                    const SizedBox(width: 4),
                    Text('$_batteryLevel%',
                        style: TextStyle(color: fg, fontSize: 12)),
                  ],
                ),
            ],
          ),
          Slider(
            value: rp.brightness.clamp(0.0, 1.0),
            onChanged: (v) => _applyBrightness(v),
            onChangeEnd: (v) => _applyBrightness(v, system: true),
          ),
        ],
      ),
    );
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
      final source = sources
          .where((s) => s.bookSourceUrl == widget.book.origin)
          .firstOrNull;
      if (source == null) return;

      // legado 约定：目录地址 = noteUrl，为空时回退 bookUrl。旧实现要求
      // noteUrl 非空才取目录，从书架/继续阅读进入的书（noteUrl 为空但
      // bookUrl 有效）会永远补不到目录，连带正文也取不到。
      final bookUrl = widget.book.bookUrl ?? '';
      final noteUrl = (widget.book.noteUrl ?? '').isNotEmpty
          ? widget.book.noteUrl!
          : bookUrl;
      if (noteUrl.isEmpty) return;

      widget.book.noteUrl = noteUrl; // 回写，供正文加载 / 换源复用
      var chapters = await _engine.getToc(source, noteUrl,
          bookInfo: widget.book.jsContext());
      // 独立 tocUrl 取不到章节时，回退用书址本身再取一次
      if (chapters.isEmpty && bookUrl.isNotEmpty && bookUrl != noteUrl) {
        chapters = await _engine.getToc(source, bookUrl,
            bookInfo: widget.book.jsContext());
        if (chapters.isNotEmpty) widget.book.noteUrl = bookUrl;
      }
      if (chapters.isNotEmpty) {
        _chapters = chapters;
        await _db.saveChapters(widget.book.name, widget.book.author, chapters);
        await _db.updateBook(widget.book);
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
          } else {
            _content = '正文规则未匹配到内容（该书源 content 规则可能不适配，或需要登录会话）';
          }
        } else if (chapter.url.isEmpty) {
          _content = '章节地址为空，无法获取正文（目录规则可能未解析出章节链接）';
        } else {
          _content = '未找到匹配的书源（可能已被禁用或删除），无法获取正文，请到书源管理重新启用';
        }
      } catch (e) {
        _content = '正文获取失败：${e.toString().split('\n').first}';
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
    // 第十轮：章节加载后的附加工作（不阻塞阅读主流程）
    unawaited(_postChapterLoaded(index));
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
      // 真实分页：按实际可用宽高与正文样式逐行测量。
      // 接分支：doubleHorizontalPage / paddingDisplayCutouts 影响有效视口。
      final effW = _effectiveWidth(config, w);
      final effH = _effectiveHeight(config, h);
      final pages = TextPaginator.paginate(
        paragraphs: paragraphs,
        indent: indent,
        paraGapLines: config.paragraphSpacing < 0 ? 0 : config.paragraphSpacing,
        maxWidth: effW,
        maxHeight: effH,
        style: _textStyle(config),
        // readBodyToLh：正文带到行高时，段间空行计入页高消耗
        gapLinesConsumeHeight: config.readBodyToLh,
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
    // noAnimScrollPage：滚动模式下代码跳页也不做动画（对齐 E）
    final noAnim =
        config.pageAnim == 4 || (config.pageAnim == 3 && config.noAnimScrollPage);
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
    // noAnimScrollPage：滚动模式下代码跳页也不做动画（对齐 E）
    final noAnim =
        config.pageAnim == 4 || (config.pageAnim == 3 && config.noAnimScrollPage);
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
    // 同步写入独立划线表，供目录页第 3 个「高亮」Tab 展示与跳转。
    // 两处共用同一次选中文本，避免「书籍标记」与「高亮」数据分叉。
    await _db.insertBookHighlight(BookHighlight(
      bookName: widget.book.name,
      author: widget.book.author,
      chapterIndex: _currentChapterIndex,
      chapterTitle: marking.chapterTitle,
      content: t,
      start: _currentPage,
      end: _currentPage,
      createTime: marking.createTime,
    ));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已添加划线，可在 目录-高亮 或 我的-书籍标记 查看'), duration: Duration(seconds: 2)));
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
      onKeyEvent: _handleKeyEvent,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Color(config.bgColor),
          statusBarIconBrightness: ThemeData.estimateBrightnessForColor(Color(config.bgColor)) == Brightness.dark
              ? Brightness.light
              : Brightness.dark,
        ),
        child: Scaffold(
          backgroundColor: Color(config.bgColor),
          body: Listener(
            onPointerSignal: _onPointerSignal,
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            child: _isLoading
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
                      // 亮度调节：跟随系统亮度时由原生通道真实改背光，不再画假遮罩；
                      // 关闭跟随系统时保留原有遮罩（不拦截点击）。
                      if (!_followSystemBrightness && readProvider.brightness < 1.0)
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
      // 接分支：_antiAlias 原逻辑保留，adaptSpecialStyle 开启时启用 CJK 排版特性
      fontFeatures: _fontFeatures(config),
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
        // optimizeRender：开启时额外隔离整页（含动画层）重绘
        Widget wrap(Widget w) =>
            config.optimizeRender ? RepaintBoundary(child: w) : w;
        // 覆盖 / 仿真：动画层只包住当前页项，静态页内容作为 child 不参与每帧重建
        if (!cover && !simulate) return wrap(item);
        return wrap(_PageAnimLayer(
          controller: _pageController,
          fallbackPage: _currentPage,
          index: index,
          advance: advance,
          vertical: isVertical,
          simulate: simulate,
          child: item,
        ));
      },
    );
  }

  /// 单页内容（含长按选择）；最外层 RepaintBoundary 隔离翻页时的逐页重绘
  Widget _pageItem(ReadConfig config, int index) {
    final child = _pageText(config, index);
    // 第十轮：外层 Stack 只追加段评气泡，原有正文渲染 / 长按选择逻辑完全保留
    return Stack(
      children: [
        RepaintBoundary(
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
        ),
        _reviewOverlay(config),
      ],
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
    // 电量图标槽位：有真实读数时按电量分段显示对应图标；无读数时回退满电图标
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
          IconButton(tooltip: '更多', icon: const Icon(Icons.more_vert), onPressed: _showMoreMenu),
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
    // progressBarBehavior：'page' 章内按页拖动 / 'chapter' 按章拖动
    final pageMode = _progressBarBehavior == 'page';
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
            // 接分支：progressBarBehavior='page' 时滑块控制章内页，否则保持原按章行为
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: pageMode ? '上一页' : '上一章',
                    icon: Icon(Icons.skip_previous, color: barFg),
                    onPressed: pageMode
                        ? (_currentPage > 0 ? () => _prevPage() : null)
                        : (_currentChapterIndex > 0
                            ? () => _loadChapterContent(_currentChapterIndex - 1)
                            : null),
                  ),
                  Expanded(
                    child: Slider(
                      activeColor: barFg,
                      value: pageMode
                          ? (_pages.length <= 1
                              ? 0
                              : _currentPage / (_pages.length - 1))
                          : (_chapters.length <= 1
                              ? 0
                              : (_dragChapterIndex ?? _currentChapterIndex) /
                                  (_chapters.length - 1)),
                      // 拖动中只更新局部状态，不触发章节加载/落库/重排
                      onChanged: pageMode
                          ? (_pages.length <= 1
                              ? null
                              : (value) {
                                  final p =
                                      (value * (_pages.length - 1)).round();
                                  if (p != _currentPage) {
                                    setState(() => _currentPage = p);
                                  }
                                })
                          : (_chapters.length <= 1
                              ? null
                              : (value) {
                                  final index =
                                      (value * (_chapters.length - 1)).round();
                                  if (index !=
                                      (_dragChapterIndex ??
                                          _currentChapterIndex)) {
                                    setState(() => _dragChapterIndex = index);
                                  }
                                }),
                      // 松手才加载章节 / 跳页（加载内部完成进度保存与重排）
                      onChangeEnd: pageMode
                          ? (_pages.length <= 1
                              ? null
                              : (value) {
                                  final p =
                                      (value * (_pages.length - 1)).round();
                                  _currentPage = p.clamp(0, _pages.length - 1);
                                  if (_pageController.hasClients) {
                                    _pageController.jumpToPage(_currentPage);
                                  }
                                  _saveCurrentProgress();
                                  setState(() {});
                                })
                          : (_chapters.length <= 1
                              ? null
                              : (value) {
                                  final index =
                                      (value * (_chapters.length - 1)).round();
                                  setState(() => _dragChapterIndex = index);
                                  _loadChapterContent(index).whenComplete(() {
                                    if (mounted) {
                                      setState(() => _dragChapterIndex = null);
                                    }
                                  });
                                }),
                    ),
                  ),
                  IconButton(
                    tooltip: pageMode ? '下一页' : '下一章',
                    icon: Icon(Icons.skip_next, color: barFg),
                    onPressed: pageMode
                        ? (_currentPage < _pages.length - 1
                            ? () => _nextPage()
                            : null)
                        : (_currentChapterIndex < _chapters.length - 1
                            ? () => _loadChapterContent(_currentChapterIndex + 1)
                            : null),
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
                  IconButton(tooltip: '减小字号', icon: Icon(Icons.remove_circle_outline, color: barFg), onPressed: () => readProvider.setTextSize(config.textSize - 1)),
                  Text('${config.textSize}', style: TextStyle(color: barFg)),
                  IconButton(tooltip: '增大字号', icon: Icon(Icons.add_circle_outline, color: barFg), onPressed: () => readProvider.setTextSize(config.textSize + 1)),
                  const Spacer(),
                  Text('行距', style: TextStyle(color: barFg)),
                  IconButton(tooltip: '减小行距', icon: Icon(Icons.remove_circle_outline, color: barFg), onPressed: () => readProvider.setLineSpacing(config.lineSpacing - 1)),
                  Text('${config.lineSpacing}', style: TextStyle(color: barFg)),
                  IconButton(tooltip: '增大行距', icon: Icon(Icons.add_circle_outline, color: barFg), onPressed: () => readProvider.setLineSpacing(config.lineSpacing + 1)),
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
            // 对齐 E view_read_menu.xml ll_bottom_bg 的五个主按钮：
            // 目录 / 朗读 / 界面 / 设置 / 备忘（ll_memo，§3.B3）
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildBottomAction(Icons.list_alt, '目录', barFg, _showChapterList),
                  _buildReadAloudAction(barFg),
                  _buildBottomAction(Icons.text_format, '界面', barFg, _showInterfaceSettings),
                  _buildBottomAction(Icons.settings, '设置', barFg, _showReadingSettings),
                  _buildBottomAction(Icons.note_alt_outlined, '备忘', barFg, _showBookMemo),
                ],
              ),
            ),
            // 第十轮：真实亮度视图（跟随系统亮度开关 + 真实电量）与全书页数估算
            const AppSectionHeader('设备与页数'),
            if (_showBrightnessView) _buildBrightnessSystemRow(barFg),
            _buildPageEstimateRow(barFg),
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

  /// 对齐 E menu_image_style：图片样式（真实消费 clickImgWay 配置）
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

  /// 对齐 E view_read_menu.xml ll_memo → BookMemoDialog：
  /// 按「书 + 章」编辑备忘（feature_gap §3.B3）。
  void _showBookMemo() {
    final chapterTitle =
        (_chapters.isNotEmpty && _currentChapterIndex < _chapters.length)
            ? _chapters[_currentChapterIndex].title
            : '';
    showBookMemoDialog(
      context,
      bookName: widget.book.name,
      author: widget.book.author,
      chapterIndex: _currentChapterIndex,
      chapterTitle: chapterTitle,
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
                // ===== 第十轮 C 组追加（只追加，不删改 E 固定 overflow 项） =====
                const Divider(height: 1),
                _extraMenuItem(ctx, Icons.summarize_outlined, '章节摘要（真实正文）',
                    _showChapterSummary),
                _extraMenuItem(ctx, Icons.mode_comment_outlined, '段评 / 本章评论',
                    _openReviewSheet),
                _extraMenuItem(ctx, Icons.refresh_outlined, '刷新当前章节',
                    () => _onRefreshScope(RefreshScope.chapter)),
                _extraMenuItem(ctx, Icons.auto_stories_outlined,
                    '刷新全文（当前章及其后）',
                    () => _onRefreshScope(RefreshScope.all)),
                _extraMenuItem(ctx, Icons.list_alt_outlined, '刷新目录',
                    () => _onRefreshScope(RefreshScope.toc)),
                _extraMenuItem(ctx, Icons.sync_outlined, '刷新与云进度面板',
                    _openRefreshProgressSheet),
                _extraMenuItem(ctx, Icons.cloud_download_outlined, '获取云进度',
                    _pullCloudProgress),
                _extraMenuItem(ctx, Icons.cloud_upload_outlined, '覆盖云进度',
                    _pushCloudProgress),
                _extraMenuItem(ctx, Icons.public_outlined,
                    '交互网页（登录 / 购买 / 验证码）', _showInteractiveWeb),
                _extraMenuItem(ctx, Icons.layers_outlined, '阅读设置分区',
                    _showSettingsSections),
                _extraMenuItem(ctx, Icons.style_outlined,
                    '排版预设（保存 / 切换）', _showReadPresets),
                _extraMenuItem(ctx, Icons.calculate_outlined, '重新估算全书页数',
                    () async {
                  final idx = _pageIndex;
                  if (idx != null) {
                    await idx.clear();
                    await _estimateChapterPages(_currentChapterIndex);
                    if (mounted) setState(() {});
                  }
                }),
                // ===== 第十轮主代理接线：BGM 背景音乐 / EPUB 阅读方式切换 =====
                _extraMenuItem(ctx, Icons.music_note_outlined, '背景音乐（BGM）',
                    () => showBgmPanel(context)),
                if (EpubReaderScreen.canOpen(widget.book))
                  _extraMenuItem(ctx, Icons.auto_stories_outlined,
                      useEpubLayoutReader ? '切换为文本阅读' : '切换为 EPUB 保版式阅读',
                      () => _toggleEpubReaderMode(context)),
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
    // expandTextMenu：展开全部动作，折叠时仅保留常用 4 项
    final order = _expandTextMenu
        ? _selectMenuOrder
        : _selectMenuOrder.take(4).toList();
    for (final key in order) {
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('朗读失败，请检查 TTS 引擎设置')));
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
          Text('原文：$text', style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
          Text('原文：$text', style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
            Text(head, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text('暂无书签',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
                        tooltip: '删除书签',
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
              // 跟随系统亮度时实时写真实背光（不画假遮罩）
              if (_followSystemBrightness) {
                NativeBridge.instance.setWindowBrightness(value);
              }
            },
            // 松手才持久化并通知阅读界面生效（真实亮度由原生通道落地）
            onChangeEnd: (value) {
              _applyBrightness(value, system: true);
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
  // 故移除历史空实现对话框；划词翻译（_translateSelection）仍由文本选择菜单提供。

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
    final cfg = context.read<ReadProvider>().config;
    // sysTtsConfig：跟随系统 TTS 偏好（tts_rate / tts_pitch）
    if (cfg.sysTtsConfig) await _ttsService.loadPrefs();
    // ttsFlowSys：关闭时使用固定语速，不再套用用户偏好
    if (!cfg.ttsFlowSys) await _ttsService.setRate(1.0);
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
    // readAloudByPage：按页朗读（复用真实分页结果）；
    // streamReadAloudAudio：流式朗读按句切成细片段边合成边播；
    // 两者关闭时保持原「按章朗读」链路。
    if (cfg.readAloudByPage) {
      _ttsService.setTextSegments(_pages, startIndex: _currentPage);
    } else if (cfg.streamReadAloudAudio) {
      final segments = (_content ?? '')
          .split(RegExp(r'(?<=[。！？；!?;])'))
          .where((s) => s.trim().isNotEmpty)
          .toList();
      _ttsService.setTextSegments(
          segments.isEmpty ? _pages : segments, startIndex: 0);
    } else {
      _ttsService.setChapters(_chapters, startIndex: _currentChapterIndex);
    }
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

