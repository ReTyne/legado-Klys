import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/data/model/explore_kind.dart';
import 'package:legado_md3/data/model/search_book.dart';
import 'package:legado_md3/help/source/source_engine.dart';
import 'package:legado_md3/di/book_provider.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/ui/book/detail/book_detail_screen.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final DatabaseService _db = DatabaseService();
  final BookSourceEngine _engine = BookSourceEngine();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<BookSource> _sources = [];
  BookSource? _currentSource;

  /// 视图层级：选源 -> 选分类 -> 书籍列表
  /// 'source' | 'category' | 'books'
  String _view = 'source';

  /// 发现分类全量（含控件型，对齐 legado exploreKinds 的 ExploreKind 列表）
  List<ExploreKind> _kinds = [];
  ExploreKind? _currentKind;
  Set<String> _hiddenCategories = {};

  /// 发现页控件状态（对齐 legado InfoMap，按书源持久化）
  Map<String, String> _infoMap = {};
  /// 控件输入框控制器（按 title 缓存）
  final Map<String, TextEditingController> _textControllers = {};
  /// 控件动态文字缓存（viewName 求值结果，按 title 缓存）
  final Map<String, String> _viewNames = {};
  /// text 控件动作防抖（对齐 legado 600ms 防抖）
  final Map<String, Timer> _textDebounce = {};
  bool _loadingKinds = false;

  final List<SearchBook> _exploreBooks = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 1;
  String? _error;

  String _searchQuery = '';
  /// 发现书源 chips 是否全部展开（默认限量展示，避免全量构建）
  bool _allSourceChips = false;
  // 0 默认 1 名称 2 作者 3 最新章节
  int _sortMode = 0;
  // 搜索/过滤匹配的字段
  final Set<String> _filterFields = {'name', 'author'};

  @override
  void initState() {
    super.initState();
    _loadSources();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    for (final t in _textDebounce.values) {
      t.cancel();
    }
    for (final c in _textControllers.values) {
      c.dispose();
    }
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  Future<void> _loadSources() async {
    try {
      final sources = await _db.getAllSources(enabled: true);
      // 发现页只显示启用发现（enabledExplore）且配置了发现地址的书源
      final exploreSources = sources
          .where((s) => s.enabledExplore && (s.exploreUrl ?? '').trim().isNotEmpty)
          .toList();
      if (!mounted) return;
      setState(() => _sources = exploreSources);
      // 仅一个发现源时直接进入
      if (_view == 'source' && _sources.length == 1) {
        await _selectSource(_sources.first);
      }
    } catch (_) {
      // 数据库尚未就绪等情况下保持空态，不使页面崩溃
      if (mounted) setState(() {});
    }
  }

  Future<Set<String>> _loadHidden(BookSource source) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList('explore_hidden_${source.bookSourceUrl}') ?? const []).toSet();
  }

  Future<void> _saveHidden(BookSource source, Set<String> hidden) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('explore_hidden_${source.bookSourceUrl}', hidden.toList());
  }

  /// 可见的 url 型分类（控件型不参与显隐管理）
  List<ExploreKind> get _visibleKinds =>
      _kinds.where((k) => k.isUrl && !_hiddenCategories.contains(k.title)).toList();

  /// 控件型分类（text/button/toggle/select）
  List<ExploreKind> get _controlKinds => _kinds.where((k) => k.isControl).toList();

  /// 加载发现分类：exploreUrl 为 `<js>`/`@js:` 时求值（对齐 legado exploreKinds），
  /// 失败时得到 ERROR 占位分类，点击可见错误详情。
  Future<void> _loadKinds(BookSource source) async {
    if (!mounted) return;
    setState(() => _loadingKinds = true);
    List<ExploreKind> kinds;
    try {
      kinds = await _engine.exploreKinds(source);
    } catch (e) {
      kinds = [ExploreKind(title: 'ERROR:$e', url: '')];
    }
    Map<String, String> infoMap;
    try {
      infoMap = await _engine.loadExploreInfoMap(source);
    } catch (_) {
      infoMap = {};
    }
    Set<String> hidden;
    try {
      hidden = await _loadHidden(source);
    } catch (_) {
      hidden = <String>{};
    }
    if (!mounted) return;
    setState(() {
      _loadingKinds = false;
      _kinds = kinds;
      _infoMap = infoMap;
      _hiddenCategories = hidden;
      for (final c in _textControllers.values) {
        c.dispose();
      }
      _textControllers.clear();
      _viewNames.clear();
    });
    // viewName 动态文字（按钮/开关标签可脚本化）
    for (final k in _controlKinds) {
      final vn = k.viewName;
      if (vn != null && vn.trim().isNotEmpty) {
        final label = await _engine.evalExploreViewName(source, vn);
        if (mounted && label.trim().isNotEmpty) {
          setState(() => _viewNames[k.title] = label);
        }
      }
    }
    // 错误占位提示（exploreUrl 求值失败时让用户看到原因）
    final errors = kinds.where((k) => k.isError).toList();
    if (errors.isNotEmpty && mounted) {
      final msg = errors.map((e) => e.title).join('\n');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('发现地址加载异常: $msg'),
        duration: const Duration(seconds: 6),
      ));
    }
  }

  Future<void> _selectSource(BookSource source) async {
    setState(() {
      _currentSource = source;
      _searchQuery = '';
      _searchController.clear();
    });
    await _loadKinds(source);
    if (!mounted) return;
    final controls = _controlKinds;
    final visible = _visibleKinds;
    if (_kinds.isEmpty) {
      setState(() => _view = 'source');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('「${source.bookSourceName}」未配置发现地址')));
      return;
    }
    if (visible.isEmpty && controls.isEmpty) {
      setState(() => _view = 'category');
      return;
    }
    if (visible.length == 1 && controls.isEmpty) {
      _openKind(visible.first);
    } else {
      setState(() => _view = 'category');
    }
  }

  void _back() {
    setState(() {
      if (_view == 'books') {
        // 单分类源没有分类选择层，直接回到选源
        _view = _visibleKinds.length <= 1 && _controlKinds.isEmpty ? 'source' : 'category';
      } else if (_view == 'category') {
        _view = 'source';
      }
    });
  }

  Future<void> _openKind(ExploreKind kind) async {
    if (kind.isError) {
      _showKindError(kind);
      return;
    }
    final url = kind.url?.trim() ?? '';
    if (url.isEmpty) return; // 占位分类（空地址）不响应点击
    setState(() {
      _currentKind = kind;
      _view = 'books';
      _exploreBooks.clear();
      _isLoading = true;
      _hasMore = true;
      _currentPage = 1;
      _error = null;
      _searchQuery = '';
      _searchController.clear();
    });
    await _loadExploreBooks();
  }

  /// 展示 ERROR 占位分类的错误详情（对齐 legado 点击 ERROR 项看堆栈）
  void _showKindError(ExploreKind kind) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('发现地址加载失败'),
        content: SingleChildScrollView(
          child: SelectableText(kind.title.length > 'ERROR:'.length
              ? kind.title.substring('ERROR:'.length)
              : kind.title),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  String _applyPage(String url, int page) {
    var u = url.replaceAll('{{page-1}}', '${page - 1}');
    u = u.replaceAll('{{ page - 1 }}', '${page - 1}');
    u = u.replaceAll('{{page}}', '$page');
    u = u.replaceAll('{{ page }}', '$page');
    return u;
  }

  Future<void> _loadExploreBooks() async {
    final source = _currentSource;
    final kind = _currentKind;
    if (source == null || kind == null) return;
    try {
      final url = _applyPage(kind.url ?? '', _currentPage);
      final books = await _engine.exploreByUrl(source, url);
      if (!mounted) return;
      setState(() {
        _exploreBooks.addAll(books);
        _isLoading = false;
        _isLoadingMore = false;
        if (books.isEmpty) _hasMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        _error = '$e';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasMore || _view != 'books') return;
    final kind = _currentKind;
    if (kind == null || !(kind.url ?? '').contains('{{page')) {
      _hasMore = false;
      return;
    }
    setState(() {
      _isLoadingMore = true;
      _currentPage++;
    });
    await _loadExploreBooks();
  }

  Future<void> _refresh() async {
    if (_view == 'books') {
      setState(() {
        _exploreBooks.clear();
        _isLoading = true;
        _hasMore = true;
        _currentPage = 1;
        _error = null;
      });
      await _loadExploreBooks();
    } else {
      await _loadSources();
    }
  }

  // ==================== 发现页控件（对齐 legado ExploreAdapter） ====================

  /// 执行控件动作（button 点击 / text 防抖后 / toggle 切换后 / select 选择后），
  /// 动作执行完刷新分类（legado 由 java.refreshExplore() 触发，这里统一刷新）。
  Future<void> _runKindAction(ExploreKind kind) async {
    final source = _currentSource;
    if (source == null) return;
    final action = kind.action;
    if (action == null || action.trim().isEmpty) return;
    try {
      await _engine.evalExploreAction(source, action);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('动作执行失败: $e')));
      }
      return;
    }
    if (!mounted) return;
    // 刷新分类与控件状态（动作可能改了配置/infoMap，分类列表随之变化）
    final keepKindTitle = _currentKind?.title;
    await _loadKinds(source);
    if (!mounted) return;
    final stillThere =
        keepKindTitle != null && _visibleKinds.any((k) => k.title == keepKindTitle);
    if (_view == 'books') {
      if (stillThere) {
        // 对齐 legado：refreshExplore 后重取当前分类书籍
        setState(() {
          _exploreBooks.clear();
          _isLoading = true;
          _hasMore = true;
          _currentPage = 1;
          _error = null;
        });
        await _loadExploreBooks();
      } else {
        setState(() => _view = _visibleKinds.length <= 1 && _controlKinds.isEmpty
            ? 'source'
            : 'category');
      }
    }
  }

  TextEditingController _controllerFor(ExploreKind kind) {
    return _textControllers.putIfAbsent(kind.title, () {
      final initial = _infoMap[kind.title] ?? kind.defaultValue ?? '';
      return TextEditingController(text: initial);
    });
  }

  /// 控件区（text/button/toggle/select），分类页与书籍页顶部共用
  Widget _buildControls() {
    final controls = _controlKinds;
    if (controls.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: controls.map(_buildControl).toList(),
      ),
    );
  }

  Widget _buildControl(ExploreKind kind) {
    switch (kind.type) {
      case ExploreKind.typeText:
        final controller = _controllerFor(kind);
        final flex = (kind.style?['layout_flexBasisPercent'] as num?)?.toDouble();
        final field = SizedBox(
          width: flex != null && flex > 0 && flex < 1
              ? MediaQuery.of(context).size.width * flex
              : 220,
          child: TextField(
            controller: controller,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              labelText: kind.title,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onChanged: (v) {
              _infoMap[kind.title] = v;
              final source = _currentSource;
              if (source == null) return;
              _engine.putExploreInfoMap(source, kind.title, v);
              final action = kind.action;
              if (action == null || action.trim().isEmpty) return;
              // 对齐 legado：内容变化后 600ms 防抖触发动作
              _textDebounce[kind.title]?.cancel();
              _textDebounce[kind.title] = Timer(
                  const Duration(milliseconds: 600), () => _runKindAction(kind));
            },
          ),
        );
        return field;
      case ExploreKind.typeButton:
        final label = _viewNames[kind.title] ?? kind.title;
        return FilledButton.tonal(
          onPressed: () => _runKindAction(kind),
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        );
      case ExploreKind.typeToggle:
        final chars = (kind.chars ?? const <String>[]);
        if (chars.isEmpty) return const SizedBox.shrink();
        final current = _infoMap[kind.title] ?? kind.defaultValue ?? chars.first;
        final label = _viewNames[kind.title] ?? kind.title;
        return OutlinedButton(
          onPressed: () {
            final idx = chars.indexOf(current);
            final next = chars[(idx + 1) % chars.length];
            setState(() => _infoMap[kind.title] = next);
            final source = _currentSource;
            if (source != null) {
              _engine.putExploreInfoMap(source, kind.title, next);
            }
            _runKindAction(kind);
          },
          child: Text('$current $label', maxLines: 1, overflow: TextOverflow.ellipsis),
        );
      case ExploreKind.typeSelect:
        final chars = kind.chars ?? const <String>[];
        if (chars.isEmpty) return const SizedBox.shrink();
        var current = _infoMap[kind.title] ?? kind.defaultValue ?? chars.first;
        if (!chars.contains(current)) current = chars.first;
        return SizedBox(
          width: 150,
          child: DropdownButtonFormField<String>(
            value: current,
            isDense: true,
            decoration: InputDecoration(
              labelText: kind.title,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
            items: chars
                .map((c) => DropdownMenuItem<String>(value: c, child: Text(c, style: const TextStyle(fontSize: 13))))
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              setState(() => _infoMap[kind.title] = v);
              final source = _currentSource;
              if (source != null) {
                _engine.putExploreInfoMap(source, kind.title, v);
              }
              _runKindAction(kind);
            },
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  // 过滤 + 排序后的展示列表
  List<SearchBook> get _visibleBooks {
    var list = List<SearchBook>.from(_exploreBooks);
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((b) {
        if (_filterFields.contains('name') && b.name.toLowerCase().contains(q)) return true;
        if (_filterFields.contains('author') && b.author.toLowerCase().contains(q)) return true;
        if (_filterFields.contains('intro') && (b.intro ?? '').toLowerCase().contains(q)) return true;
        if (_filterFields.contains('kind') && (b.kind ?? '').toLowerCase().contains(q)) return true;
        return false;
      }).toList();
    }
    switch (_sortMode) {
      case 1:
        list.sort((a, b) => a.name.compareTo(b.name));
        break;
      case 2:
        list.sort((a, b) => a.author.compareTo(b.author));
        break;
      case 3:
        list.sort((a, b) => (b.lastChapter ?? '').compareTo(a.lastChapter ?? ''));
        break;
    }
    return list;
  }

  void _showSourceSwitcher() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(padding: EdgeInsets.all(16), child: Text('选择发现书源', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
            if (_sources.isEmpty)
              const Padding(padding: EdgeInsets.all(24), child: Text('暂无启用的发现书源'))
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: _sources.map((source) => ListTile(
                    leading: const Icon(Icons.rss_feed),
                    title: Text(source.bookSourceName),
                    subtitle: Text(source.bookSourceUrl, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                    trailing: _currentSource?.bookSourceUrl == source.bookSourceUrl ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary) : null,
                    onTap: () {
                      Navigator.pop(context);
                      _selectSource(source);
                    },
                  )).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 分类管理：显示/隐藏当前书源的发现分类（持久化）
  void _showCategoryManager() {
    final source = _currentSource;
    if (source == null) {
      _showSourceSwitcher();
      return;
    }
    // 仅 url 型分类参与显隐（控件型为功能控件）
    final urlKinds = _kinds.where((k) => k.isUrl).toList();
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('分类管理 · ${source.bookSourceName}'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('勾选要在发现页显示的分类，取消勾选则隐藏',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: urlKinds.map((c) {
                    final hidden = _hiddenCategories.contains(c.title);
                    return CheckboxListTile(
                      dense: true,
                      value: !hidden,
                      title: Text(c.title),
                      onChanged: (v) {
                        setDialogState(() {
                          if (v == true) {
                            _hiddenCategories.remove(c.title);
                          } else {
                            // 至少保留一个可见分类
                            if (urlKinds.length - _hiddenCategories.length <= 1) return;
                            _hiddenCategories.add(c.title);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
            FilledButton(onPressed: () async {
              await _saveHidden(source, _hiddenCategories);
              if (!mounted) return;
              Navigator.pop(context);
              // 重新进入以应用显隐
              await _selectSource(source);
            }, child: const Text('保存')),
          ],
        ),
      ),
    );
  }

  /// 过滤字段选择
  void _showFilterDialog() {
    final labels = {'name': '书名', 'author': '作者', 'intro': '简介', 'kind': '分类'};
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('搜索过滤字段'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: labels.entries.map((e) => CheckboxListTile(
              dense: true,
              title: Text(e.value),
              value: _filterFields.contains(e.key),
              onChanged: (v) => setDialogState(() {
                if (v == true) {
                  _filterFields.add(e.key);
                } else if (_filterFields.length > 1) {
                  _filterFields.remove(e.key);
                }
              }),
            )).toList(),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
          ],
        ),
      ),
    );
  }

  void _showSortDialog() {
    const names = ['默认排序', '按名称', '按作者', '按最新章节'];
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('排序方式'),
        children: List.generate(names.length, (i) => SimpleDialogOption(
          child: Row(children: [
            Icon(i == _sortMode ? Icons.radio_button_checked : Icons.radio_button_off, size: 18,
                color: i == _sortMode ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Text(names[i]),
          ]),
          onPressed: () {
            setState(() => _sortMode = i);
            Navigator.pop(context);
          },
        )),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: _view == 'source'
            ? null
            : IconButton(icon: const Icon(Icons.arrow_back), onPressed: _back),
        title: Text(_titleText(), maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (_view == 'books') ...[
            IconButton(icon: const Icon(Icons.category_outlined), tooltip: '分类', onPressed: _backToCategory),
            IconButton(icon: const Icon(Icons.filter_list), tooltip: '过滤', onPressed: _showFilterDialog),
            IconButton(icon: const Icon(Icons.sort), tooltip: '排序', onPressed: _showSortDialog),
            IconButton(icon: const Icon(Icons.refresh), tooltip: '刷新', onPressed: _refresh),
          ],
          if (_view == 'category')
            IconButton(icon: const Icon(Icons.tune), tooltip: '分类管理', onPressed: _showCategoryManager),
          IconButton(icon: const Icon(Icons.source_outlined), tooltip: '切换书源', onPressed: _showSourceSwitcher),
        ],
      ),
      body: _buildBody(),
    );
  }

  void _backToCategory() {
    final visibleCount = _visibleKinds.length;
    setState(() => _view = visibleCount > 1 || _controlKinds.isNotEmpty ? 'category' : 'source');
  }

  String _titleText() {
    if (_view == 'source') return '发现';
    final name = _currentSource?.bookSourceName ?? '发现';
    if (_view == 'books' && _currentKind != null) return '${_currentKind!.title} · $name';
    return name;
  }

  Widget _buildBody() {
    if (_view == 'source') return _buildSourceChips();
    if (_view == 'category') return _buildCategoryList();
    return _buildBooksList();
  }

  Widget _buildSourceChips() {
    if (_sources.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.explore_off, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text('暂无发现书源', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            const Text('请在「书源管理」中导入书源、配置发现地址并启用发现', style: TextStyle(color: Colors.grey), textAlign: TextAlign.center),
          ],
        ),
      );
    }
    // 书源 chips 限量构建：默认最多 12 个，超出部分由「展开更多」按需展示
    const maxChips = 12;
    final shown = _allSourceChips ? _sources : _sources.take(maxChips).toList();
    final chips = <Widget>[
      ...shown.map((source) => ActionChip(
            avatar: const Icon(Icons.rss_feed, size: 16),
            label: Text(source.bookSourceName),
            onPressed: () => _selectSource(source),
          )),
    ];
    if (_sources.length > maxChips) {
      chips.add(TextButton.icon(
        onPressed: () => setState(() => _allSourceChips = !_allSourceChips),
        icon: Icon(_allSourceChips ? Icons.expand_less : Icons.expand_more,
            size: 18),
        label: Text(_allSourceChips
            ? '收起'
            : '展开更多（${_sources.length - maxChips}）'),
      ));
    }
    return RefreshIndicator(
      onRefresh: _loadSources,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('发现书源', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: chips,
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryList() {
    final visible = _visibleKinds;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(children: [
              Expanded(child: Text('${_currentSource?.bookSourceName ?? ''} 的发现分类', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
              TextButton.icon(onPressed: _showCategoryManager, icon: const Icon(Icons.tune, size: 16), label: const Text('管理')),
            ]),
          ),
          if (_loadingKinds)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          // 控件区（text/button/toggle/select，对齐 legado flexbox 控件）
          _buildControls(),
          ...visible.map((c) {
            if (c.isError) {
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  leading: Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
                  title: Text(c.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                  subtitle: const Text('点击查看错误详情', style: TextStyle(fontSize: 11)),
                  onTap: () => _showKindError(c),
                ),
              );
            }
            final empty = (c.url ?? '').trim().isEmpty;
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                leading: Icon(empty ? Icons.check_box_outline_blank : Icons.folder_outlined),
                title: Text(c.title),
                trailing: empty ? null : const Icon(Icons.chevron_right),
                onTap: () => _openKind(c),
              ),
            );
          }),
          if (!_loadingKinds && visible.isEmpty && _controlKinds.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 48),
              child: Center(child: Text('没有可用的发现分类')),
            ),
        ],
      ),
    );
  }

  Widget _buildBooksList() {
    if (_isLoading && _exploreBooks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _exploreBooks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text('加载失败: $_error', style: const TextStyle(color: Colors.grey), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: _refresh, child: const Text('重试')),
          ],
        ),
      );
    }
    final books = _visibleBooks;
    return Column(
      children: [
        _buildControls(),
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: '过滤当前分类书籍...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchController.clear(); setState(() => _searchQuery = ''); })
                  : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: books.isEmpty
                ? ListView(children: const [SizedBox(height: 200), Center(child: Text('没有匹配的书籍'))])
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: books.length + (_isLoadingMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= books.length) {
                        return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
                      }
                      return _buildBookItem(books[index]);
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildBookItem(SearchBook book) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: _buildCover(book),
        title: Text(book.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(book.author, style: const TextStyle(fontSize: 12)),
            if (book.lastChapter != null && book.lastChapter!.isNotEmpty)
              Text('最新: ${book.lastChapter}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.primary)),
            if (book.intro != null && book.intro!.isNotEmpty)
              Text(book.intro!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.add),
          tooltip: '加入书架',
          onPressed: () async {
            await context.read<BookProvider>().addBook(book.toBook());
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已添加《${book.name}》到书架')));
          },
        ),
        onTap: () {
          final b = book.toBook();
          Navigator.push(context, MaterialPageRoute(builder: (_) => BookDetailScreen(book: b)));
        },
      ),
    );
  }

  Widget _buildCover(SearchBook book) {
    if (book.coverUrl != null && book.coverUrl!.isNotEmpty) {
      // CachedNetworkImage：磁盘 + 内存缓存，并按设备像素比限制解码尺寸
      final dpr = MediaQuery.of(context).devicePixelRatio;
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: CachedNetworkImage(
          imageUrl: book.coverUrl!,
          width: 48,
          height: 66,
          fit: BoxFit.cover,
          memCacheWidth: (100 * dpr).round(),
          memCacheHeight: (133 * dpr).round(),
          placeholder: (_, __) => _defaultCover(book.name),
          errorWidget: (_, __, ___) => _defaultCover(book.name),
        ),
      );
    }
    return _defaultCover(book.name);
  }

  Widget _defaultCover(String name) {
    // 默认占位色板：低饱和深色（与 Material 3 on-surface 体系协调）
    const colors = [Color(0xFF5B6B76), Color(0xFF6E5F56), Color(0xFF4F6B5E), Color(0xFF575F7E), Color(0xFF7E5B57), Color(0xFF6B5B7E)];
    final color = colors[name.hashCode.abs() % colors.length];
    return Container(
      width: 48, height: 66,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
      child: Center(child: Padding(padding: const EdgeInsets.all(4), child: Text(name, maxLines: 3, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)))),
    );
  }
}
