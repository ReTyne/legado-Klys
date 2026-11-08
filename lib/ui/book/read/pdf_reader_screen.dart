import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/v14_models.dart';
import 'package:legado_md3/di/book_provider.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';
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
  final DatabaseService _db = DatabaseService();
  List<PdfOutline> _outlines = [];

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
    _loadOutlines();
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

  /// 从 pdf_outlines 表恢复本书目录。
  Future<void> _loadOutlines() async {
    try {
      final list =
          await _db.getPdfOutlines(widget.book.name, widget.book.author);
      if (mounted) setState(() => _outlines = list);
    } catch (_) {}
  }

  /// 目录 / 大纲面板：点击跳转、解析内置大纲、手动增删均在此闭环。
  Future<void> _showOutlineSheet() async {
    if (!mounted) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _OutlineSheet(
        outlines: _outlines,
        totalPages: _totalPages,
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'parse') {
      await _parseOutlines();
      await _showOutlineSheet();
    } else if (action == 'add') {
      await _addOutlineManually();
      await _showOutlineSheet();
    } else if (action.startsWith('del:')) {
      await _deleteOutlineAt(int.tryParse(action.substring(4)) ?? -1);
      await _showOutlineSheet();
    } else if (action.startsWith('go:')) {
      final page = int.tryParse(action.substring(3));
      if (page != null) _jumpToPage(page + 1);
    }
  }

  /// 解析 PDF 内置 /Outlines 并整表落库；解析不到时保留手动目录。
  Future<void> _parseOutlines() async {
    final path = widget.book.fileName;
    if (path == null || path.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await File(path).readAsBytes();
      final res = _PdfOutlineParser.parse(
        bytes,
        bookName: widget.book.name,
        author: widget.book.author,
        totalPages: _totalPages,
      );
      if (res.outlines.isNotEmpty) {
        await _db.replacePdfOutlines(
            widget.book.name, widget.book.author, res.outlines);
        if (mounted) setState(() => _outlines = res.outlines);
      }
      messenger.showSnackBar(SnackBar(
        content: Text(res.outlines.isNotEmpty
            ? '已解析 PDF 内置大纲 ${res.outlines.length} 条'
            : res.found
                ? '发现大纲字典但目标页无法解析，可手动添加目录'
                : '该 PDF 未内置大纲，可手动添加目录'),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('大纲解析失败：$e')));
    }
  }

  Future<void> _addOutlineManually() async {
    final titleCtrl = TextEditingController();
    final pageCtrl = TextEditingController(text: '$_currentPage');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加目录项'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: '标题'),
            ),
            TextField(
              controller: pageCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                  labelText: '页码（1 - ${_totalPages > 0 ? _totalPages : '…'}）'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('添加')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final title = titleCtrl.text.trim();
    if (title.isEmpty) return;
    final page = int.tryParse(pageCtrl.text.trim()) ?? _currentPage;
    final maxPage = _totalPages > 0 ? _totalPages - 1 : 0;
    final next = List<PdfOutline>.of(_outlines)
      ..add(PdfOutline(
        bookName: widget.book.name,
        author: widget.book.author,
        title: title,
        level: 0,
        page: (page - 1).clamp(0, maxPage),
        order: _outlines.length,
      ));
    await _db.replacePdfOutlines(
        widget.book.name, widget.book.author, next);
    if (mounted) setState(() => _outlines = next);
  }

  Future<void> _deleteOutlineAt(int index) async {
    if (index < 0 || index >= _outlines.length) return;
    final next = List<PdfOutline>.of(_outlines)..removeAt(index);
    final renumbered = <PdfOutline>[];
    for (var i = 0; i < next.length; i++) {
      final o = next[i];
      renumbered.add(PdfOutline(
        bookName: o.bookName,
        author: o.author,
        title: o.title,
        level: o.level,
        page: o.page,
        order: i,
      ));
    }
    await _db.replacePdfOutlines(
        widget.book.name, widget.book.author, renumbered);
    if (mounted) setState(() => _outlines = renumbered);
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
                case 'outline':
                  _showOutlineSheet();
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
              _moreMenuItem('outline', Icons.list_alt_outlined, '目录 / 大纲'),
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
                    tooltip: '上一页',
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
                    tooltip: '下一页',
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


/// 目录面板：展示已落库大纲，点击返回跳转动作，长按返回删除动作。
class _OutlineSheet extends StatelessWidget {
  const _OutlineSheet({required this.outlines, required this.totalPages});

  final List<PdfOutline> outlines;
  final int totalPages;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Text('目录 / 大纲',
                      style: Theme.of(context).textTheme.titleMedium),
                  if (totalPages > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text('共 $totalPages 页',
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant)),
                    ),
                  const Spacer(),
                  IconButton(
                    tooltip: '解析 PDF 内置大纲',
                    icon: const Icon(Icons.auto_stories_outlined),
                    onPressed: () => Navigator.pop(context, 'parse'),
                  ),
                  IconButton(
                    tooltip: '添加目录项',
                    icon: const Icon(Icons.add),
                    onPressed: () => Navigator.pop(context, 'add'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: outlines.isEmpty
                  ? const AppEmptyState(
                      icon: Icons.list_alt_outlined,
                      title: '暂无目录',
                      message: '可解析 PDF 内置大纲，或手动添加目录项后点击跳转',
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: outlines.length,
                      itemBuilder: (ctx, i) {
                        final o = outlines[i];
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.only(
                              left: 16.0 + o.level * 16, right: 16),
                          leading: Icon(Icons.bookmark_outline,
                              size: 18, color: cs.primary),
                          title: Text(o.title,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: Text('${o.page + 1}',
                              style: TextStyle(
                                  fontSize: 12, color: cs.onSurfaceVariant)),
                          onTap: () => Navigator.pop(ctx, 'go:${o.page}'),
                          onLongPress: () => Navigator.pop(ctx, 'del:$i'),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _RawOutline {
  const _RawOutline(this.title, this.level, this.page);
  final String title;
  final int level;
  final int? page;
}

/// PDF 内置 /Outlines 大纲解析（纯 Dart）。
///
/// pdfx 2.6.0 未暴露 pdfium 的 FPDFBookmark_* 接口，因此直接解析 PDF 文件结构：
/// 扫描 `N G obj ... endobj`，把 /ObjStm（FlateDecode）里的压缩对象合并进对象表，
/// 由 /Pages 树建立「页对象编号 -> 0-based 页序」，再沿 /Outlines 的
/// /First -> /Next 链（含 /First 子层级）提取标题与 /Dest、/A /D 的目标页。
/// 加密文档 / 命名目标 / 无内置大纲时返回空列表，由 UI 的手动目录兜底。
class _PdfOutlineParser {
  _PdfOutlineParser._();

  static final RegExp _objRe =
      RegExp(r'(\d+)\s+(\d+)\s+obj\b([\s\S]*?)\bendobj');
  static final RegExp _refRe = RegExp(r'(\d+)\s+\d+\s+R');

  static ({List<PdfOutline> outlines, bool found}) parse(
    Uint8List bytes, {
    required String bookName,
    required String author,
    required int totalPages,
  }) {
    final text = String.fromCharCodes(bytes);
    final objects = <int, String>{};
    for (final m in _objRe.allMatches(text)) {
      final num = int.tryParse(m.group(1)!) ?? -1;
      if (num > 0) objects[num] = m.group(3)!;
    }
    _expandObjectStreams(objects);

    final pageOrder = _buildPageOrder(objects);

    int? root;
    for (final e in objects.entries) {
      if (RegExp(r'/Type\s*/Outlines').hasMatch(e.value)) {
        root = e.key;
        break;
      }
    }
    if (root == null) {
      for (final e in objects.entries) {
        if (RegExp(r'/Type\s*/Catalog').hasMatch(e.value)) {
          root = _firstRef(e.value, '/Outlines');
          if (root != null) break;
        }
      }
    }
    if (root == null) return (outlines: <PdfOutline>[], found: false);

    final raw = <_RawOutline>[];
    final visited = <int>{};
    void walk(int? ref, int level) {
      var cur = ref;
      while (cur != null && visited.add(cur) && raw.length < 5000) {
        final body = objects[cur];
        if (body == null) break;
        raw.add(_RawOutline(
            _decodeTitle(body), level, _destPageRef(body) == null
                ? null
                : pageOrder[_destPageRef(body)]));
        final child = _firstRef(body, '/First');
        if (child != null) walk(child, level + 1);
        cur = _firstRef(body, '/Next');
      }
    }
    walk(_firstRef(objects[root] ?? '', '/First'), 0);

    final list = <PdfOutline>[];
    var lastPage = 0;
    for (final r in raw) {
      if (r.title.isEmpty) continue;
      if (r.page != null) lastPage = r.page!;
      var page = lastPage;
      if (totalPages > 0 && page >= totalPages) page = totalPages - 1;
      if (page < 0) page = 0;
      list.add(PdfOutline(
        bookName: bookName,
        author: author,
        title: r.title,
        level: r.level.clamp(0, 8),
        page: page,
        order: list.length,
      ));
    }
    return (outlines: list, found: true);
  }

  /// 解压 /ObjStm，把其中压缩的间接对象合并进对象表。
  static void _expandObjectStreams(Map<int, String> objects) {
    for (final entry in List.of(objects.entries)) {
      final body = entry.value;
      if (!RegExp(r'/Type\s*/ObjStm').hasMatch(body)) continue;
      final n = int.tryParse(
              RegExp(r'/N\s+(\d+)').firstMatch(body)?.group(1) ?? '') ??
          0;
      final first = int.tryParse(
              RegExp(r'/First\s+(\d+)').firstMatch(body)?.group(1) ?? '') ??
          0;
      if (n <= 0 || first <= 0) continue;
      final start = body.indexOf('stream');
      if (start < 0) continue;
      var dataStart = start + 'stream'.length;
      if (dataStart < body.length && body[dataStart] == '\r') dataStart++;
      if (dataStart < body.length && body[dataStart] == '\n') dataStart++;
      final end = body.indexOf('endstream', dataStart);
      if (end < 0 || end <= dataStart) continue;
      final rawBytes = Uint8List.fromList(
          body.codeUnits.sublist(dataStart, end));
      List<int> decoded;
      try {
        decoded = RegExp(r'/FlateDecode').hasMatch(body)
            ? ZLibCodec().decode(rawBytes)
            : rawBytes;
      } catch (_) {
        continue;
      }
      final inner = String.fromCharCodes(decoded);
      final header =
          inner.substring(0, first.clamp(0, inner.length));
      final pairs = RegExp(r'(\d+)\s+(\d+)').allMatches(header).toList();
      if (pairs.length < n) continue;
      for (var i = 0; i < n; i++) {
        final objNum = int.tryParse(pairs[i].group(1)!) ?? -1;
        final off = int.tryParse(pairs[i].group(2)!) ?? 0;
        final nextOff = i + 1 < n
            ? (int.tryParse(pairs[i + 1].group(2)!) ?? inner.length)
            : inner.length;
        final seg = inner.substring(
            (first + off).clamp(0, inner.length),
            (first + nextOff).clamp(0, inner.length));
        if (objNum > 0) objects.putIfAbsent(objNum, () => seg);
      }
    }
  }

  /// 建立页对象编号 -> 0-based 页序；优先 /Pages 树，回退按对象编号排序。
  static Map<int, int> _buildPageOrder(Map<int, String> objects) {
    final order = <int, int>{};
    int? root;
    for (final e in objects.entries) {
      if (RegExp(r'/Type\s*/Catalog').hasMatch(e.value)) {
        root = _firstRef(e.value, '/Pages');
        if (root != null) break;
      }
    }
    if (root == null) {
      for (final e in objects.entries) {
        if (RegExp(r'/Type\s*/Pages\b').hasMatch(e.value) &&
            !e.value.contains('/Parent')) {
          root = e.key;
          break;
        }
      }
    }
    final visited = <int>{};
    void walk(int? ref) {
      if (ref == null || !visited.add(ref)) return;
      final body = objects[ref];
      if (body == null) return;
      if (RegExp(r'/Type\s*/Page\b').hasMatch(body)) {
        order[ref] = order.length;
        return;
      }
      final kids = RegExp(r'/Kids\s*\[([\s\S]*?)\]').firstMatch(body);
      if (kids == null) return;
      for (final m in _refRe.allMatches(kids.group(1)!)) {
        walk(int.tryParse(m.group(1)!));
      }
    }
    walk(root);
    if (order.isEmpty) {
      final pages = objects.entries
          .where((e) => RegExp(r'/Type\s*/Page\b').hasMatch(e.value))
          .map((e) => e.key)
          .toList()
        ..sort();
      for (var i = 0; i < pages.length; i++) {
        order[pages[i]] = i;
      }
    }
    return order;
  }

  static int? _firstRef(String body, String key) {
    final kidx = body.indexOf(key);
    if (kidx < 0) return null;
    final m = _refRe.firstMatch(body.substring(kidx + key.length));
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  static int? _destPageRef(String body) {
    for (final pattern in [r'/Dest\b', r'/D\b']) {
      final m = RegExp('$pattern([\\s\\S]{0,160})').firstMatch(body);
      if (m == null) continue;
      final ref = _refRe.firstMatch(m.group(1)!);
      if (ref != null) return int.tryParse(ref.group(1)!);
    }
    return null;
  }

  static String _decodeTitle(String body) {
    final m = RegExp(r'/Title\s*').firstMatch(body);
    if (m == null) return '';
    final rest = body.substring(m.end);
    if (rest.startsWith('(')) return _literalString(rest);
    if (rest.startsWith('<')) return _hexString(rest);
    return '';
  }

  static String _literalString(String s) {
    final buf = <int>[];
    var depth = 0;
    var i = 0;
    while (i < s.length) {
      final c = s.codeUnitAt(i);
      if (c == 0x28) {
        depth++;
        if (depth > 1) buf.add(c);
        i++;
        continue;
      }
      if (c == 0x29) {
        depth--;
        if (depth == 0) break;
        buf.add(c);
        i++;
        continue;
      }
      if (c == 0x5C && i + 1 < s.length) {
        final n = s.codeUnitAt(i + 1);
        switch (n) {
          case 0x6E: buf.add(0x0A); i += 2; continue;
          case 0x72: buf.add(0x0D); i += 2; continue;
          case 0x74: buf.add(0x09); i += 2; continue;
          case 0x62: buf.add(0x08); i += 2; continue;
          case 0x66: buf.add(0x0C); i += 2; continue;
          case 0x28: buf.add(0x28); i += 2; continue;
          case 0x29: buf.add(0x29); i += 2; continue;
          case 0x5C: buf.add(0x5C); i += 2; continue;
          case 0x0D:
            i += 2;
            if (i < s.length && s.codeUnitAt(i) == 0x0A) i++;
            continue;
          case 0x0A: i += 2; continue;
          default:
            if (n >= 0x30 && n <= 0x37) {
              var oct = '';
              var j = i + 1;
              while (j < s.length && oct.length < 3 &&
                  s.codeUnitAt(j) >= 0x30 && s.codeUnitAt(j) <= 0x37) {
                oct += s[j];
                j++;
              }
              buf.add(int.parse(oct, radix: 8) & 0xFF);
              i = j;
              continue;
            }
            buf.add(n);
            i += 2;
            continue;
        }
      }
      buf.add(c);
      i++;
    }
    return _fromBytes(buf);
  }

  static String _hexString(String s) {
    final end = s.indexOf('>');
    if (end < 0) return '';
    var hex = s.substring(1, end).replaceAll(RegExp(r'\s'), '');
    if (hex.length.isOdd) hex += '0';
    final bytes = <int>[];
    for (var i = 0; i + 1 < hex.length; i += 2) {
      final v = int.tryParse(hex.substring(i, i + 2), radix: 16);
      if (v == null) return '';
      bytes.add(v);
    }
    return _fromBytes(bytes);
  }

  /// 处理 UTF-16 BOM；否则按 PDFDocEncoding（近似 Latin-1）返回。
  static String _fromBytes(List<int> bytes) {
    List<int> data = bytes;
    bool? bigEndian;
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      bigEndian = true;
      data = bytes.sublist(2);
    } else if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      bigEndian = false;
      data = bytes.sublist(2);
    }
    if (bigEndian != null) {
      final units = <int>[];
      for (var i = 0; i + 1 < data.length; i += 2) {
        units.add(bigEndian
            ? (data[i] << 8) | data[i + 1]
            : (data[i + 1] << 8) | data[i]);
      }
      return String.fromCharCodes(units).trim();
    }
    return String.fromCharCodes(data).trim();
  }
}
