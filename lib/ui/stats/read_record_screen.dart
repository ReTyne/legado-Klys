import 'package:flutter/material.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/read_record.dart';
import 'package:legado_md3/help/readaloud/reading_record.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 阅读记录（对齐原版 ui/about/ReadRecordActivity）：
/// 搜索过滤、排序（名称/阅读时长/最近阅读时间，升降序）、总阅读时长统计、单条/全部删除
class ReadRecordScreen extends StatefulWidget {
  const ReadRecordScreen({super.key});

  @override
  State<ReadRecordScreen> createState() => _ReadRecordScreenState();
}

class _ReadRecordScreenState extends State<ReadRecordScreen> {
  final DatabaseService _db = DatabaseService();
  final ReadingRecordService _recordService = ReadingRecordService();
  List<ReadRecord> _records = [];
  bool _loading = true;
  int _totalDuration = 0;
  int _totalDays = 0;

  String _query = '';
  bool _searching = false;
  final TextEditingController _searchController = TextEditingController();

  /// 排序模式：0 按名称 1 按阅读时长 2 按最近阅读时间
  int _sortMode = 2;
  bool _sortAsc = false;

  @override
  void initState() {
    super.initState();
    _loadSort();
    _loadRecords();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSort() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _sortMode = (p.getInt('readRecordSort') ?? 2).clamp(0, 2);
      _sortAsc = p.getBool('readRecordSortAsc') ?? false;
    });
  }

  /// 选择排序模式；再次点击同一模式则切换升降序
  Future<void> _setSort(int mode) async {
    setState(() {
      if (_sortMode == mode) {
        _sortAsc = !_sortAsc;
      } else {
        _sortMode = mode;
        _sortAsc = mode == 0; // 名称默认升序，时长/时间默认降序
      }
    });
    final p = await SharedPreferences.getInstance();
    await p.setInt('readRecordSort', _sortMode);
    await p.setBool('readRecordSortAsc', _sortAsc);
  }

  Future<void> _toggleAsc() async {
    setState(() => _sortAsc = !_sortAsc);
    final p = await SharedPreferences.getInstance();
    await p.setBool('readRecordSortAsc', _sortAsc);
  }

  Future<void> _loadRecords() async {
    final records = await _db.getReadRecords();
    // 总阅读时长汇总所有记录（含历史全部数据）
    final totalDuration = await _recordService.getTotalDuration();
    final days = <String>{};
    for (final r in records) {
      final d = DateTime.fromMillisecondsSinceEpoch(r.date);
      days.add('${d.year}-${d.month}-${d.day}');
    }
    if (!mounted) return;
    setState(() {
      _records = records;
      _totalDuration = totalDuration;
      _totalDays = days.length;
      _loading = false;
    });
  }

  /// 搜索过滤 + 排序后的可见列表
  List<ReadRecord> get _visibleRecords {
    var list = _records;
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list.where((r) => r.bookName.toLowerCase().contains(q)).toList();
    }
    final sorted = List<ReadRecord>.of(list);
    sorted.sort((a, b) {
      switch (_sortMode) {
        case 0:
          return _sortAsc
              ? a.bookName.compareTo(b.bookName)
              : b.bookName.compareTo(a.bookName);
        case 1:
          return _sortAsc
              ? a.duration.compareTo(b.duration)
              : b.duration.compareTo(a.duration);
        default:
          return _sortAsc ? a.date.compareTo(b.date) : b.date.compareTo(a.date);
      }
    });
    return sorted;
  }

  /// 删除单条记录（确认对话框）
  Future<bool?> _confirmDelete(ReadRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除记录'),
        content: Text('确定要删除《${record.bookName}》的这条阅读记录吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final db = await _db.database;
      if (record.id != null) {
        await db.delete('read_records',
            where: 'id = ?', whereArgs: [record.id]);
      }
      await _loadRecords();
    }
    return confirmed ?? false;
  }

  /// 清空全部阅读记录
  Future<void> _clearAllRecords() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空阅读记录'),
        content: const Text('确定要清空所有阅读记录吗？此操作不可恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final db = await _db.database;
      await db.delete('read_records');
      await _loadRecords();
    }
  }

  @override
  Widget build(BuildContext context) {
    final records = _visibleRecords;
    return Scaffold(
      appBar: AppBar(
        title: !_searching
            ? const Text('阅读记录')
            : TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                    hintText: '搜索书名...', border: InputBorder.none),
                onChanged: (v) => setState(() => _query = v),
              ),
        actions: [
          if (!_searching)
            IconButton(
                icon: const Icon(Icons.search),
                tooltip: '搜索',
                onPressed: () => setState(() => _searching = true)),
          if (_searching)
            IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _searching = false;
                    _query = '';
                  });
                }),
          PopupMenuButton<String>(
            tooltip: '排序与更多',
            onSelected: (v) {
              switch (v) {
                case 'sort_name':
                  _setSort(0);
                  break;
                case 'sort_duration':
                  _setSort(1);
                  break;
                case 'sort_date':
                  _setSort(2);
                  break;
                case 'toggle_asc':
                  _toggleAsc();
                  break;
                case 'clear_all':
                  _clearAllRecords();
                  break;
              }
            },
            itemBuilder: (context) => [
              _sortMenuItem('sort_name', 0, '按名称', Icons.sort_by_alpha),
              _sortMenuItem('sort_duration', 1, '按阅读时长', Icons.timer_outlined),
              _sortMenuItem('sort_date', 2, '按最近阅读时间', Icons.schedule),
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                value: 'toggle_asc',
                child: Row(children: [
                  Icon(_sortAsc ? Icons.arrow_downward : Icons.arrow_upward,
                      size: 20),
                  const SizedBox(width: 8),
                  Text(_sortAsc ? '切换为降序' : '切换为升序'),
                ]),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'clear_all',
                child: Row(children: [
                  Icon(Icons.delete_sweep_outlined, size: 20, color: Colors.red),
                  SizedBox(width: 8),
                  Text('清空全部记录', style: TextStyle(color: Colors.red)),
                ]),
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Container(
                padding: const EdgeInsets.all(16),
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStat('阅读天数', '$_totalDays天'),
                    _buildStat(
                        '总阅读时长', ReadingRecordService.formatDuration(_totalDuration)),
                    _buildStat('记录数', '${_records.length}条'),
                  ],
                ),
              ),
              Expanded(
                child: records.isEmpty
                    ? Center(
                        child: Text(_query.isEmpty ? '暂无阅读记录' : '没有匹配的记录',
                            style: TextStyle(color: Colors.grey[600])))
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: records.length,
                        itemBuilder: (context, index) =>
                            _buildRecordItem(records[index], index),
                      ),
              ),
            ]),
    );
  }

  PopupMenuItem<String> _sortMenuItem(
      String value, int mode, String label, IconData icon) {
    final selected = _sortMode == mode;
    return PopupMenuItem<String>(
      value: value,
      child: Row(children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(label)),
        if (selected)
          Icon(
            _sortAsc ? Icons.arrow_upward : Icons.arrow_downward,
            size: 18,
            color: Theme.of(context).colorScheme.primary,
          ),
      ]),
    );
  }

  Widget _buildRecordItem(ReadRecord record, int index) {
    final date = DateTime.fromMillisecondsSinceEpoch(record.date);
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return Dismissible(
      key: ValueKey('record_${record.id ?? index}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) => _confirmDelete(record),
      onDismissed: (direction) {},
      background: Container(
        alignment: Alignment.centerRight,
        color: Colors.red,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: Card(
        child: ListTile(
          leading: CircleAvatar(
              child:
                  Text(record.bookName.isNotEmpty ? record.bookName[0] : '?')),
          title: Text(record.bookName),
          subtitle: Text('${record.author} · $dateStr'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(ReadingRecordService.formatDuration(record.duration),
                style: const TextStyle(fontSize: 12)),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: '删除',
              onPressed: () => _confirmDelete(record),
            ),
          ]),
          onLongPress: () => _confirmDelete(record),
        ),
      ),
    );
  }

  Widget _buildStat(String label, String value) {
    return Column(children: [
      Text(value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      Text(label, style: const TextStyle(fontSize: 12)),
    ]);
  }
}
