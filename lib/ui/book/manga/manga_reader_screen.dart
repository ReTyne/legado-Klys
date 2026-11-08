import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_chapter.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/help/source/source_engine.dart';
import 'package:legado_md3/help/storage/book_progress_sync.dart';
import 'package:legado_md3/help/translate/manga_translate_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 当前翻页模式的总页数：单页=图片数；双页=相邻两页拼一屏（ceil(n/2)）。
/// 补齐双页拼合（对齐 E 的漫画双页阅读），抽成顶层纯函数便于离线单测。
int mangaPageCount(int imageCount, bool doublePage) =>
    doublePage ? (imageCount + 1) ~/ 2 : imageCount;

/// 双页模式第 [pageIndex] 屏对应的图片下标：正常两张 [左, 右]，奇数张时最后一屏仅 [左]。
/// 补齐双页拼合（对齐 E 的漫画双页阅读），抽成顶层纯函数便于离线单测。
List<int> mangaDoublePageIndices(int pageIndex, int imageCount) {
  final left = 2 * pageIndex;
  if (left >= imageCount) return const [];
  return left + 1 < imageCount ? [left, left + 1] : [left];
}

/// 漫画阅读器（图片书源 / 条漫）。
///
/// 图片获取策略（增量修复）：
/// 1. 先解析章节缓存 `chapter.content` 中的 `<img src>`（兼容旧缓存/本地漫画）；
/// 2. 缓存为空时调用书源引擎 `BookSourceEngine.getImageContent` 拉取图片 URL 列表，
///    并写回 `chapter.content` 缓存，下次阅读走本地缓存。
class MangaReaderScreen extends StatefulWidget {
  final Book book;
  final int initialChapter;
  const MangaReaderScreen({super.key, required this.book, this.initialChapter = 0});

  @override
  State<MangaReaderScreen> createState() => _MangaReaderScreenState();
}

class _MangaReaderScreenState extends State<MangaReaderScreen> {
  final DatabaseService _db = DatabaseService();
  // 书源引擎：用于拉取网络漫画的图片列表
  final BookSourceEngine _engine = BookSourceEngine();
  List<BookChapter> _chapters = [];
  int _currentChapter = 0;
  bool _loading = true;
  bool _showMenu = false;

  // ==================== 漫画配置（manga_config_screen 写入的 prefs 键） ====================
  int _scrollMode = 0;      // manga_scrollMode：0 条漫(纵向连续) 1 横向翻页 2 双页(相邻两页拼一屏)
  bool _gray = false;       // manga_gray：灰度模式
  bool _eink = false;       // manga_eink：墨水屏优化
  bool _hideTitle = false;  // manga_hideTitle：隐藏菜单标题栏
  bool _noScale = false;    // manga_noScale：禁用双指缩放
  bool _noClickScroll = false; // manga_noClickScroll：禁用点击滚动
  int _autoSpeed = 5;       // manga_autoSpeed：自动翻页速度（秒）
  int _preDownload = 3;     // manga_preDownload：预下载后续章节图片数
  double _sidePadding = 0;  // manga_sidePadding：条漫两侧边距

  // Sigma 漫画专属补充键（manga_config_screen 写入，逐项消费到渲染分支）
  int _threshold = 128;     // manga_threshold：二值化阈值
  int _colorFilter = 0;     // manga_colorFilter：0 无 / 1 护眼 / 2 复古 / 3 冷色
  int _scaleMax = 4;        // manga_scaleMax：InteractiveViewer 最大缩放
  int _pageAnim = 0;        // manga_pageAnim：0 滑动 / 1 淡入 / 2 瞬切
  bool _noScrollAnim = false;  // manga_noScrollAnim
  bool _noCrossFade = false;   // manga_noCrossFade
  bool _volumeKeyPage = false; // manga_volumeKey
  bool _reverseVolumeKey = false; // manga_reverseVolumeKey
  bool _aiTranslate = false;   // manga_translate_enabled
  List<MangaTextRegion> _translateRegions = const [];

