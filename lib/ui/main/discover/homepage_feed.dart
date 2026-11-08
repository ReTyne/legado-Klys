import 'package:flutter/material.dart';

import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/data/model/homepage_module.dart';
import 'package:legado_md3/help/source/source_engine.dart';
import 'package:legado_md3/ui/main/discover/homepage_module_widgets.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';

/// 首页卡片式模块化 Feed（fork F16）。
///
/// 数据全部来自现成的 `homepage_modules` / `homepage_custom_sets` 表：
/// - 消费 [DatabaseService.getHomepageModules]：只渲染 enabled 模块；
/// - 消费 [DatabaseService.getHomepageCustomSets] + [HomepageSetStore] 当前模块集：
///   模块集按 moduleIds 过滤并排序，未选模块集时按 DAO 的 customOrder 排序；
/// - 每个模块的卡片优先取 config(JSON)，无内容且有 exploreUrl 时通过
///   [BookSourceEngine.exploreByUrl] 拉取真实发现书籍填充。
/// 点击动作通过 [onAction] 交给宿主页面真实分发（书源发现 / 搜索 / 书籍 / URL）。
class HomepageFeed extends StatefulWidget {
  const HomepageFeed({
    super.key,
    required this.onAction,
    required this.onManage,
    required this.onSwitchToBrowse,
  });

  /// 卡片点击：宿主按 item.action 分发到发现 / 搜索 / 书籍详情 / URL。
  final ValueChanged<HomepageItem> onAction;

  /// 打开首页模块管理页（返回后宿主会重建本 Feed 触发刷新）。
  final VoidCallback onManage;

  /// 切换到原来的「书源发现」列表视图。
  final VoidCallback onSwitchToBrowse;

  @override
  State<HomepageFeed> createState() => _HomepageFeedState();
}

class _FeedSection {
  _FeedSection({required this.module, required this.data});

  final HomepageModule module;
  final HomepageModuleData data;
  List<HomepageItem> items = <HomepageItem>[];
  String? error;
  bool loading = false;
}

class _HomepageFeedState extends State<HomepageFeed> {
  final DatabaseService _db = DatabaseService();
  final BookSourceEngine _engine = BookSourceEngine();

  List<_FeedSection> _sections = <_FeedSection>[];
  List<HomepageCustomSet> _sets = <HomepageCustomSet>[];
  int? _activeSetId;
  bool _loading = true;

  /// 单模块最多展示的卡片数，避免超长 config 拖垮首屏。
  static const int _maxItems = 30;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    // DB 不可用（如单测环境 sqflite 抛 MissingPluginException）时必须结束
    // loading 并显示空态，否则 CircularProgressIndicator 会无限转圈。
    List<HomepageModule> modules = <HomepageModule>[];
    List<HomepageCustomSet> sets = <HomepageCustomSet>[];
    int? activeId;
    try {
      modules = await _db.getHomepageModules();
      sets = await _db.getHomepageCustomSets();
      activeId = await HomepageSetStore.loadActiveSetId();
    } catch (_) {
      // 落到空态，不阻断渲染
    }

    HomepageCustomSet? active;
    for (final s in sets) {
      if (s.id != null && s.id == activeId) {
        active = s;
        break;
      }
    }

    final enabled = modules.where((m) => m.enabled).toList();
    List<HomepageModule> visible;
    if (active != null) {
      final ids = HomepageSetStore.parseModuleIds(active.moduleIds);
      final byId = <int, HomepageModule>{
        for (final m in enabled)
          if (m.id != null) m.id!: m,
      };
      visible = ids.map((id) => byId[id]).whereType<HomepageModule>().toList();
    } else {
      // getHomepageModules 已按 customOrder ASC 排序
      visible = enabled;
    }

