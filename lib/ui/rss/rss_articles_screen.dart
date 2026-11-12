import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/rss_source.dart';
import 'package:legado_md3/data/model/rss_article.dart';
import 'package:legado_md3/data/model/rss_read_record.dart';
import 'package:legado_md3/help/http/rss_service.dart';
import 'package:legado_md3/ui/rss/rss_read_screen.dart';
import 'package:legado_md3/ui/rss/rss_search_sheet.dart';
import 'package:legado_md3/ui/rss/rss_source_edit_screen.dart';
import 'package:legado_md3/ui/rss/rss_source_login_screen.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';

/// 订阅源文章列表页： RssArticlesScreen。
/// 支持 sortUrl 分类切换、进入即拉取、缩略图、刷新；结果落库。
/// 顶栏「阅读记录」 ReadRecordDialog（清除 / 开启记录 / 点击续读）。
class RssArticlesScreen extends StatefulWidget {
  const RssArticlesScreen({super.key, required this.source});
  final RssSource source;

  @override
  State<RssArticlesScreen> createState() => _RssArticlesScreenState();
}

class _RssArticlesScreenState extends State<RssArticlesScreen> {
  /// 与 rss_read_screen.dart 共用的全局「开启记录」开关键
  static const _recordEnabledKey = 'rss_read_record_enabled';

  final DatabaseService _db = DatabaseService();
  final RssService _service = RssService();
  late RssSource source;
  late List<RssCategory> _categories;
  RssCategory? _category;
  List<RssArticle> _articles = [];
  bool _loading = true;
  String? _error;
  bool _sortDesc = true;
  bool _recordEnabled = true;

  /// 文章列表布局 0..4（ RssSource.articleStyle 与
  /// RssSortViewModel.switchLayout 的五档循环），按源持久化。
  int _articleStyle = 0;
  static const _layoutKeyPrefix = 'rss_articles_layout_';
  static const List<String> layoutNames = [
    '标准列表', '紧凑列表', '双列网格', '瀑布流', '大图卡片',
  ];

  @override
  void initState() {
    super.initState();
    source = widget.source;
    _categories = _service.parseCategories(source);
    _loadRecordEnabled();
    _loadLayout();
    _load();
  }

