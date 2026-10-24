import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/di/book_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// PDF 本地书阅读页（基于 pdfx 位图分页渲染）。
///
/// 交互复刻 [ReadingScreen]：
/// * 点击页面中央唤出/隐藏菜单；
/// * 顶部菜单（返回、书名、更多：跳页/护眼/亮度）；
/// * 底部菜单（上一页/下一页、翻页滑杆、页码与总页数、跳页对话框、亮度滑杆、护眼遮罩）；
/// * 左右滑动翻页与双指缩放由 pdfx 的 [PdfView] 内置手势完成。
///
/// 阅读进度保存方式与 [ReadingScreen] 对齐：退出/翻页时调用
/// `BookProvider.saveReadingProgress`（durChapterIndex=0 对应 PDF 单章「正文」，
/// durChapterPos=当前页码），并同步 SharedPreferences 键
/// `pdf_progress_<书名>_<作者>` 便于单独恢复。
class PdfReaderScreen extends StatefulWidget {
  final Book book;

  const PdfReaderScreen({super.key, required this.book});

  @override
  State<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends State<PdfReaderScreen>
    with SingleTickerProviderStateMixin {
  static const _wakeChannel = MethodChannel('legado/wakelock');
  static const _eyeCarePrefKey = 'pdf_eye_care';
  static const _saveDebounce = Duration(milliseconds: 500);

  /// 单本 PDF 的 SharedPreferences 进度键
  String get _progressKey =>
      'pdf_progress_${widget.book.name}_${widget.book.author}';

  // 进度保存所需的 provider：initState 捕获，避免 dispose 里再走 context
  late final BookProvider _bookProvider;

  PdfController? _pdfController;
  bool _loading = true;
  String? _error;
  int _totalPages = 0;
  int _currentPage = 1; // 1 起始，与 pdfx 页码约定一致
  int? _dragPage; // 滑杆拖动中的局部页码（null 表示未拖动）

  // 菜单显隐（动画曲线/位移量参考 reading_screen）
  late AnimationController _menuController;

  // 护眼模式（暖黄遮罩）与亮度滑杆展开状态
  bool _eyeCare = false;
  bool _showBrightnessRow = false;

  // 屏幕常亮（跟随阅读配置 keepScreenOn）
  bool _wakeEnabled = false;

  // 翻页进度防抖保存
  Timer? _saveTimer;

  /// 文档加载完成且拿到总页数后才允许翻页/滑杆操作
  bool get _ready => _pdfController != null && _totalPages > 0 && _error == null;

  @override
  void initState() {
    super.initState();
    _bookProvider = context.read<BookProvider>();
    _menuController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _loadEyeCare();
    // PDF 横竖屏自适应：允许全部屏幕方向
    try {
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    } catch (_) {}
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _applyWakeLock(context.read<ReadProvider>().config.keepScreenOn);
    });
    _init();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    // 退出时兜底保存当前页
    if (_currentPage > 0) _saveProgress(_currentPage);
    _pdfController?.loadingState.removeListener(_onLoadingStateChanged);
    _pdfController?.dispose();
    _menuController.dispose();
    _applyWakeLock(false);
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