    final sections = <_FeedSection>[];
    for (final m in visible) {
      try {
        sections.add(await _resolveSection(m));
      } catch (_) {
        // 单模块解析失败不影响其余模块
      }
    }
    if (!mounted) return;
    setState(() {
      _sections = sections;
      _sets = sets;
      _activeSetId = activeId;
      _loading = false;
    });
  }

  Future<_FeedSection> _resolveSection(HomepageModule module) async {
    final data = HomepageModuleData.fromModule(module);
    final section = _FeedSection(module: module, data: data);
    try {
      if (data.items.isNotEmpty) {
        section.items = data.items.take(_maxItems).toList();
      } else {
        section.items = await _fetchRemoteItems(module);
      }
    } catch (e) {
      section.error = '$e';
    }
    return section;
  }

  /// 无静态 config 时按模块 sourceUrl/exploreUrl 拉取真实发现书籍。
  Future<List<HomepageItem>> _fetchRemoteItems(HomepageModule module) async {
    final url = module.exploreUrl?.trim() ?? '';
    if (url.isEmpty) return <HomepageItem>[];
    BookSource? source;
    final sourceUrl = module.sourceUrl?.trim() ?? '';
    if (sourceUrl.isNotEmpty) {
      source = await _db.getSource(sourceUrl);
    }
    if (source == null) {
      final all = await _db.getAllSources(enabled: true);
      for (final s in all) {
        if (s.enabledExplore && (s.exploreUrl ?? '').trim().isNotEmpty) {
          source = s;
          break;
        }
      }
    }
    if (source == null) return <HomepageItem>[];
    final books = await _engine.exploreByUrl(source, url);
    return books
        .take(_maxItems)
        .map(HomepageItem.fromSearchBook)
        .toList(growable: false);
  }

  Future<void> _switchSet(int? id) async {
    await HomepageSetStore.saveActiveSetId(id);
    await _load();
  }

  Future<void> _retrySection(int index) async {
    if (index < 0 || index >= _sections.length) return;
    setState(() => _sections[index].loading = true);
    final updated = await _resolveSection(_sections[index].module);
    if (!mounted) return;
    setState(() => _sections[index] = updated);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildToolbar(context),
        Expanded(child: _buildBody(context)),
      ],
    );
  }

  Widget _buildToolbar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        children: [
          if (_sets.isNotEmpty)
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _setChip(context, '全部', null),
                    for (final s in _sets)
                      if (s.id != null) _setChip(context, s.name, s.id),
                  ],
                ),
              ),
            )
          else
            const Spacer(),
          IconButton(
            tooltip: '管理首页模块',
            icon: const Icon(Icons.dashboard_customize_outlined),
            onPressed: widget.onManage,
          ),
          IconButton(
            tooltip: '切换到书源发现',
            icon: const Icon(Icons.explore_outlined),
            onPressed: widget.onSwitchToBrowse,
          ),
        ],
      ),
    );
  }

  Widget _setChip(BuildContext context, String label, int? id) {
    final selected = (id == null && _activeSetId == null) ||
        (id != null && id == _activeSetId);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => _switchSet(id),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_sections.isEmpty) return _empty(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: _sections.length,
        itemBuilder: (context, i) {
          final s = _sections[i];
          return HomepageModuleView(
            module: s.module,
            data: s.data,
            items: s.items,
            loading: s.loading,
            error: s.error,
            onTap: widget.onAction,
            onRetry: () => _retrySection(i),
          );
        },
      ),
    );
  }

  Widget _empty(BuildContext context) {
    return AppEmptyState(
      icon: Icons.dashboard_customize_outlined,
      title: '首页暂无模块',
      message: '在「首页模块」中新增模块并启用，即可在此渲染卡片式首页；也可切换到书源发现',
      action: Wrap(
        spacing: 12,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          FilledButton.icon(
            onPressed: widget.onManage,
            icon: const Icon(Icons.add),
            label: const Text('管理首页模块'),
          ),
          OutlinedButton.icon(
            onPressed: widget.onSwitchToBrowse,
            icon: const Icon(Icons.explore_outlined),
            label: const Text('书源发现'),
          ),
        ],
      ),
    );
  }
}
