import 'package:flutter/material.dart';
import 'package:legado_md3/help/readaloud/reading_record.dart';

class ReadingStatsScreen extends StatefulWidget {
  const ReadingStatsScreen({super.key});

  @override
  State<ReadingStatsScreen> createState() => _ReadingStatsScreenState();
}

class _ReadingStatsScreenState extends State<ReadingStatsScreen> with SingleTickerProviderStateMixin {
  final ReadingRecordService _recordService = ReadingRecordService();
  late TabController _tabController;
  int _todayDuration = 0;
  int _totalDuration = 0;
  int _readingDays = 0;
  int _continuousDays = 0;
  Map<String, int> _recentStats = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
    if (mounted) setState(() => _isLoading = false);
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
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildOverviewTab(),
                _buildTimelineTab(),
              ],
            ),
    );
  }

  Widget _buildOverviewTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(child: _buildStatCard('今日阅读', ReadingRecordService.formatDuration(_todayDuration), Icons.today)),
            const SizedBox(width: 12),
            Expanded(child: _buildStatCard('累计阅读', ReadingRecordService.formatDuration(_totalDuration), Icons.menu_book)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildStatCard('阅读天数', '$_readingDays 天', Icons.calendar_today)),
            const SizedBox(width: 12),
            Expanded(child: _buildStatCard('连续阅读', '$_continuousDays 天', Icons.local_fire_department)),
          ],
        ),
        const SizedBox(height: 24),
        Text('近30天阅读趋势', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        _buildChart(),
      ],
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
      return const Center(child: Text('暂无数据'));
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
                      borderRadius: BorderRadius.circular(2),
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
    if (_recentStats.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bar_chart_outlined, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('暂无阅读记录', style: TextStyle(fontSize: 18, color: Colors.grey[600])),
            const SizedBox(height: 8),
            const Text('开始阅读后这里会显示记录'),
          ],
        ),
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
}
