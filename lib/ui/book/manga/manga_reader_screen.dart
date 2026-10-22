import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_chapter.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/help/source/source_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  int _scrollMode = 0;      // manga_scrollMode：0 条漫(纵向连续) 1 横向翻页 2 双页(降级为翻页)
  bool _gray = false;       // manga_gray：灰度模式
  bool _eink = false;       // manga_eink：墨水屏优化
  bool _hideTitle = false;  // manga_hideTitle：隐藏菜单标题栏
  bool _noScale = false;    // manga_noScale：禁用双指缩放
  bool _noClickScroll = false; // manga_noClickScroll：禁用点击滚动
  int _autoSpeed = 5;       // manga_autoSpeed：自动翻页速度（秒）
  int _preDownload = 3;     // manga_preDownload：预下载后续章节图片数
  double _sidePadding = 0;  // manga_sidePadding：条漫两侧边距

  // ==================== 运行状态 ====================
  // 每章图片 URL 缓存：key 为章节下标，value 为图片地址列表（null/缺失表示尚未加载）
  final Map<int, List<String>> _imageUrls = {};
  // 正在拉取图片的章节下标，防止并发重复请求
  final Set<int> _fetching = {};
  // 每章拉取失败原因，用于空白页提示与重试
  final Map<int, String> _fetchErrors = {};
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
      });
    } catch (_) {}
  }

  Future<void> _loadChapters() async {
    final chapters = await _db.getChapters(widget.book.name, widget.book.author);
    if (!mounted) return;
    setState(() {
      _chapters = chapters;
      _loading = false;
    });
    // 加载当前章图片：优先本地缓存，缓存为空再走书源引擎
    await _ensureImages(_currentChapter);
    if (mounted) setState(() {});
    unawaited(_prefetchImages(_currentChapter));
  }

  /// 根据 book.origin 查找书源；先按 URL 精确查，失败再全表扫描兜底。
  Future<BookSource?> _findSource() async {
    final origin = widget.book.origin;
    if (origin == null || origin.isEmpty) return null;
    try {
      final exact = await _db.getSource(origin);
      if (exact != null) return exact;
      final all = await _db.getAllSources();
      return all.where((s) => s.bookSourceUrl == origin).firstOrNull;
    } catch (_) {
      return null;
    }
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
      final source = await _findSource();
      if (source == null) {
        _imageUrls[index] = const [];
        _fetchErrors[index] = '未找到书源：${widget.book.origin ?? "未知"}';
        return;
      }
      final content = await _engine.getImageContent(
        source,
        chapter.url,
        bookInfo: widget.book.jsContext(),
        chapter: chapter.jsContext(widget.book.bookUrl),
      );
      if (content != null && content.trim().isNotEmpty) {
        final urls = content
            .split('\n')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        _imageUrls[index] = urls;
        _fetchErrors.remove(index);
        // 写回数据库缓存，并同步内存中的章节内容，下次阅读直接走缓存
        chapter.content = content;
        await _db.updateChapterContent(
            widget.book.name, widget.book.author, chapter.index, content);
      } else {
        _imageUrls[index] = const [];
        _fetchErrors[index] = '未获取到图片，请检查书源图片规则';
      }
    } catch (e) {
      _imageUrls[index] = const [];
      _fetchErrors[index] = '加载失败：$e';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        // 点击行为：未禁用「点击滚动」时，条漫模式点击向下滚动一屏（菜单改由长按唤出）；
        // 禁用点击滚动或翻页模式下，点击照旧唤出/隐藏菜单。
        onTap: () {
          if (!_noClickScroll && _scrollMode == 0 && _scrollController.hasClients) {
            final pos = _scrollController.position;
            final target =
                (_scrollController.offset + pos.viewportDimension).clamp(0.0, pos.maxScrollExtent);
            _scrollController.animateTo(target,
                duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
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
      // 横向翻页（manga_scrollMode=2 双页模式降级为普通翻页，暂未实现双页拼合）
      return PageView.builder(
        controller: _pageController,
        itemCount: images.length,
        onPageChanged: (i) => setState(() => _imageIndex = i),
        itemBuilder: (context, index) =>
            Center(child: _buildImage(images[index], BoxFit.contain, false)),
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
          ],
        ],
      ),
    );
  }

  /// 渲染单张漫画图片，应用灰度/墨水屏滤镜，并包一层 InteractiveViewer 支持双指缩放。
  Widget _buildImage(String url, BoxFit fit, bool dark) {
    return _MangaImage(
      url: url,
      fit: fit,
      dark: dark,
      gray: _gray,
      eink: _eink,
      noScale: _noScale,
    );
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
                    IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
                    Expanded(child: Text(_chapters.isNotEmpty ? _chapters[_currentChapter].title : '', style: const TextStyle(color: Colors.white, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    IconButton(icon: const Icon(Icons.list, color: Colors.white), onPressed: _showChapterList),
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
                // 展示当前生效的自动滚动速度，便于用户理解 manga_autoSpeed 配置
                Text('自动滚动速度：$_autoSpeed 秒/次',
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

  /// 切换滚动模式并持久化到 manga_scrollMode，保持与漫画配置页一致。
  Future<void> _setScrollMode(int mode) async {
    setState(() {
      _scrollMode = mode;
      _imageIndex = 0;
    });
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
      if (_imageIndex >= images.length - 1) {
        _nextChapter();
        return;
      }
      _pageController.nextPage(
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
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

  const _MangaImage({
    required this.url,
    required this.fit,
    required this.dark,
    required this.gray,
    required this.eink,
    required this.noScale,
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
    // manga_noScale：禁用双指缩放时直接返回图片
    if (widget.noScale) return img;
    return InteractiveViewer(
      transformationController: _transformController,
      minScale: 1.0,
      maxScale: 4.0,
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
