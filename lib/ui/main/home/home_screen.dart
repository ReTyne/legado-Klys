import 'package:flutter/material.dart';
import 'package:legado_md3/ui/book/source/source_manage_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/read_record.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/ui/book/search/search_screen.dart';
import 'package:legado_md3/ui/book/read/reading_screen.dart';
import 'package:legado_md3/ui/book/detail/book_detail_screen.dart';
import 'package:legado_md3/data/model/homepage_module.dart';
import 'package:legado_md3/ui/main/homepage/homepage_manage_screen.dart';
import 'package:legado_md3/ui/main/discover/explore_books_screen.dart';
import 'package:legado_md3/ui/stats/read_record_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DatabaseService _db = DatabaseService();
  List<Book> _recentBooks = [];
  List<ReadRecord> _readRecords = [];
  int _todayMinutes = 0;
  int _totalMinutes = 0;
  int _readingDays = 0;
  int _dailyGoal = 30;
  bool _isLoading = true;
  List<HomepageModule> _modules = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    _dailyGoal = prefs.getInt('daily_goal') ?? 30;

    // 加载最近阅读的书籍
    final books = await _db.getAllBooks();
    _recentBooks = books.where((b) => b.durChapterTime > 0).toList()
      ..sort((a, b) => b.durChapterTime.compareTo(a.durChapterTime));
    if (_recentBooks.length > 6) _recentBooks = _recentBooks.sublist(0, 6);

    // 加载阅读记录
    _readRecords = await _db.getReadRecords(50);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayMs = today.millisecondsSinceEpoch;

    for (final r in _readRecords) {
      final duration = (r.duration as int?) ?? 0;
      _totalMinutes += duration ~/ 60000;
      final readDate = r.date as int?;
      if (readDate != null && readDate >= todayMs) {
        _todayMinutes += duration ~/ 60000;
      }
    }

    // 计算阅读天数
    final days = <String>{};
    for (final r in _readRecords) {
      final readDate = r.date as int?;
      if (readDate != null) {
        final d = DateTime.fromMillisecondsSinceEpoch(readDate);
        days.add('${d.year}-${d.month}-${d.day}');
      }
    }
    _readingDays = days.length;

    // 加载首页模块
    _modules = await _db.getHomepageModules();

    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // 搜索栏
                  _buildSearchBar(),
                  const SizedBox(height: 16),

                  // 首页模块
                  if (_modules.isNotEmpty) ...[
                    _buildModulesSection(),
                    const SizedBox(height: 16),
                  ],

                  // 阅读目标卡片
                  _buildReadingGoalCard(),
                  const SizedBox(height: 16),

                  // 最近阅读
                  if (_recentBooks.isNotEmpty) ...[
                    _buildSectionHeader('最近阅读', onMore: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const ReadRecordScreen()));
                    }),
                    const SizedBox(height: 8),
                    _buildRecentBooks(),
                    const SizedBox(height: 16),
                  ],

                  // 阅读统计
                  _buildSectionHeader('阅读统计'),
                  const SizedBox(height: 8),
                  _buildStatsGrid(),
                  const SizedBox(height: 16),

                  // 快捷功能
                  _buildSectionHeader('快捷功能'),
                  const SizedBox(height: 8),
                  _buildQuickActions(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildSearchBar() {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen())),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Row(
          children: [
            Icon(Icons.search, color: Colors.grey[600]),
            const SizedBox(width: 12),
            Text('搜索书籍、作者...', style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }

  Widget _buildReadingGoalCard() {
    final progress = _dailyGoal > 0 ? (_todayMinutes / _dailyGoal).clamp(0.0, 1.0) : 0.0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('今日阅读', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text('$_todayMinutes / $_dailyGoal 分钟', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              progress >= 1.0 ? '已完成今日目标！' : '还差 ${_dailyGoal - _todayMinutes} 分钟完成目标',
              style: TextStyle(fontSize: 12, color: progress >= 1.0 ? Colors.green : Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, {VoidCallback? onMore}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        if (onMore != null) TextButton(onPressed: onMore, child: const Text('更多')),
      ],
    );
  }

  Widget _buildModulesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('首页模块', onMore: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const HomepageManageScreen()));
        }),
        const SizedBox(height: 8),
        ..._modules.where((m) => m.enabled).map((module) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _buildModuleCard(module),
        )),
      ],
    );
  }

  /// 打开首页模块：解析关联书源与发现地址，跳转到发现书籍列表
  Future<void> _openModule(HomepageModule module) async {
    final sourceUrl = module.sourceUrl;
    if (sourceUrl == null || sourceUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('该模块尚未关联书源，请先在首页管理中配置')));
      return;
    }
    final source = await _db.getSource(sourceUrl);
    if (source == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('关联书源不存在或已删除')));
      return;
    }
    // 优先用模块自带发现地址；否则取书源发现分类的第一个
    var exploreUrl = module.exploreUrl;
    if ((exploreUrl == null || exploreUrl.isEmpty) && source.exploreUrl != null) {
      final firstLine = source.exploreUrl!.split(RegExp(r'\n')).first;
      final firstOpt = firstLine.split('&&&').first;
      final idx = firstOpt.indexOf(':::');
      exploreUrl = idx >= 0 ? firstOpt.substring(idx + 3) : firstOpt;
      // 兼容旧的 :: 分隔
      if (!exploreUrl.contains('http') && firstOpt.contains('::')) {
        final j = firstOpt.indexOf('::');
        exploreUrl = firstOpt.substring(j + 2);
      }
    }
    if (exploreUrl == null || exploreUrl.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('该书源没有可用的发现地址')));
      return;
    }
    if (mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => ExploreBooksScreen(source: source, exploreUrl: exploreUrl!, title: module.name)));
    }
  }

  Widget _buildModuleCard(HomepageModule module) {
    IconData icon;
    Color color;
    switch (module.type) {
      case HomepageModuleType.banner: icon = Icons.image; color = Colors.blue; break;
      case HomepageModuleType.buttonGroup: icon = Icons.smart_button; color = Colors.green; break;
      case HomepageModuleType.card: icon = Icons.credit_card; color = Colors.orange; break;
      case HomepageModuleType.grid: icon = Icons.grid_view; color = Colors.purple; break;
      case HomepageModuleType.gridRanking: icon = Icons.grid_on; color = Colors.teal; break;
      case HomepageModuleType.ranking: icon = Icons.emoji_events; color = Colors.amber; break;
      case HomepageModuleType.waterfall: icon = Icons.view_stream; color = Colors.pink; break;
      case HomepageModuleType.custom: icon = Icons.settings; color = Colors.grey; break;
    }
    return Card(
      child: ListTile(
        leading: CircleAvatar(backgroundColor: color.withOpacity(0.1), child: Icon(icon, color: color)),
        title: Text(module.name),
        subtitle: Text(module.sourceUrl ?? '点击配置书源'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _openModule(module),
      ),
    );
  }

  Widget _buildRecentBooks() {
    return SizedBox(
      height: 160,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _recentBooks.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final book = _recentBooks[index];
          return GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReadingScreen(book: book))),
            onLongPress: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BookDetailScreen(book: book))),
            child: SizedBox(
              width: 100,
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: book.coverUrl != null && book.coverUrl!.isNotEmpty
                        ? Image.network(book.coverUrl!, width: 100, height: 130, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _buildDefaultCover(book))
                        : _buildDefaultCover(book),
                  ),
                  const SizedBox(height: 6),
                  Text(book.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDefaultCover(Book book) {
    final colors = [Colors.blueGrey, Colors.brown, Colors.teal, Colors.indigo, Colors.deepOrange, Colors.purple];
    final color = colors[book.name.hashCode.abs() % colors.length];
    return Container(
      width: 100,
      height: 130,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
      child: Center(child: Padding(padding: const EdgeInsets.all(8), child: Text(book.name, maxLines: 3, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)))),
    );
  }

  Widget _buildStatsGrid() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(child: _buildStatItem('今日阅读', '$_todayMinutes分钟', Icons.today)),
            Expanded(child: _buildStatItem('累计阅读', '${_totalMinutes ~/ 60}小时', Icons.menu_book)),
            Expanded(child: _buildStatItem('阅读天数', '$_readingDays天', Icons.calendar_today)),
            Expanded(child: _buildStatItem('在读书籍', '${_recentBooks.length}本', Icons.library_books)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 24, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildQuickActions() {
    final actions = [
      {'icon': Icons.folder_open, 'label': '本地导入', 'color': Colors.blue},
      {'icon': Icons.cloud_download, 'label': '网络导入', 'color': Colors.green},
      {'icon': Icons.backup_outlined, 'label': '备份恢复', 'color': Colors.orange},
      {'icon': Icons.cleaning_services_outlined, 'label': '缓存管理', 'color': Colors.purple},
      {'icon': Icons.bookmark_border, 'label': '书签管理', 'color': Colors.red},
      {'icon': Icons.find_replace_outlined, 'label': '替换净化', 'color': Colors.teal},
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 16, crossAxisSpacing: 16),
          itemCount: actions.length,
          itemBuilder: (context, index) {
            final action = actions[index];
            return GestureDetector(
              onTap: () => _handleQuickAction(action['label'] as String),
              child: Column(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(color: (action['color'] as Color).withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                    child: Icon(action['icon'] as IconData, color: action['color'] as Color),
                  ),
                  const SizedBox(height: 6),
                  Text(action['label'] as String, style: const TextStyle(fontSize: 12)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _handleQuickAction(String label) {
    switch (label) {
      case '本地导入':
        Navigator.pushNamed(context, '/local_import');
        break;
      case '网络导入':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const SourceManageScreen()));
        break;
      case '备份恢复':
        Navigator.pushNamed(context, '/backup');
        break;
      case '缓存管理':
        Navigator.pushNamed(context, '/cache');
        break;
      case '书签管理':
        Navigator.pushNamed(context, '/bookmark');
        break;
      case '替换净化':
        Navigator.pushNamed(context, '/replace');
        break;
    }
  }
}
