import 'package:flutter/material.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/help/readaloud/reading_record.dart';
import 'package:legado_md3/ui/config/read_record_config.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';

// 对齐 E：legado-E 无独立「阅读统计」界面，本页为本项目增强页。
// 主入口在 lib/ui/main/my/profile_screen.dart 的「阅读统计」（我的页），
// 并非「无任何主入口引用」。统计开关 / 书籍分布明细 / 点击开书为第十轮补齐。
class ReadingStatsScreen extends StatefulWidget {
  const ReadingStatsScreen({super.key});

  @override
  State<ReadingStatsScreen> createState() => _ReadingStatsScreenState();
}

class _ReadingStatsScreenState extends State<ReadingStatsScreen>
    with SingleTickerProviderStateMixin {
  final ReadingRecordService _recordService = ReadingRecordService();
  final DatabaseService _db = DatabaseService();
  late TabController _tabController;
  int _todayDuration = 0;
  int _totalDuration = 0;
  int _readingDays = 0;
  int _continuousDays = 0;
  Map<String, int> _recentStats = {};
  List<_BookStat> _bookStats = [];
  bool _statsEnabled = true;
  bool _recordEnabled = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadStats();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);
    _todayDuration = await _recordService.getTodayDuration();
    _totalDuration = await _recordService.getTotalDuration();
    _readingDays = await _recordService.getReadingDays();
    _continuousDays = await _recordService.getContinuousDays();
    _recentStats = await _recordService.getRecentStats(30);
    _statsEnabled = await ReadRecordConfig.isStatsEnabled();
    _recordEnabled = await ReadRecordConfig.isRecordEnabled();
    _bookStats = await _loadBookStats();
    if (mounted) setState(() => _isLoading = false);
  }

  /// 按 (书名, 作者) 聚合阅读时长，避免用字符串拼接键时作者含下划线被误拆。
  Future<List<_BookStat>> _loadBookStats() async {
    final records = await _db.getReadRecords();
    final agg = <String, _BookStat>{};
    for (final r in records) {
      final key = '${r.bookName}\u0000${r.author}';
      final stat =
          agg.putIfAbsent(key, () => _BookStat(r.bookName, r.author, 0));
      stat.seconds += r.duration;
    }
    return agg.values.toList()
      ..sort((a, b) => b.seconds.compareTo(a.seconds));
  }

  Future<void> _setStatsEnabled(bool v) async {
    setState(() => _statsEnabled = v);
    await ReadRecordConfig.setStatsEnabled(v);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('阅读统计'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '概览'),
            Tab(text: '时间轴'),
            Tab(text: '书籍分布'),
          ],
        ),
      ),
      body: _isLoading
          ? const AppLoadingIndicator()
          : TabBarView(
              controller: _tabController,
              children: [
                _buildOverviewTab(),
                _buildTimelineTab(),
                _buildBooksTab(),
              ],
            ),
    );
  }

  Widget _buildOverviewTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AppSwitchTile(
          title: '启用阅读统计',
          subtitle: _statsEnabled
              ? 'enableReadingStats：汇总时长、天数与趋势'
              : '已关闭：暂停汇总统计（记录本身仍保留）',
          value: _statsEnabled,
          onChanged: _setStatsEnabled,
        ),
        if (!_recordEnabled)
          _buildPausedBanner('阅读记录已暂停（enableReadRecord），统计不再累加'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildStatCard('今日阅读', ReadingRecordService.formatDuration(_statsEnabled ? _todayDuration : 0), Icons.today)),
            const SizedBox(width: 12),
            Expanded(child: _buildStatCard('累计阅读', ReadingRecordService.formatDuration(_statsEnabled ? _totalDuration : 0), Icons.menu_book)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildStatCard('阅读天数', '${_statsEnabled ? _readingDays : 0} 天', Icons.calendar_today)),
            const SizedBox(width: 12),
            Expanded(child: _buildStatCard('连续阅读', '${_statsEnabled ? _continuousDays : 0} 天', Icons.local_fire_department)),
          ],
        ),
        const SizedBox(height: 24),
        Text('近30天阅读趋势', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        _statsEnabled ? _buildChart() : const AppEmptyState(
          icon: Icons.bar_chart_outlined,
          title: '统计已暂停',
          message: '开启「启用阅读统计」后显示趋势图',
        ),
      ],
    );
  }

  Widget _buildPausedBanner(String text) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text,
          style: TextStyle(fontSize: 12, color: cs.onErrorContainer)),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: theme.colorScheme.primary, size: 24),
            const SizedBox(height: 8),
            Text(value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(title, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _buildChart() {
    if (_recentStats.isEmpty) {
      return const AppEmptyState(
        icon: Icons.bar_chart_outlined,
        title: '暂无数据',
        message: '开始阅读后这里会显示统计图表',
      );
    }
    final entries = _recentStats.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    final maxDuration = entries.map((e) => e.value).fold<int>(0, (a, b) => a > b ? a : b);

    return SizedBox(
      height: 150,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: entries.map((entry) {
          final height = maxDuration > 0 ? (entry.value / maxDuration) * 120 : 0.0;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    height: height,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTimelineTab() {
    if (_recentStats.isEmpty || !_statsEnabled) {
      return const AppEmptyState(
        icon: Icons.bar_chart_outlined,
        title: '暂无阅读记录',
        message: '开始阅读并开启统计后这里会显示记录',
      );
    }

    final entries = _recentStats.entries.toList()..sort((a, b) => b.key.compareTo(a.key));
    final maxVal = entries.map((e) => e.value).fold<int>(0, (a, b) => a > b ? a : b);
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              child: Text(entry.key.split('-').last),
            ),
            title: Text(entry.key),
            subtitle: LinearProgressIndicator(
              value: maxVal > 0 ? entry.value / maxVal : 0,
            ),
            trailing: Text(
              ReadingRecordService.formatDuration(entry.value),
              style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold),
            ),
          ),
        );
      },
    );
  }

  /// 书籍分布明细：每本书累计时长 + 占比，点击开书 / 无书搜书名。
  Widget _buildBooksTab() {
    if (!_statsEnabled || !_recordEnabled) {
      return const AppEmptyState(
        icon: Icons.pie_chart_outline,
        title: '统计已暂停',
        message: '开启「启用阅读统计」与阅读记录后显示书籍分布',
      );
    }
    if (_bookStats.isEmpty) {
      return const AppEmptyState(
        icon: Icons.menu_book_outlined,
        title: '暂无书籍阅读数据',
        message: '阅读任意书籍后这里会按书名汇总时长',
      );
    }
    final maxVal = _bookStats.first.seconds;
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _bookStats.length,
      itemBuilder: (context, index) {
        final s = _bookStats[index];
        return Card(
          child: ListTile(
            leading: BookCover(name: s.name, width: 36, height: 50, radius: 6),
            title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11)),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                    value: maxVal > 0 ? s.seconds / maxVal : 0),
              ],
            ),
            trailing: Text(
              ReadingRecordService.formatDuration(s.seconds),
              style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 12),
            ),
            onTap: () =>
                ReadRecordConfig.openBookOrSearch(context, s.name, s.author),
          ),
        );
      },
    );
  }
}

class _BookStat {
  final String name;
  final String author;
  int seconds;
  _BookStat(this.name, this.author, this.seconds);
}
