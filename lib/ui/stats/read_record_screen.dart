import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/read_record.dart';
import 'package:legado_md3/help/readaloud/reading_record.dart';
import 'package:legado_md3/ui/config/read_record_config.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 阅读记录（对齐原版 ui/about/ReadRecordActivity）：
/// 搜索过滤、三种排序、总时长统计、单条/全部删除，
/// 以及第十轮 4 项增强：
/// 1. `enableReadRecord` 开关（写 SharedPreferences，供记录写入服务 / 统计页读取）；
/// 2. 点击记录打开书籍 / 无书则按书名跳搜索页；
/// 3. 显示书籍封面（从 books 表取 coverUrl 走统一 BookCover）；
/// 4. 编辑书名 / 作者 / 时长，并同步写入 v14 新增列 deviceId/readTime/lastRead。
class ReadRecordScreen extends StatefulWidget {
  const ReadRecordScreen({super.key});

  @override
  State<ReadRecordScreen> createState() => _ReadRecordScreenState();
}

class _ReadRecordScreenState extends State<ReadRecordScreen> {
  final DatabaseService _db = DatabaseService();
  final ReadingRecordService _recordService = ReadingRecordService();
  List<ReadRecord> _records = [];
  Map<String, Book> _bookMap = {};
  bool _loading = true;
  bool _recordEnabled = true;
  int _totalDuration = 0;
  int _totalDays = 0;
  late final String _deviceId = Platform.localHostname;

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
    final totalDuration = await _recordService.getTotalDuration();
    final books = await _db.getAllBooks();
    final bookMap = <String, Book>{
      for (final b in books) '${b.name}_${b.author}': b,
    };
    final enabled = await ReadRecordConfig.isRecordEnabled();
    final days = <String>{};
    for (final r in records) {
      final d = DateTime.fromMillisecondsSinceEpoch(r.date);
      days.add('${d.year}-${d.month}-${d.day}');
    }
    if (!mounted) return;
    setState(() {
      _records = records;
      _bookMap = bookMap;
      _totalDuration = totalDuration;
      _totalDays = days.length;
      _recordEnabled = enabled;
      _loading = false;
    });
  }

  /// 搜索过滤 + 排序后的可见列表
  List<ReadRecord> get _visibleRecords {
    var list = _records;
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list
          .where((r) =>
              r.bookName.toLowerCase().contains(q) ||
              r.author.toLowerCase().contains(q))
          .toList();
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

  void _tip(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// menu_enable_record：真实开关，写入 enableReadRecord（记录服务 / 统计页消费）。
  Future<void> _toggleRecordEnabled(bool v) async {
    if (!v) {
      final ok = await showAppConfirmDialog(
        context,
        title: '关闭阅读记录',
        content: '关闭后不再统计新的阅读 / 听书时长，已有记录保留。'
            '记录写入服务与阅读统计页会读取 enableReadRecord 键。',
        confirmText: '关闭',
      );
      if (!ok) return;
    }
    setState(() => _recordEnabled = v);
    await ReadRecordConfig.setRecordEnabled(v);
    _tip(v ? '已开启阅读记录' : '已暂停阅读记录');
  }

  /// 点击记录：有书开书，无书搜书名（走统一 readerForBook 分流）。
  Future<void> _openRecord(ReadRecord record) =>
      ReadRecordConfig.openBookOrSearch(context, record.bookName, record.author);

  /// 长按菜单：跳转 / 编辑 / 删除。
  Future<void> _showRecordMenu(ReadRecord record) async {
    await showAppMenuSheet(
      context,
      title: record.bookName,
      items: [
        AppMenuSheetItem(
          title: '打开书籍 / 搜索书名',
          icon: Icons.menu_book_outlined,
          onTap: () => _openRecord(record),
        ),
        AppMenuSheetItem(
          title: '编辑书名与时长',
          icon: Icons.edit_outlined,
          onTap: () => _editRecord(record),
        ),
        AppMenuSheetItem(
          title: '删除这条记录',
          icon: Icons.delete_outline,
          onTap: () => _confirmDelete(record),
        ),
      ],
    );
  }

  /// 编辑记录：书名 / 作者 / 时长（分钟），并同步 v14 新增列。
  Future<void> _editRecord(ReadRecord record) async {
    final nameCtl = TextEditingController(text: record.bookName);
    final authorCtl = TextEditingController(text: record.author);
    final minutesCtl =
        TextEditingController(text: '${(record.duration / 60).round()}');
    final saved = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('编辑阅读记录'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameCtl,
                decoration: const InputDecoration(labelText: '书名')),
            const SizedBox(height: 8),
            TextField(controller: authorCtl,
                decoration: const InputDecoration(labelText: '作者')),
            const SizedBox(height: 8),
            TextField(
              controller: minutesCtl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: '阅读时长（分钟）', hintText: '整数分钟'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false),
              child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true),
              child: const Text('保存')),
        ],
      ),
    );
    if (saved != true || record.id == null) return;
    final minutes = int.tryParse(minutesCtl.text.trim()) ?? 0;
    final seconds = minutes.clamp(0, 100000) * 60;
    final db = await _db.database;
    await db.update(
      'read_records',
      {
        'bookName': nameCtl.text.trim(),
        'author': authorCtl.text.trim(),
        'duration': seconds,
        // v14 新增列：累计时长 / 最后阅读时间 / 设备标识
        'readTime': seconds,
        'lastRead': DateTime.now().millisecondsSinceEpoch,
        'deviceId': _deviceId,
      },
      where: 'id = ?',
      whereArgs: [record.id],
    );
    await _loadRecords();
    _tip('阅读记录已更新');
  }

  /// 手动补记（受 enableReadRecord 真实 gate）：仅开关开启时允许写入。
  Future<void> _addRecord() async {
    if (!_recordEnabled) {
      _tip('阅读记录已暂停，请先开启「启用阅读记录」');
      return;
    }
    final nameCtl = TextEditingController();
    final authorCtl = TextEditingController();
    final minutesCtl = TextEditingController(text: '30');
    final saved = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('手动补记阅读时长'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameCtl,
                decoration: const InputDecoration(labelText: '书名')),
            const SizedBox(height: 8),
            TextField(controller: authorCtl,
                decoration: const InputDecoration(labelText: '作者')),
            const SizedBox(height: 8),
            TextField(
              controller: minutesCtl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '时长（分钟）'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false),
              child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true),
              child: const Text('保存')),
        ],
      ),
    );
    if (saved != true) return;
    final name = nameCtl.text.trim();
    if (name.isEmpty) {
      _tip('书名不能为空');
      return;
    }
    final minutes = int.tryParse(minutesCtl.text.trim()) ?? 0;
    final seconds = minutes.clamp(0, 100000) * 60;
    final now = DateTime.now().millisecondsSinceEpoch;
    final db = await _db.database;
    await db.insert('read_records', {
      'bookName': name,
      'author': authorCtl.text.trim(),
      'duration': seconds,
      'date': now,
      // v14 新增列
      'readTime': seconds,
      'lastRead': now,
      'deviceId': _deviceId,
    });
    await _loadRecords();
    _tip('已补记《$name》$minutes 分钟');
  }

  /// 删除单条记录（确认对话框）
  Future<bool?> _confirmDelete(ReadRecord record) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: '删除记录',
      content: '确定要删除《${record.bookName}》的这条阅读记录吗？',
      confirmText: '删除',
      danger: true,
    );
    if (confirmed) {
      final db = await _db.database;
      if (record.id != null) {
        await db.delete('read_records',
            where: 'id = ?', whereArgs: [record.id]);
      }
      await _loadRecords();
    }
    return confirmed;
  }

  /// 清空全部阅读记录
  Future<void> _clearAllRecords() async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: '清空阅读记录',
      content: '确定要清空所有阅读记录吗？此操作不可恢复。',
      confirmText: '清空',
      danger: true,
    );
    if (confirmed) {
      final db = await _db.database;
      await db.delete('read_records');
      await _loadRecords();
    }
  }

  @override
  Widget build(BuildContext context) {
    final records = _visibleRecords;
    final cs = Theme.of(context).colorScheme;
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
                tooltip: '清除搜索',
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _searching = false;
                    _query = '';
                  });
                }),
          IconButton(
            icon: const Icon(Icons.add_outlined),
            tooltip: '手动补记阅读时长',
            onPressed: _addRecord,
          ),
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
                case 'enable_record':
                  _toggleRecordEnabled(!_recordEnabled);
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
              PopupMenuItem<String>(
                value: 'enable_record',
                child: Row(children: [
                  Icon(_recordEnabled
                      ? Icons.toggle_on_outlined
                      : Icons.toggle_off_outlined,
                      size: 20),
                  const SizedBox(width: 8),
                  Text(_recordEnabled ? '关闭阅读记录' : '开启阅读记录'),
                ]),
              ),
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                value: 'clear_all',
                child: Row(children: [
                  Icon(Icons.delete_sweep_outlined, size: 20, color: cs.error),
                  const SizedBox(width: 8),
                  Text('清空全部记录', style: TextStyle(color: cs.error)),
                ]),
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const AppLoadingIndicator()
          : Column(children: [
              Container(
                padding: const EdgeInsets.all(16),
                color: cs.primaryContainer,
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
              AppSwitchTile(
                title: '启用阅读记录',
                subtitle: _recordEnabled
                    ? 'enableReadRecord：阅读 / 听书会话写入 read_records'
                    : '已暂停：不再生成新的阅读记录',
                value: _recordEnabled,
                onChanged: _toggleRecordEnabled,
              ),
              if (!_recordEnabled)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '阅读记录已暂停，统计页与手动补记同步停用。',
                    style: TextStyle(fontSize: 12, color: cs.onErrorContainer),
                  ),
                ),
              Expanded(
                child: records.isEmpty
                    ? AppEmptyState(
                        icon: Icons.history_outlined,
                        title: _query.isEmpty ? '暂无阅读记录' : '没有匹配的记录',
                        message: _recordEnabled ? null : '记录已暂停',
                      )
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
    final book = _bookMap['${record.bookName}_${record.author}'];
    final cover = book?.coverUrl;
    return Dismissible(
      key: ValueKey('record_${record.id ?? index}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) => _confirmDelete(record),
      onDismissed: (direction) => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('阅读记录已删除')),
          ),
      background: Container(
        alignment: Alignment.centerRight,
        color: Theme.of(context).colorScheme.error,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Icon(Icons.delete, color: Theme.of(context).colorScheme.onError),
      ),
      child: Card(
        child: ListTile(
          leading: BookCover(
            name: record.bookName,
            coverUrl: cover != null && !cover.startsWith('/') ? cover : null,
            localPath: cover != null && cover.startsWith('/') ? cover : null,
            width: 40,
            height: 56,
            radius: 6,
          ),
          title: Text(record.bookName, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${record.author} · $dateStr',
              maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(ReadingRecordService.formatDuration(record.duration),
                style: const TextStyle(fontSize: 12)),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, size: 18),
              tooltip: '删除',
              onPressed: () => _confirmDelete(record),
            ),
          ]),
          // 点击开书 / 搜书名；长按弹编辑与跳转菜单
          onTap: () => _openRecord(record),
          onLongPress: () => _showRecordMenu(record),
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