  // ==================== 运行状态 ====================
  // 每章图片 URL 缓存：key 为章节下标，value 为图片地址列表（null/缺失表示尚未加载）
  final Map<int, List<String>> _imageUrls = {};
  // 正在拉取图片的章节下标，防止并发重复请求
  final Set<int> _fetching = {};
  // 每章拉取失败原因，用于空白页提示与重试
  final Map<int, String> _fetchErrors = {};
  // 自动换源：候选书源列表（现有书源表）与当前生效源下标
  List<BookSource> _candidateSources = const [];
  int _activeSourceIndex = 0;
  String _activeSourceName = '';
  // 条漫滚动 / 翻页控制器
  final ScrollController _scrollController = ScrollController();
  final PageController _pageController = PageController();
  // 自动滚动（自动翻页）
  Timer? _autoScrollTimer;
  bool _autoScrollOn = false;
  // 翻页模式当前图片下标（自动翻页章末判断用）
  int _imageIndex = 0;

  @override
  void initState() {
    super.initState();
    _currentChapter = widget.initialChapter;
    _loadFilters();
    _loadChapters();
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _scrollController.dispose();
    _pageController.dispose();
    unawaited(_syncProgress());
    super.dispose();
  }

  /// 读取漫画配置（对应 manga_config_screen 的各项开关）
  Future<void> _loadFilters() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _gray = p.getBool('manga_gray') ?? false;
        _eink = p.getBool('manga_eink') ?? false;
        _scrollMode = p.getInt('manga_scrollMode') ?? 0;
        _hideTitle = p.getBool('manga_hideTitle') ?? false;
        _noScale = p.getBool('manga_noScale') ?? false;
        _noClickScroll = p.getBool('manga_noClickScroll') ?? false;
        _autoSpeed = p.getInt('manga_autoSpeed') ?? 5;
        _preDownload = p.getInt('manga_preDownload') ?? 3;
        _sidePadding = p.getDouble('manga_sidePadding') ?? 0;
        _threshold = p.getInt('manga_threshold') ?? 128;
        _colorFilter = p.getInt('manga_colorFilter') ?? 0;
        _scaleMax = p.getInt('manga_scaleMax') ?? 4;
        _pageAnim = p.getInt('manga_pageAnim') ?? 0;
        _noScrollAnim = p.getBool('manga_noScrollAnim') ?? false;
        _noCrossFade = p.getBool('manga_noCrossFade') ?? false;
        _volumeKeyPage = p.getBool('manga_volumeKey') ?? false;
        _reverseVolumeKey = p.getBool('manga_reverseVolumeKey') ?? false;
      });
    } catch (_) {}
    await _loadTranslateRegions();
  }

  /// 载入「按书源翻译规则替换图内文字」配置并预先翻译（真实调翻译服务）。
  Future<void> _loadTranslateRegions() async {
    final store = MangaTranslateStore.instance;
    final origin = widget.book.origin ?? '';
    await store.load(origin);
    if (!store.enabled) {
      if (mounted) {
        setState(() {
          _aiTranslate = false;
          _translateRegions = const [];
        });
      }
      return;
    }
    final regions = await store.translatedRegions(origin);
    if (mounted) {
      setState(() {
        _aiTranslate = true;
        _translateRegions = regions;
      });
    }
  }

  Future<void> _syncProgress() async {
    try {
      await BookProgressSync.instance.record(widget.book,
          chapterIndex: _currentChapter, pagePos: _imageIndex);
      await BookProgressSync.instance.push();
    } catch (_) {}
  }

  Future<void> _loadChapters() async {
    final chapters = await _db.getChapters(widget.book.name, widget.book.author);
    if (!mounted) return;
    setState(() {
      _chapters = chapters;
      _loading = false;
    });
    // 云进度：拉取较新的阅读位置并跳章
    final changed = await BookProgressSync.instance.pull();
    if (changed > 0 && mounted && _chapters.isNotEmpty) {
      final books = await _db.getAllBooks();
      final mine = books
          .where((b) =>
              b.name == widget.book.name && b.author == widget.book.author)
          .firstOrNull;
      if (mine != null) {
        final idx = mine.durChapterIndex.clamp(0, _chapters.length - 1).toInt();
        if (idx != _currentChapter) setState(() => _currentChapter = idx);
      }
    }
    // 加载当前章图片：优先本地缓存，缓存为空再走书源引擎
    await _ensureImages(_currentChapter);
    if (mounted) setState(() {});
    unawaited(_prefetchImages(_currentChapter));
  }

  /// 现有书源列表：当前书源优先，其余图片书源（type==2）靠前，供自动换源逐个尝试。
  Future<List<BookSource>> _candidateSourcesList() async {
    if (_candidateSources.isNotEmpty) return _candidateSources;
    final all = await _db.getAllSources(enabled: true);
    final origin = widget.book.origin ?? '';
    final ordered = <BookSource>[
      for (final s in all)
        if (origin.isNotEmpty && s.bookSourceUrl == origin) s,
    ];
    final rest = all.where((s) => !ordered.contains(s)).toList()
      ..sort((a, b) => (b.bookSourceType == 2 ? 1 : 0)
          .compareTo(a.bookSourceType == 2 ? 1 : 0));
    ordered.addAll(rest);
    _candidateSources = ordered;
    _activeSourceName = ordered.isNotEmpty ? ordered.first.bookSourceName : '';
    return ordered;
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 确保指定章节的图片列表已加载。
  ///
  /// 顺序：1) 解析 `chapter.content` 缓存中的图片；
  /// 2) 本地书籍无网络内容可拉，直接标记为空；
  /// 3) 调书源引擎 `getImageContent` 拉取，并写回 `chapter.content` 缓存。
  Future<void> _ensureImages(int index) async {
    if (index < 0 || index >= _chapters.length) return;
    if (_imageUrls.containsKey(index) || _fetching.contains(index)) return;

    final chapter = _chapters[index];
    // 1. 已缓存内容（旧版缓存 / 本地漫画 / 文本阅读器写回的图文混合内容）
    final cached = _parseImages(chapter.content ?? '');
    if (cached.isNotEmpty) {
      _imageUrls[index] = cached;
      return;
    }

    // 2. 本地书籍：没有书源可拉，直接置空（保留原空白行为，不报错）
    if (widget.book.local) {
      _imageUrls[index] = const [];
      return;
    }

    // 3. 网络漫画：调书源引擎拉取图片 URL 列表
    if (chapter.url.isEmpty) {
      _imageUrls[index] = const [];
      _fetchErrors[index] = '章节地址为空，无法加载';
      return;
    }

    _fetching.add(index);
    if (index == _currentChapter && mounted) setState(() {});
    try {
      // 自动换源：从当前生效源起，逐个尝试现有书源列表，任一成功即消费
      final sources = await _candidateSourcesList();
      if (sources.isEmpty) {
        _imageUrls[index] = const [];
        _fetchErrors[index] = '书源列表为空，无法加载漫画图片';
        return;
      }
      Object? lastError;
      for (var attempt = 0; attempt < sources.length; attempt++) {
        final si = (_activeSourceIndex + attempt) % sources.length;
        final source = sources[si];
        try {
          final content = await _engine.getImageContent(
            source,
            chapter.url,
            bookInfo: widget.book.jsContext(),
            chapter: chapter.jsContext(widget.book.bookUrl),
          );
          final urls = (content ?? '')
              .split('\n')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
          if (urls.isEmpty) {
            lastError = '书源「${source.bookSourceName}」未返回图片';
            continue; // 图片加载失败 → 切下一书源
          }
          _activeSourceIndex = si;
          _activeSourceName = source.bookSourceName;
          _imageUrls[index] = urls;
          _fetchErrors.remove(index);
          // 写回数据库缓存，下次阅读直接走缓存
          chapter.content = content;
          await _db.updateChapterContent(
              widget.book.name, widget.book.author, chapter.index, content!);
          if (attempt > 0 && index == _currentChapter && mounted) {
            _toast('已自动换源到：${source.bookSourceName}');
          }
          return;
        } catch (e) {
          lastError = e;
        }
      }
      _imageUrls[index] = const [];
      _fetchErrors[index] = '全部 ${sources.length} 个书源均未取到图片'
          '${lastError != null ? '（最后错误：$lastError）' : ''}';
    } finally {
      _fetching.remove(index);
      if (mounted) setState(() {});
    }
  }

  /// 预下载后续章节图片（manga_preDownload 控制数量，串行执行避免并发过高）。
  Future<void> _prefetchImages(int fromIndex) async {
    if (_preDownload <= 0) return;
    for (int i = fromIndex + 1;
        i <= fromIndex + _preDownload && i < _chapters.length;
        i++) {
      if (_imageUrls.containsKey(i)) continue;
      if (_chapters[i].url.isEmpty) continue;
      await _ensureImages(i);
    }
  }

  /// manga_pageAnim / manga_noScrollAnim 真实消费到翻页与滚动动画。
  Duration get _pageDuration => (_pageAnim == 2 || _noScrollAnim)
      ? Duration.zero
      : Duration(milliseconds: _pageAnim == 1 ? 450 : 300);

  Curve get _pageCurve => _pageAnim == 1 ? Curves.easeInOut : Curves.easeOut;

  /// manga_volumeKey / manga_reverseVolumeKey：音量键翻页。
  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (!_volumeKeyPage || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final k = event.logicalKey;
    final up = k == LogicalKeyboardKey.audioVolumeUp;
    final down = k == LogicalKeyboardKey.audioVolumeDown;
    if (!up && !down) return KeyEventResult.ignored;
    final forward = _reverseVolumeKey ? down : up;
    if (forward) {
      _nextChapter();
    } else {
      _prevChapter();
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          // 点击行为：未禁用「点击滚动」时，条漫模式点击向下滚动一屏（菜单改由长按唤出）；
          // 禁用点击滚动或翻页模式下，点击照旧唤出/隐藏菜单。
          onTap: () {
            if (!_noClickScroll &&
                _scrollMode == 0 &&
                _scrollController.hasClients) {
              final pos = _scrollController.position;
              final target = (_scrollController.offset + pos.viewportDimension)
                  .clamp(0.0, pos.maxScrollExtent);
              _scrollController.animateTo(target,
                  duration: _noScrollAnim
                      ? Duration.zero
                      : const Duration(milliseconds: 250),
                  curve: _noScrollAnim ? Curves.linear : Curves.easeOut);
            } else {
              setState(() => _showMenu = !_showMenu);
            }
          },
          // 长按始终可以唤出/隐藏菜单（点击滚动开启时的菜单入口）
          onLongPress: () => setState(() => _showMenu = !_showMenu),
          child: Stack(
            children: [
              _buildContent(),
              if (_showMenu) _buildMenu(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (_chapters.isEmpty) {
      return const Center(child: Text('暂无章节', style: TextStyle(color: Colors.white)));
    }
    // 当前章图片未加载时触发拉取（首次进入 / 切章后由这里发起）
    final images = _imageUrls[_currentChapter];
    if (images == null) {
      unawaited(_ensureImages(_currentChapter));
      return _buildChapterPlaceholder();
    }
    if (images.isEmpty) {
      return _buildChapterPlaceholder();
    }

    if (_scrollMode == 0) {
      // 条漫：纵向连续滚动，两侧边距取 manga_sidePadding
      return ListView.builder(
        controller: _scrollController,
        padding: EdgeInsets.symmetric(horizontal: _sidePadding),
        itemCount: images.length,
        itemBuilder: (context, index) => _buildImage(images[index], BoxFit.fitWidth, true),
      );
    } else {
      // 补齐双页拼合（manga_scrollMode==2，对齐 E 的漫画双页阅读）：
      // 相邻两页并排放进同一屏 Row，页数按 ceil(n/2)；单页模式保持原有 Center 渲染不变。
      final doublePage = _scrollMode == 2;
      return PageView.builder(
        controller: _pageController,
        itemCount: mangaPageCount(images.length, doublePage),
        onPageChanged: (i) => setState(() => _imageIndex = i),
        itemBuilder: (context, index) {
          if (!doublePage) {
            return Center(child: _buildImage(images[index], BoxFit.contain, false));
          }
          // 相邻两页并排：每张图各自保留缩放/滤镜能力，互不影响
          return Row(
            children: [
              for (final imgIndex
                  in mangaDoublePageIndices(index, images.length))
                Expanded(
                    child: Center(
                        child: _buildImage(
                            images[imgIndex], BoxFit.contain, false))),
            ],
          );
        },
      );
    }
  }

  /// 章节图片的加载中 / 失败 / 空占位。
  Widget _buildChapterPlaceholder() {
    if (_fetching.contains(_currentChapter)) {
      return const Center(
          child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: Colors.white),
          SizedBox(height: 12),
          Text('正在加载图片…', style: TextStyle(color: Colors.white70)),
        ],
      ));
    }
    final error = _fetchErrors[_currentChapter];
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(error ?? '本章暂无图片',
              style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
          if (error != null) ...[
            const SizedBox(height: 12),
                FilledButton(
                  onPressed: () {
                    // 重试：清除失败标记后重新拉取
                    _fetchErrors.remove(_currentChapter);
                    _imageUrls.remove(_currentChapter);
                    unawaited(_ensureImages(_currentChapter));
                  },
                  child: const Text('重试'),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => unawaited(_switchToNextSource()),
                  icon: const Icon(Icons.autorenew_outlined),
                  label: const Text('换源重试', style: TextStyle(color: Colors.white70)),
                ),
              ],
        ],
      ),
    );
  }

  /// 渲染单张漫画图片，应用灰度/墨水屏滤镜，并包一层 InteractiveViewer 支持双指缩放。
  Widget _buildImage(String url, BoxFit fit, bool dark) {
    final img = _MangaImage(
      url: url,
      fit: fit,
      dark: dark,
      gray: _gray,
      eink: _eink,
      noScale: _noScale,
      threshold: _threshold,
      colorFilter: _colorFilter,
      scaleMax: _scaleMax.toDouble(),
      fadeIn: !_noCrossFade && _pageAnim != 2,
    );
    // 漫画 AI 翻译：OCR 框 / 书源规则译文覆盖层（真实盖回图内文字）
    if (!_aiTranslate || _translateRegions.isEmpty) return img;
    return Stack(children: [
      img,
      Positioned.fill(
        child: MangaTranslationOverlay(regions: _translateRegions),
      ),
    ]);
  }

  /// 从缓存内容中正则抽取 `<img src>`（兼容单双引号与 data-src）。
  List<String> _parseImages(String content) {
    final regex = RegExp(r'''<img[^>]+(?:src|data-src)=["']([^"']+)["']''', caseSensitive: false);
    return regex.allMatches(content).map((m) => m.group(1)!).toList();
  }

  // ==================== 菜单 ====================

  Widget _buildMenu() {
    return Positioned.fill(
      child: Column(
        children: [
          // manga_hideTitle：隐藏标题栏
          if (!_hideTitle)
            Container(
              color: Colors.black87,
              child: SafeArea(
                child: Row(
                  children: [
                    IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), tooltip: '返回', onPressed: () => Navigator.pop(context)),
                    Expanded(child: Text(_chapters.isNotEmpty ? _chapters[_currentChapter].title : '', style: const TextStyle(color: Colors.white, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    IconButton(icon: const Icon(Icons.list, color: Colors.white), tooltip: '章节列表', onPressed: _showChapterList),
                  ],
                ),
              ),
            ),
          const Spacer(),
          Container(
            color: Colors.black87,
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildMenuButton(
                        _scrollMode == 0 ? Icons.swap_vert : Icons.swap_vert_outlined, '滚动模式',
                        () => _setScrollMode(0)),
                    _buildMenuButton(
                        _scrollMode != 0 ? Icons.swap_horiz : Icons.swap_horiz_outlined, '翻页模式',
                        () => _setScrollMode(1)),
                    // manga_autoSpeed：自动翻页速度，点击开始/停止自动滚动
                    _buildMenuButton(_autoScrollOn ? Icons.pause : Icons.play_arrow, '自动滚动', _toggleAutoScroll),
                    _buildMenuButton(Icons.skip_previous, '上一章', _prevChapter),
                    _buildMenuButton(Icons.skip_next, '下一章', _nextChapter),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildMenuButton(Icons.autorenew_outlined, '换源',
                        () => unawaited(_switchToNextSource())),
                    _buildMenuButton(Icons.cloud_sync_outlined, '云进度',
                        () => unawaited(_manualSyncProgress())),
                    _buildMenuButton(
                        _aiTranslate
                            ? Icons.translate
                            : Icons.translate_outlined,
                        'AI 翻译',
                        () => unawaited(_toggleAiTranslate())),
                  ],
                ),
                const SizedBox(height: 8),
                // 展示当前生效的自动滚动速度与书源
                Text(
                    '自动滚动速度：$_autoSpeed 秒/次 · 当前书源：'
                    '${_activeSourceName.isEmpty ? "自动" : _activeSourceName}',
                    style: const TextStyle(color: Colors.white54, fontSize: 11)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('章节', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    Expanded(
                      child: Slider(
                        value: _chapters.isNotEmpty ? _currentChapter.toDouble() : 0,
                        max: (_chapters.length - 1).toDouble(),
                        onChanged: (v) => _goToChapter(v.toInt()),
                      ),
                    ),
                    Text('${_currentChapter + 1}/${_chapters.length}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuButton(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  /// 手动切到下一书源：清当前章缓存后重新走自动换源链路。
  Future<void> _switchToNextSource() async {
    final sources = await _candidateSourcesList();
    if (sources.isEmpty) {
      _toast('当前没有可用书源');
      return;
    }
    _activeSourceIndex = (_activeSourceIndex + 1) % sources.length;
    if (_chapters.isNotEmpty) {
      final ch = _chapters[_currentChapter];
      ch.content = null;
      await _db.updateChapterContent(
          widget.book.name, widget.book.author, ch.index, '');
    }
    _imageUrls.remove(_currentChapter);
    _fetchErrors.remove(_currentChapter);
    if (mounted) setState(() {});
    await _ensureImages(_currentChapter);
    if (mounted) setState(() {});
    _toast('已切换到书源：${sources[_activeSourceIndex].bookSourceName}');
  }

  /// 手动云进度：拉取较新的云端进度 + 上传本地进度。
  Future<void> _manualSyncProgress() async {
    final changed = await BookProgressSync.instance.pull();
    await _syncProgress();
    _toast(changed > 0 ? '云进度已拉取并同步（更新 $changed 本）' : '本地进度已上传');
  }

  /// 漫画 AI 翻译开关：切换后重新按书源规则翻译并刷新覆盖层。
  Future<void> _toggleAiTranslate() async {
    final store = MangaTranslateStore.instance;
    await store.setEnabled(!_aiTranslate);
    store.clearCache();
    await _loadTranslateRegions();
    _toast(_aiTranslate ? 'AI 翻译已开启' : 'AI 翻译已关闭');
  }

  /// 切换滚动模式并持久化到 manga_scrollMode，保持与漫画配置页一致。
  Future<void> _setScrollMode(int mode) async {
    setState(() {
      _scrollMode = mode;
      _imageIndex = 0;
    });
    // 补齐双页拼合（对齐 E 的漫画双页阅读）：单页↔双页切换会改变 PageView 页数，
    // 复位到第 0 页避免停留在越界页。
    if (_pageController.hasClients) _pageController.jumpToPage(0);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt('manga_scrollMode', mode);
    } catch (_) {}
  }

  // ==================== 自动滚动（manga_autoSpeed） ====================

  void _toggleAutoScroll() {
    if (_autoScrollOn) {
      _stopAutoScroll();
    } else {
      _startAutoScroll();
    }
  }

  void _startAutoScroll() {
    _autoScrollTimer?.cancel();
    // 速度配置为秒，夹紧到 1~30 秒防御非法值
    final seconds = _autoSpeed.clamp(1, 30);
    _autoScrollTimer = Timer.periodic(Duration(seconds: seconds), (_) => _autoScrollStep());
    setState(() => _autoScrollOn = true);
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    setState(() => _autoScrollOn = false);
  }

  /// 自动滚动一步：条漫向下滚约一屏，翻页模式翻到下一页；章末自动进入下一章。
  void _autoScrollStep() {
    final images = _imageUrls[_currentChapter];
    if (images == null || images.isEmpty) return;
    if (_scrollMode == 0) {
      if (!_scrollController.hasClients) return;
      final pos = _scrollController.position;
      final next = _scrollController.offset + pos.viewportDimension;
      if (next >= pos.maxScrollExtent - 1) {
        _nextChapter();
        return;
      }
      _scrollController.animateTo(next,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    } else {
      // 补齐双页拼合（对齐 E 的漫画双页阅读）：双页模式下 _imageIndex 是「页对」索引，
      // 章末判断改用 _pageCount，避免单页口径导致翻到一半就跳章。
      if (_imageIndex >= mangaPageCount(images.length, _scrollMode == 2) - 1) {
        _nextChapter();
        return;
      }
      _pageController.nextPage(duration: _pageDuration, curve: _pageCurve);
    }
  }

  // ==================== 章节切换 ====================

  void _prevChapter() {
    if (_currentChapter > 0) _goToChapter(_currentChapter - 1);
  }

  void _nextChapter() {
    if (_currentChapter < _chapters.length - 1) _goToChapter(_currentChapter + 1);
  }

  Future<void> _goToChapter(int index) async {
    if (index < 0 || index >= _chapters.length || index == _currentChapter) return;
    setState(() {
      _currentChapter = index;
      _imageIndex = 0;
    });
    // 补齐双页拼合（对齐 E 的漫画双页阅读）：新章节图片数不同，复位翻页位置避免越界。
    if (_pageController.hasClients) _pageController.jumpToPage(0);
    await _ensureImages(index);
    unawaited(_prefetchImages(index));
  }

  void _showChapterList() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (context) => ListView.builder(
        itemCount: _chapters.length,
        itemBuilder: (context, index) => ListTile(
          title: Text(_chapters[index].title, style: TextStyle(color: index == _currentChapter ? Theme.of(context).colorScheme.primary : Colors.white70, fontSize: 14)),
          selected: index == _currentChapter,
          onTap: () {
            _goToChapter(index);
            Navigator.pop(context);
          },
        ),
      ),
    );
  }
}

/// 单张漫画图片：灰度/墨水屏滤镜 + InteractiveViewer 双指缩放。
///
/// 缩放采用「放大后才允许平移」策略（TransformationController 监听缩放倍数），
/// 避免在条漫纵向滚动 / 翻页手势上产生冲突；`noScale` 为 true 时不包缩放层。
class _MangaImage extends StatefulWidget {
  final String url;
  final BoxFit fit;
  final bool dark;
  final bool gray;
  final bool eink;
  final bool noScale;
  final int threshold;
  final int colorFilter;
  final double scaleMax;
  final bool fadeIn;

  const _MangaImage({
    required this.url,
    required this.fit,
    required this.dark,
    required this.gray,
    required this.eink,
    required this.noScale,
    this.threshold = 128,
    this.colorFilter = 0,
    this.scaleMax = 4,
    this.fadeIn = true,
  });

  @override
  State<_MangaImage> createState() => _MangaImageState();
}

class _MangaImageState extends State<_MangaImage> {
  final TransformationController _transformController = TransformationController();
  // 仅缩放倍数大于 1 时开放平移，未缩放时把手势交还给外层滚动/翻页
  bool _panEnabled = false;

  @override
  void initState() {
    super.initState();
    _transformController.addListener(_onTransform);
  }

  @override
  void dispose() {
    _transformController.removeListener(_onTransform);
    _transformController.dispose();
    super.dispose();
  }

  /// 从变换矩阵估算当前缩放倍数是否大于 1。
  /// （该版本 vector_math 无 getMaxScaledValue，手动取 X 轴缩放平方与 1 比较）
  bool _isZoomed(Matrix4 m) {
    final s = m.storage;
    final scaleSq = s[0] * s[0] + s[1] * s[1];
    return scaleSq > 1.01 * 1.01;
  }

  void _onTransform() {
    final zoomed = _isZoomed(_transformController.value);
    if (zoomed != _panEnabled && mounted) {
      setState(() => _panEnabled = zoomed);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget img = CachedNetworkImage(
      imageUrl: widget.url,
      fit: widget.fit,
      placeholder: (context, url) => Container(
        height: 200,
        color: widget.dark ? Colors.grey[900] : null,
        child: Center(child: CircularProgressIndicator(color: widget.dark ? null : Colors.white)),
      ),
      errorWidget: (context, url, error) =>
          Icon(Icons.broken_image, color: widget.dark ? Colors.grey : Colors.grey),
    );
    // 墨水屏优化：灰度 + 提高对比度
    if (widget.eink) {
      img = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0, 0, 0, 1, 0,
        ]),
        child: img,
      );
      img = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          1.2, 0, 0, 0, -20,
          0, 1.2, 0, 0, -20,
          0, 0, 1.2, 0, -20,
          0, 0, 0, 1, 0,
        ]),
        child: img,
      );
    } else if (widget.gray) {
      img = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0, 0, 0, 1, 0,
        ]),
        child: img,
      );
    }
    // manga_threshold：二值化阈值（灰度/墨水屏之后按阈值拉开黑白对比）
    if (widget.eink || widget.gray) {
      final bias = -((widget.threshold.clamp(0, 255) - 128) * 1.8).toDouble();
      img = ColorFiltered(
        colorFilter: ColorFilter.matrix(<double>[
          3, 0, 0, 0, bias,
          0, 3, 0, 0, bias,
          0, 0, 3, 0, bias,
          0, 0, 0, 1, 0,
        ]),
        child: img,
      );
    }
    // manga_colorFilter：0 无 / 1 护眼 / 2 复古 / 3 冷色
    if (widget.colorFilter == 1) {
      img = ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          0.95, 0, 0, 0, 10,
          0, 0.95, 0, 0, 8,
          0, 0, 0.85, 0, 0,
          0, 0, 0, 1, 0,
        ]),
        child: img,
      );
    } else if (widget.colorFilter == 2) {
      img = ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          0.393, 0.769, 0.189, 0, 0,
          0.349, 0.686, 0.168, 0, 0,
          0.272, 0.534, 0.131, 0, 0,
          0, 0, 0, 1, 0,
        ]),
        child: img,
      );
    } else if (widget.colorFilter == 3) {
      img = ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          0.9, 0, 0, 0, 0,
          0, 0.95, 0, 0, 0,
          0, 0, 1.1, 0, 10,
          0, 0, 0, 1, 0,
        ]),
        child: img,
      );
    }
    // manga_noCrossFade / manga_pageAnim：图片淡入
    if (widget.fadeIn) {
      img = TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 260),
        builder: (context, v, child) => Opacity(opacity: v, child: child),
        child: img,
      );
    }
    // manga_noScale：禁用双指缩放时直接返回图片
    if (widget.noScale) return img;
    return InteractiveViewer(
      transformationController: _transformController,
      minScale: 1.0,
      maxScale: widget.scaleMax.clamp(2.0, 8.0).toDouble(),
      panEnabled: _panEnabled,
      // 结束交互时若缩放已回到 1 倍以内则复位，并恢复「禁用平移」
      onInteractionEnd: (_) {
        if (!_isZoomed(_transformController.value)) {
          _transformController.value = Matrix4.identity();
          if (_panEnabled && mounted) setState(() => _panEnabled = false);
        }
      },
      child: img,
    );
  }
}