  Future<void> _loadLayout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getInt('$_layoutKeyPrefix${source.sourceUrl}') ??
          source.articleStyle ?? 0;
      if (mounted) setState(() => _articleStyle = v.clamp(0, 4));
    } catch (_) {}
  }

  /// 五档布局循环 0→1→2→3→4→0，同时写 SharedPreferences 与 rss_sources 表，
  /// 与上游 RssSortViewModel.switchLayout / RssSource.articleStyle 对齐。
  Future<void> _switchLayout() async {
    final next = (_articleStyle + 1) % 5;
    setState(() => _articleStyle = next);
    source.articleStyle = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('$_layoutKeyPrefix${source.sourceUrl}', next);
      await _db.updateRssSource(source);
    } catch (_) {}
  }

  Future<void> _loadRecordEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() =>
            _recordEnabled = prefs.getBool(_recordEnabledKey) ?? true);
      }
    } catch (_) {}
  }

  Future<void> _setRecordEnabled(bool v) async {
    setState(() => _recordEnabled = v);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_recordEnabledKey, v);
    } catch (_) {}
  }

  /// 按发布时间排序（pubDate 毫秒时间戳，null 按 0 处理）。
  List<RssArticle> _sorted(List<RssArticle> list) {
    final sorted = List<RssArticle>.of(list);
    sorted.sort((a, b) {
      final ta = a.pubDate ?? 0;
      final tb = b.pubDate ?? 0;
      return _sortDesc ? tb.compareTo(ta) : ta.compareTo(tb);
    });
    return sorted;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = _category == null
          ? await _service.fetchRss(source)
          : await _service.fetchCategory(source, _category!);
      for (final a in list) {
        await _db.saveRssArticles([a]);
      }
      if (mounted) {
        setState(() {
          _articles = _sorted(list);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  void _switchCategory() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: const Text('全部（默认）'),
            trailing: _category == null ? const Icon(Icons.check) : null,
            onTap: () {
              Navigator.pop(ctx);
              if (_category != null) {
                setState(() => _category = null);
                _load();
              }
            },
          ),
          for (final c in _categories)
            ListTile(
              title: Text(c.name),
              trailing: _category?.name == c.name
                  ? const Icon(Icons.check)
                  : null,
              onTap: () {
                Navigator.pop(ctx);
                if (_category?.name != c.name) {
                  setState(() => _category = c);
                  _load();
                }
              },
            ),
        ]),
      ),
    );
  }

  Future<void> _openArticle(RssArticle article) async {
    if (article.id != null) {
      await _db.markRssArticleRead(article.id!);
    }
    if (mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              RssReadScreen(article: article, source: source),
        ),
      );
      _load();
    }
  }

  // ===== 文章页菜单（对齐 res/menu/rss_articles.xml）=====

  /// 顶栏「更多」菜单分发：文章内搜索 / 刷新排序 / 源变量 / 编辑源 / 登录 / 清空，
  /// 另含阅读记录与时间排序。每一项都真实作用于数据或页面。
  Future<void> _onMenu(String value) async {
    switch (value) {
      case 'search':
        await _searchArticles();
        break;
      case 'refresh_sort':
        await _refreshSort();
        break;
      case 'source_variable':
        await _editSourceVariable();
        break;
      case 'edit_source':
        await _editSource();
        break;
      case 'login':
        await _loginSource();
        break;
      case 'clear':
        await _clearArticles();
        break;
      case 'switch_layout':
        await _switchLayout();
        break;
      case 'read_record':
        await _showReadRecords();
        break;
      case 'desc':
      case 'asc':
        final desc = value == 'desc';
        if (desc != _sortDesc) {
          setState(() {
            _sortDesc = desc;
            _articles = _sorted(_articles);
          });
        }
        break;
    }
  }

  /// menu_search：在当前源已加载的文章内按关键词检索并可直接打开。
  Future<void> _searchArticles() async {
    await showRssArticleSearchSheet(
      context,
      articles: _articles,
      onOpen: _openArticle,
    );
  }

  /// menu_refresh_sort：重新解析分类并重新拉取文章（清掉旧排序缓存）。
  Future<void> _refreshSort() async {
    setState(() => _categories = _service.parseCategories(source));
    await _load();
  }

  /// menu_set_source_variable：编辑订阅源变量并落库（updateRssSourceVariable）。
  Future<void> _editSourceVariable() async {
    final ctl = TextEditingController(text: source.variable ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('设置源变量'),
        content: TextField(
          controller: ctl,
          maxLines: 6,
          autofocus: true,
          decoration: InputDecoration(
            labelText: '变量（JSON 或 key=value）',
            helperText: (source.variableComment ?? '').trim().isEmpty
                ? '保存后立即生效，并影响后续文章拉取'
                : source.variableComment,
            helperMaxLines: 2,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(d, ctl.text),
              child: const Text('保存')),
        ],
      ),
    );
    ctl.dispose();
    if (result == null) return;
    await _db.updateRssSourceVariable(source.sourceUrl, result);
    setState(() => source.variable = result);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('源变量已保存')),
      );
    }
    await _load();
  }

  /// menu_edit_source：打开订阅源编辑页，返回后重新载入源与文章。
  Future<void> _editSource() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RssSourceEditScreen(source: source)),
    );
    await _reloadSource();
    await _load();
  }

  /// menu_login：打开订阅源登录页（loginUrl / loginUi），返回后同步源。
  Future<void> _loginSource() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RssSourceLoginScreen(source: source)),
    );
    await _reloadSource();
  }

  /// 从库重新读取当前源，拿到编辑 / 登录 / 变量后的最新字段。
  Future<void> _reloadSource() async {
    try {
      final all = await _db.getRssSources();
      for (final s in all) {
        if (s.sourceUrl == source.sourceUrl) {
          if (mounted) setState(() => source = s);
          break;
        }
      }
    } catch (_) {}
  }

  /// menu_clear：清空该订阅源的全部文章（真实删库），对齐 Sigma clearArticles。
  Future<void> _clearArticles() async {
    final ok = await showAppConfirmDialog(
      context,
      title: '清空文章',
      content: '确定清空「${source.sourceName}」的全部文章吗？',
      confirmText: '清空',
      danger: true,
    );
    if (!ok) return;
    final db = await _db.database;
    await db.delete('rss_articles',
        where: 'sourceUrl = ?', whereArgs: [source.sourceUrl]);
    if (mounted) {
      setState(() => _articles = <RssArticle>[]);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已清空该源文章')),
      );
    }
  }

  // ===== 阅读记录=====

  Future<void> _showReadRecords() async {
    List<RssReadRecord> records;
    try {
      records = await _db.getRssReadRecords();
    } catch (_) {
      records = [];
    }
    if (!mounted) return;
    bool enabled = _recordEnabled;
    List<RssReadRecord> current = List.of(records);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l, vertical: AppSpacing.xs),
              child: Row(children: [
                const Expanded(
                    child: Text('阅读记录',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold))),
                IconButton(
                  tooltip: '清除',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    final ok = await showAppConfirmDialog(
                      ctx,
                      title: '清除阅读记录',
                      content: '确定清除全部阅读记录吗？',
                      confirmText: '清除',
                      danger: true,
                    );
                    if (!ok) return;
                    await _db.clearRssReadRecords();
                    setSheet(() => current = []);
                  },
                ),
              ]),
            ),
            SwitchListTile(
              dense: true,
              title: const Text('开启记录'),
              subtitle: const Text('关闭后不再记录 / 恢复阅读位置',
                  style: TextStyle(fontSize: 11)),
              value: enabled,
              onChanged: (v) {
                setSheet(() => enabled = v);
                _setRecordEnabled(v);
              },
            ),
            const Divider(height: 1),
            if (current.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                child: AppEmptyState(
                    icon: Icons.history_outlined, title: '暂无阅读记录'),
              )
            else
              SizedBox(
                height: 320,
                child: ListView.builder(
                  itemCount: current.length,
                  itemBuilder: (c, i) {
                    final rec = current[i];
                    return ListTile(
                      leading: const Icon(Icons.article_outlined),
                      title: Text(
                          rec.title.isEmpty ? rec.link : rec.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        '${_fmtTime(rec.readTime)} · 位置 ${rec.durPos.toInt()}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: Switch(
                        value: rec.enabled != 0,
                        onChanged: (v) async {
                          await _db.toggleRssReadRecordEnabled(
                              rec.link, v ? 1 : 0);
                          setSheet(() {
                            final idx = current
                                .indexWhere((e) => e.link == rec.link);
                            if (idx >= 0) current[idx].enabled = v ? 1 : 0;
                          });
                        },
                      ),
                      onTap: () => _resume(rec, ctx),
                    );
                  },
                ),
              ),
          ]),
        ),
      ),
    );
  }

  String _fmtTime(int? t) {
    if (t == null || t <= 0) return '未记录时间';
    return DateTime.fromMillisecondsSinceEpoch(t).toString().substring(0, 16);
  }

  /// 点击历史记录续读：优先从库里按 link 找回完整文章，否则用记录构造。
  Future<void> _resume(RssReadRecord rec, BuildContext sheetCtx) async {
    RssArticle article;
    try {
      final all = await _db.getRssArticles();
      RssArticle? found;
      for (final a in all) {
        if (a.link == rec.link) {
          found = a;
          break;
        }
      }
      article = found ??
          RssArticle(
            title: rec.title.isEmpty ? rec.link : rec.title,
            link: rec.link,
            sourceUrl: rec.sourceUrl.isEmpty ? null : rec.sourceUrl,
            sourceName: rec.sourceUrl.isEmpty ? null : rec.sourceUrl,
          );
    } catch (_) {
      article = RssArticle(
        title: rec.title.isEmpty ? rec.link : rec.title,
        link: rec.link,
        sourceUrl: rec.sourceUrl.isEmpty ? null : rec.sourceUrl,
      );
    }
    if (!mounted) return;
    if (sheetCtx.mounted) Navigator.pop(sheetCtx);
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RssReadScreen(article: article)),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final title = _category?.name ?? source.sourceName;
    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (_categories.isNotEmpty)
            IconButton(
              tooltip: '分类',
              icon: const Icon(Icons.category_outlined),
              onPressed: _switchCategory,
            ),
          IconButton(
            tooltip: '文章内搜索',
            icon: const Icon(Icons.search_outlined),
            onPressed: _searchArticles,
          ),
          IconButton(
            tooltip: '切换布局（当前：${layoutNames[_articleStyle]}）',
            icon: Icon(_articleStyle == 2 || _articleStyle == 3
                ? Icons.grid_view_outlined
                : Icons.view_list_outlined),
            onPressed: _switchLayout,
          ),
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
          // 对齐 rss_articles.xml 的溢出菜单：搜索 / 登录 / 刷新排序 /
          // 源变量 / 编辑源 / 切换布局 / 阅读记录 / 清空。
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: _onMenu,
            itemBuilder: (context) => [
              const PopupMenuItem<String>(
                value: 'search',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.search_outlined),
                  title: Text('文章内搜索'),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'refresh_sort',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.refresh_outlined),
                  title: Text('刷新排序'),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'source_variable',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.data_object_outlined),
                  title: Text('设置源变量'),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'edit_source',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.edit_outlined),
                  title: Text('编辑源'),
                ),
              ),
              if ((source.loginUrl ?? '').trim().isNotEmpty ||
                  (source.loginUi ?? '').trim().isNotEmpty)
                const PopupMenuItem<String>(
                  value: 'login',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.login_outlined),
                    title: Text('登录'),
                  ),
                ),
              PopupMenuItem<String>(
                value: 'switch_layout',
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.dashboard_outlined),
                  title: Text('切换布局（当前：${layoutNames[_articleStyle]}）'),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'read_record',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.history_outlined),
                  title: Text('阅读记录'),
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                value: 'desc',
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.arrow_downward),
                  title: const Text('时间倒序'),
                  trailing: _sortDesc ? const Icon(Icons.check) : null,
                ),
              ),
              PopupMenuItem<String>(
                value: 'asc',
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.arrow_upward),
                  title: const Text('时间正序'),
                  trailing: !_sortDesc ? const Icon(Icons.check) : null,
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'clear',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.delete_outline),
                  title: Text('清空文章'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const AppLoadingIndicator()
          : _error != null
              ? AppErrorState(message: _error!, onRetry: _load)
              : _articles.isEmpty
                  ? _empty()
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: _buildBody(),
                    ),
    );
  }

  /// 按 articleStyle 分派五种布局。
  Widget _buildBody() {
    switch (_articleStyle) {
      case 1:
        return _buildCompactList();
      case 2:
        return _buildGrid(columns: 2);
      case 3:
        // 上游 style=3 为瀑布流，横屏三列、竖屏两列。
        return _buildGrid(
          columns: MediaQuery.orientationOf(context) == Orientation.landscape
              ? 3
              : 2,
          aspect: 0.70,
        );
      case 4:
        return _buildLargeCardList();
      default:
        return _buildList();
    }
  }

  /// 紧凑列表：无分隔线、更小留白。
  Widget _buildCompactList() => ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
        itemCount: _articles.length,
        itemBuilder: (c, i) => _tile(_articles[i]),
      );

  /// 大图卡片列表：复用网格卡片但每项固定高度，突出封面。
  Widget _buildLargeCardList() => ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.m),
        itemCount: _articles.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.m),
        itemBuilder: (c, i) => SizedBox(
          height: 220,
          child: _gridTile(_articles[i]),
        ),
      );

  Widget _buildList() => ListView.separated(
        itemCount: _articles.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (c, i) => _tile(_articles[i]),
      );

  Widget _buildGrid({int columns = 2, double aspect = 0.82}) =>
      GridView.builder(
        padding: const EdgeInsets.all(AppSpacing.m),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: AppSpacing.s,
          crossAxisSpacing: AppSpacing.s,
          childAspectRatio: aspect,
        ),
        itemCount: _articles.length,
        itemBuilder: (c, i) => _gridTile(_articles[i]),
      );

  Widget _gridTile(RssArticle article) {
    final cs = Theme.of(context).colorScheme;
    final read = article.read == true;
    final image = article.image ?? '';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openArticle(article),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SizedBox.expand(
                child: image.isNotEmpty
                    ? Image.network(
                        image,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _gridPlaceholder(cs),
                      )
                    : _gridPlaceholder(cs),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.s),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    article.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          read ? FontWeight.normal : FontWeight.bold,
                    ),
                  ),
                  if ((article.description ?? '').isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      article.description!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 10, color: cs.onSurfaceVariant),
                    ),
                  ],
                  const SizedBox(height: 3),
                  Text(
                    article.sourceName ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: cs.primary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gridPlaceholder(ColorScheme cs) => Container(
        color: cs.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(Icons.article_outlined, size: 32, color: cs.onSurfaceVariant),
      );

  Widget _tile(RssArticle article) {
    final cs = Theme.of(context).colorScheme;
    final read = article.read == true;
    return ListTile(
      leading: _thumb(article),
      title: Text(
        article.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: read ? FontWeight.normal : FontWeight.bold,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ((article.description ?? '').isNotEmpty)
            Text(article.description!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 2),
          Text(
            '${article.sourceName ?? ''} ${article.pubDate != null ? DateTime.fromMillisecondsSinceEpoch(article.pubDate!).toString().substring(0, 16) : ''}',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ],
      ),
      trailing: read
          ? Icon(Icons.check_circle_outline,
              size: 18, color: cs.onSurfaceVariant)
          : Icon(Icons.fiber_new, size: 18, color: cs.error),
      onTap: () => _openArticle(article),
    );
  }

  Widget _thumb(RssArticle article) {
    if ((article.image ?? '').isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.network(
          article.image!,
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _iconBox(article),
        ),
      );
    }
    return _iconBox(article);
  }

  Widget _iconBox(RssArticle article) => Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Icon(Icons.article_outlined, size: 24),
      );

  Widget _empty() => AppEmptyState(
        icon: Icons.article_outlined,
        title: '暂无文章',
        message: '下拉刷新或点击重试获取文章',
        action: FilledButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: const Text('重新加载'),
        ),
      );
}