  /// 读取护眼模式开关
  Future<void> _loadEyeCare() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() => _eyeCare = p.getBool(_eyeCarePrefKey) ?? false);
    } catch (_) {}
  }

  Future<void> _toggleEyeCare() async {
    final next = !_eyeCare;
    setState(() => _eyeCare = next);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_eyeCarePrefKey, next);
    } catch (_) {}
  }

  /// 打开 PDF：校验文件 -> 恢复保存的页码 -> 创建 PdfController。
  /// 文件缺失/路径为空时直接进入错误态；加载失败由 onDocumentError 兜底。
  Future<void> _init() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final path = widget.book.fileName;
    if (path == null || path.isEmpty) {
      if (mounted) {
        setState(() {
          _error = '书籍文件路径缺失，无法打开 PDF';
          _loading = false;
        });
      }
      return;
    }
    final file = File(path);
    if (!await file.exists()) {
      if (mounted) {
        setState(() {
          _error = '文件不存在或已被移动：$path';
          _loading = false;
        });
      }
      return;
    }
    final savedPage = await _loadSavedPage();
    final controller = PdfController(
      document: PdfDocument.openFile(path),
      initialPage: savedPage,
    );
    controller.loadingState.addListener(_onLoadingStateChanged);
    if (!mounted) {
      controller.loadingState.removeListener(_onLoadingStateChanged);
      controller.dispose();
      return;
    }
    final old = _pdfController;
    _pdfController = controller;
    _currentPage = savedPage;
    old?.loadingState.removeListener(_onLoadingStateChanged);
    old?.dispose();
    setState(() => _loading = false);
  }

  /// 读取保存的页码：优先 SharedPreferences，回退 Book.durChapterPos
  Future<int> _loadSavedPage() async {
    try {
      final p = await SharedPreferences.getInstance();
      final saved = p.getInt(_progressKey) ?? widget.book.durChapterPos;
      return saved > 0 ? saved : 1;
    } catch (_) {
      return 1;
    }
  }

  /// 文档加载成功：记录总页数，纠正越界的恢复页码
  void _onLoadingStateChanged() {
    final controller = _pdfController;
    if (controller == null || !mounted) return;
    if (controller.loadingState.value != PdfLoadingState.success) return;
    final total = controller.pagesCount ?? 0;
    var page = controller.page;
    if (total > 0 && page > total) {
      page = total;
      controller.jumpToPage(page);
    }
    setState(() {
      _totalPages = total;
      _currentPage = page;
    });
    _scheduleSave(page);
  }

  /// pdfx 文档加载失败（文件损坏/格式不支持等）：展示友好错误+重试
  void _onDocumentError(Object error) {
    if (!mounted) return;
    setState(() => _error = 'PDF 打开失败，文件可能已损坏或不受支持\n$error');
  }

  /// 翻页回调（1 起始）
  void _onPageChanged(int page) {
    if (!mounted) return;
    setState(() => _currentPage = page);
    _scheduleSave(page);
  }

  void _scheduleSave(int page) {
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDebounce, () => _saveProgress(page));
  }

  /// 保存阅读进度：Book 字段（对齐 reading_screen）+ SharedPreferences
  Future<void> _saveProgress(int page) async {
    if (page <= 0) return;
    try {
      await _bookProvider.saveReadingProgress(widget.book, 0, page);
    } catch (_) {}
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_progressKey, page);
    } catch (_) {}
  }

  void _toggleMenu() {
    if (_menuController.isDismissed) {
      _menuController.forward();
    } else {
      _menuController.reverse();
    }
  }

  /// 跳转到指定页（1 起始，自动做边界裁剪）
  void _jumpToPage(int page) {
    if (!_ready) return;
    final total = _totalPages;
    final target = page.clamp(1, total);
    _pdfController?.jumpToPage(target);
    setState(() => _currentPage = target);
    _scheduleSave(target);
  }

  /// 跳页对话框
  Future<void> _showJumpDialog() async {
    if (!_ready) return;
    final input = TextEditingController();
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('跳到指定页'),
        content: TextField(
          controller: input,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: '1 - $_totalPages'),
          onSubmitted: (v) => Navigator.pop(ctx, int.tryParse(v)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(input.text)),
            child: const Text('跳转'),
          ),
        ],
      ),
    );
    if (result != null) _jumpToPage(result);
  }

  @override
  Widget build(BuildContext context) {
    final readProvider = context.watch<ReadProvider>();
    final config = readProvider.config;
    // 屏幕常亮设置变化时实时生效（同 reading_screen）
    if (_wakeEnabled != config.keepScreenOn) {
      _applyWakeLock(config.keepScreenOn);
    }
    final colorScheme = Theme.of(context).colorScheme;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Theme.of(context).brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        body: Stack(
          children: [
            Positioned.fill(child: _buildBody(colorScheme)),
            _buildTopMenu(colorScheme),
            _buildBottomMenu(colorScheme, readProvider),
            // 护眼模式：暖黄色遮罩（不拦截点击），与 reading_screen 同色同算法
            if (_eyeCare)
              IgnorePointer(
                child: Positioned.fill(
                  child: Container(
                    color: const Color(0xFFFFF1D6).withOpacity(0.35),
                  ),
                ),
              ),
            // 亮度调节：黑色半透明遮罩模拟屏幕变暗（不拦截点击）
            if (readProvider.brightness < 1.0)
              IgnorePointer(
                child: Positioned.fill(
                  child: Container(
                    color:
                        Colors.black.withOpacity((1 - readProvider.brightness) * 0.6),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 主内容区：错误态 / 初始化加载态 / PdfView（点击中央唤出菜单）
  Widget _buildBody(ColorScheme colorScheme) {
    if (_error != null) return _buildError(colorScheme, _error!);
    // 初始化阶段（校验文件/读进度/创建控制器）显示加载态
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: colorScheme.primary),
      );
    }
    final controller = _pdfController;
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // 仅点击页面中央切换菜单显隐（左右滑动翻页交给 PdfView 手势）
      onTapUp: (details) {
        final size = MediaQuery.of(context).size;
        final dx = details.globalPosition.dx;
        final dy = details.globalPosition.dy;
        final centerX = dx > size.width / 3 && dx < size.width * 2 / 3;
        final centerY = dy > size.height / 3 && dy < size.height * 2 / 3;
        if (centerX && centerY) _toggleMenu();
      },
      child: PdfView(
        controller: controller,
        scrollDirection: Axis.horizontal,
        backgroundDecoration: BoxDecoration(color: colorScheme.surface),
        onPageChanged: _onPageChanged,
        onDocumentError: _onDocumentError,
      ),
    );
  }

  /// 加载失败/文件损坏的友好提示（图标 + 文字 + 重试）
  Widget _buildError(ColorScheme colorScheme, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 56, color: colorScheme.error),
            const SizedBox(height: 16),
            Text('PDF 无法打开',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _init,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  /// 顶部菜单（返回、书名、更多），滑入动画与 reading_screen 一致
  Widget _buildTopMenu(ColorScheme colorScheme) {
    return AnimatedBuilder(
      animation: _menuController,
      builder: (context, child) => Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: Transform.translate(
          offset: Offset(0, -(1 - _menuController.value) * 120),
          child: Opacity(opacity: _menuController.value, child: child),
        ),
      ),
      child: AppBar(
        title: Text(widget.book.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (value) {
              switch (value) {
                case 'jump':
                  _showJumpDialog();
                case 'eye':
                  _toggleEyeCare();
                case 'brightness':
                  setState(() => _showBrightnessRow = !_showBrightnessRow);
              }
            },
            itemBuilder: (context) => [
              _moreMenuItem('jump', Icons.pin, '跳到指定页'),
              _moreMenuItem('eye',
                  _eyeCare ? Icons.remove_red_eye : Icons.remove_red_eye_outlined,
                  _eyeCare ? '关闭护眼模式' : '开启护眼模式'),
              _moreMenuItem(
                  'brightness',
                  Icons.brightness_6,
                  _showBrightnessRow ? '隐藏亮度调节' : '亮度调节'),
            ],
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _moreMenuItem(
      String value, IconData icon, String label) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Text(label),
        ],
      ),
    );
  }

  /// 底部菜单（翻页/滑杆/页码/跳页/护眼/亮度），下滑动画与 reading_screen 一致
  Widget _buildBottomMenu(ColorScheme colorScheme, ReadProvider readProvider) {
    return AnimatedBuilder(
      animation: _menuController,
      builder: (context, child) => Positioned(
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
      ),
      child: _buildBottomPanel(colorScheme, readProvider),
    );
  }

  Widget _buildBottomPanel(ColorScheme colorScheme, ReadProvider readProvider) {
    final showPage = _dragPage ?? _currentPage;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 上一页 / 翻页滑杆 / 下一页（拖动只更新局部页码，松手才跳页）
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.skip_previous),
                    onPressed:
                        _ready && _currentPage > 1 ? () => _jumpToPage(_currentPage - 1) : null,
                  ),
                  Expanded(
                    child: Slider(
                      value: _ready && _totalPages > 1
                          ? ((showPage - 1) / (_totalPages - 1)).clamp(0.0, 1.0)
                          : 0,
                      onChanged: _ready && _totalPages > 1
                          ? (v) => setState(
                              () => _dragPage = (v * (_totalPages - 1)).round() + 1)
                          : null,
                      onChangeEnd: _ready && _totalPages > 1
                          ? (v) {
                              final page = (v * (_totalPages - 1)).round() + 1;
                              setState(() => _dragPage = null);
                              _jumpToPage(page);
                            }
                          : null,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next),
                    onPressed: _ready && _currentPage < _totalPages
                        ? () => _jumpToPage(_currentPage + 1)
                        : null,
                  ),
                ],
              ),
            ),
            // 页码 / 跳页 / 护眼 / 亮度
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Text(
                    '第 $showPage / ${_totalPages > 0 ? _totalPages : '…'} 页',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _showJumpDialog,
                    icon: const Icon(Icons.pin, size: 18),
                    label: const Text('跳页'),
                  ),
                  IconButton(
                    tooltip: _eyeCare ? '关闭护眼模式' : '开启护眼模式',
                    icon: Icon(_eyeCare
                        ? Icons.remove_red_eye
                        : Icons.remove_red_eye_outlined),
                    onPressed: _toggleEyeCare,
                  ),
                  IconButton(
                    tooltip: '亮度调节',
                    icon: Icon(_showBrightnessRow
                        ? Icons.brightness_high
                        : Icons.brightness_6),
                    onPressed: () =>
                        setState(() => _showBrightnessRow = !_showBrightnessRow),
                  ),
                ],
              ),
            ),
            // 亮度滑杆（复用 ReadProvider，与 reading_screen 同一份亮度状态）
            if (_showBrightnessRow)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  children: [
                    const Icon(Icons.brightness_6),
                    Expanded(
                      child: Slider(
                        value: readProvider.brightness.clamp(0.0, 1.0),
                        onChanged: (v) => readProvider.setBrightness(v),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
