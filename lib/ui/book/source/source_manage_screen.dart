
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/help/source/source_engine.dart';
import 'package:legado_md3/ui/book/source/source_debug_screen.dart';
import 'package:legado_md3/ui/book/source/source_edit_screen.dart';
import 'package:legado_md3/ui/book/source/source_login_screen.dart';
import 'package:legado_md3/ui/book/source/qr_share_screen.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:share_plus/share_plus.dart';

class SourceManageScreen extends StatefulWidget {
  const SourceManageScreen({super.key});

  @override
  State<SourceManageScreen> createState() => _SourceManageScreenState();
}

class _SourceManageScreenState extends State<SourceManageScreen> {
  final DatabaseService _db = DatabaseService();
  List<BookSource> _sources = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String? _selectedGroup;
  int _sortBy = 0; // 0=手动 1=权重 2=名称 3=URL 4=更新时间 5=响应时间 6=启用
  bool _sortAsc = true;
  bool _selectMode = false;
  bool _groupByDomain = false;
  final Set<String> _selectedIds = {};
  List<String> _groups = [];

  @override
  void initState() {
    super.initState();
    _loadSources();
  }

  Future<void> _loadSources() async {
    setState(() => _isLoading = true);
    _sources = await _db.getAllSources();
    _groups = _sources
        .map((s) => s.bookSourceGroup)
        .whereType<String>().where((g) => g.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    if (mounted) setState(() => _isLoading = false);
  }

  List<BookSource> get _filteredSources {
    var result = _sources;
    if (_selectedGroup != null) {
      result = result.where((s) => s.bookSourceGroup == _selectedGroup).toList();
    }
    if (_searchQuery.isNotEmpty) {
      result = result
          .where((s) =>
              s.bookSourceName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              s.bookSourceUrl.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
    }
    // 排序
    result = List.from(result);
    switch (_sortBy) {
      case 1: result.sort((a, b) => _sortAsc ? a.weight.compareTo(b.weight) : b.weight.compareTo(a.weight)); break;
      case 2: result.sort((a, b) => _sortAsc ? a.bookSourceName.compareTo(b.bookSourceName) : b.bookSourceName.compareTo(a.bookSourceName)); break;
      case 3: result.sort((a, b) => _sortAsc ? a.bookSourceUrl.compareTo(b.bookSourceUrl) : b.bookSourceUrl.compareTo(a.bookSourceUrl)); break;
      case 4: result.sort((a, b) => _sortAsc ? (a.lastUpdateTime ?? 0).compareTo(b.lastUpdateTime ?? 0) : (b.lastUpdateTime ?? 0).compareTo(a.lastUpdateTime ?? 0)); break;
      case 5: result.sort((a, b) => _sortAsc ? (a.respondTime ?? 0).compareTo(b.respondTime ?? 0) : (b.respondTime ?? 0).compareTo(a.respondTime ?? 0)); break;
      case 6: result.sort((a, b) => _sortAsc ? (a.enabled ? 0 : 1).compareTo(b.enabled ? 0 : 1) : (b.enabled ? 0 : 1).compareTo(a.enabled ? 0 : 1)); break;
    }
    return result;
  }

  Future<void> _toggleSource(BookSource source, bool enabled) async {
    source.enabled = enabled;
    await _db.updateSource(source);
    setState(() {});
  }

  void _showSourceLogin(BookSource source) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SourceLoginScreen(source: source),
    ));
  }

  Future<void> _deleteSource(BookSource source) async {
    await _db.deleteSource(source.bookSourceUrl);
    _loadSources();
  }

  void _showAddMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_link),
              title: const Text('网络导入'),
              subtitle: const Text('从URL导入书源JSON'),
              onTap: () {
                Navigator.pop(context);
                _showImportDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('新建书源'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SourceEditScreen()),
                ).then((_) => _loadSources());
              },
            ),
            ListTile(
              leading: const Icon(Icons.content_paste),
              title: const Text('剪贴板导入'),
              subtitle: const Text('从剪贴板粘贴书源JSON'),
              onTap: () {
                Navigator.pop(context);
                _importFromClipboard();
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('本地导入'),
              subtitle: const Text('从JSON文件导入'),
              onTap: () {
                Navigator.pop(context);
                _importFromFile();
              },
            ),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text('导出书源'),
              subtitle: const Text('导出所有书源为JSON'),
              onTap: () {
                Navigator.pop(context);
                _exportSources();
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.qr_code_scanner),
              title: const Text('二维码导入'),
              subtitle: const Text('扫描二维码导入书源'),
              onTap: () async {
                Navigator.pop(context);
                final code = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const QrScannerScreen(title: '扫描书源二维码')));
                if (code == null || code.isEmpty) return;
                final text = code.trim();
                if (text.startsWith('http')) {
                  _importFromUrl(text);
                } else {
                  final n = await _importSourcesFromString(text);
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入 $n 个书源')));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.domain),
              title: const Text('按域名分组'),
              subtitle: const Text('自动按域名分组显示'),
              onTap: () {
                Navigator.pop(context);
                setState(() => _groupByDomain = !_groupByDomain);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_groupByDomain ? '已按域名分组' : '已取消域名分组')));
              },
            ),
            ListTile(
              leading: const Icon(Icons.verified_outlined),
              title: const Text('书源校验'),
              subtitle: const Text('校验所有书源可用性'),
              onTap: () {
                Navigator.pop(context);
                _validateSources();
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_special),
              title: const Text('分组管理'),
              onTap: () {
                Navigator.pop(context);
                _showGroupManageDialog();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _importFromUrl(String url) async {
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        responseType: ResponseType.bytes,
      ));
      final response = await dio.get<List<int>>(url);
      final bytes = response.data ?? [];
      // 检测 gzip 压缩（特殊书源常用 gzip 传输但可能无 Content-Encoding 头）
      var body = '';
      if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
        body = utf8.decode(gzip.decode(bytes));
      } else {
        body = utf8.decode(bytes);
      }
      final count = await _importSourcesFromString(body);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(count > 0 ? '成功导入 $count 个书源' : '未识别到有效书源')),
        );
      }
      _loadSources();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e')),
        );
      }
    }
  }

  /// 从字符串解析并导入书源，兼容 JSON 数组/单对象/包装对象/JSONL
  Future<int> _importSourcesFromString(String raw) async {
    var text = raw.trim();
    if (text.isEmpty) return 0;
    // 去除 BOM 与常见包裹
    if (text.startsWith('﻿')) text = text.substring(1);
    dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      // 可能是 JSONL：逐行一个对象
      final lines = text.split(RegExp(r'[\r\n]+')).where((l) => l.trim().startsWith('{')).toList();
      if (lines.isEmpty) rethrow;
      final arr = [];
      for (final l in lines) {
        try { arr.add(jsonDecode(l)); } catch (_) {}
      }
      decoded = arr;
    }
    return _importSourcesFromData(decoded);
  }

  Future<void> _importFromFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'txt'],
      );
      if (result == null || result.files.isEmpty || result.files.first.path == null) return;
      final file = File(result.files.first.path!);
      final bytes = await file.readAsBytes();
      // 检测 gzip 压缩
      var content = '';
      if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
        content = utf8.decode(gzip.decode(bytes));
      } else {
        content = utf8.decode(bytes);
      }
      int count = await _importSourcesFromString(content);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('成功导入 $count 个书源')),
        );
      }
      _loadSources();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e')),
        );
      }
    }
  }

  Future<void> _importFromClipboard() async {
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      if (clipboardData == null || clipboardData.text == null || clipboardData.text!.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('剪贴板为空')),
        );
        return;
      }
      int count = await _importSourcesFromString(clipboardData.text!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('成功导入 $count 个书源')),
        );
      }
      _loadSources();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e')),
        );
      }
    }
  }

  Future<void> _exportSources() async {
    try {
      final sources = await _db.getAllSources();
      if (sources.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有可导出的书源')),
        );
        return;
      }
      final jsonStr = const JsonEncoder.withIndent('  ').convert(
        sources.map((s) => s.toJson()).toList(),
      );
      // 复制到剪贴板
      await Clipboard.setData(ClipboardData(text: jsonStr));
      // 同时分享
      final tempFile = File('${Directory.systemTemp.path}/book_sources.json');
      await tempFile.writeAsString(jsonStr);
      await Share.shareXFiles([XFile(tempFile.path)], text: 'Legado书源导出 (${sources.length}个)');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导出 ${sources.length} 个书源（已复制到剪贴板）')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    }
  }

  Future<int> _importSourcesFromData(dynamic data) async {
    // 解包常见订阅格式：{data:[...]} / {bookSources:[...]} / {result:[...]}
    dynamic unwrapped = data;
    if (unwrapped is Map && !unwrapped.containsKey('bookSourceUrl')) {
      for (final key in ['data', 'bookSources', 'sources', 'result', 'list', 'records']) {
        if (unwrapped[key] is List) { unwrapped = unwrapped[key]; break; }
      }
    }
    int count = 0;
    final list = unwrapped is List ? unwrapped : [unwrapped];
    for (final item in list) {
      if (item is Map) {
        try {
          final m = Map<String, dynamic>.from(item);
          if ((m['bookSourceUrl'] ?? '').toString().isEmpty) continue;
          final source = BookSource.fromJson(m);
          await _db.insertSource(source);
          count++;
        } catch (_) {}
      }
    }
    return count;
  }

  void _showImportDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('网络导入书源'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: '输入书源URL（JSON格式）'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final url = controller.text.trim();
              Navigator.pop(context);
              if (url.isNotEmpty) _importFromUrl(url);
            },
            child: const Text('导入'),
          ),
        ],
      ),
    );
  }

  void _showSortDialog() {
    const sortNames = ['手动排序', '按权重', '按名称', '按URL', '按更新时间', '按响应时间', '按启用状态'];
    showDialog(context: context, builder: (context) => AlertDialog(
      title: const Text('排序方式'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        ...List.generate(sortNames.length, (index) => RadioListTile<int>(
          title: Text(sortNames[index]),
          value: index,
          groupValue: _sortBy,
          onChanged: (v) => setState(() { _sortBy = v ?? 0; Navigator.pop(context); }),
        )),
        const Divider(),
        SwitchListTile(title: const Text('降序排列'), value: !_sortAsc, onChanged: (v) => setState(() => _sortAsc = !v)),
      ]),
    ));
  }

  void _showGroupManageDialog() {
    showDialog(context: context, builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('分组管理'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('分组来源于书源；可在此重命名或解散（解散后书源回到未分组）。新建分组请在编辑书源或多选“添加分组”中设置。',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ),
            if (_groups.isEmpty)
              const Padding(padding: EdgeInsets.all(16), child: Text('暂无分组'))
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: _groups.map((g) => ListTile(
                    dense: true,
                    title: Text(g),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(icon: const Icon(Icons.drive_file_rename_outline, size: 18), tooltip: '重命名', onPressed: () => _renameGroup(g)),
                      IconButton(icon: const Icon(Icons.delete, size: 18), tooltip: '解散分组', onPressed: () async {
                        for (final s in _sources.where((s) => s.bookSourceGroup == g)) {
                          s.bookSourceGroup = null;
                          await _db.updateSource(s);
                        }
                        await _loadSources();
                        if (mounted) { setDialogState(() {}); }
                      }),
                    ]),
                  )).toList(),
                ),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
        ],
      ),
    ));
  }

  Future<void> _renameGroup(String oldName) async {
    final controller = TextEditingController(text: oldName);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名分组'),
        content: TextField(controller: controller, decoration: const InputDecoration(labelText: '新分组名', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('确定')),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == oldName) return;
    for (final s in _sources.where((s) => s.bookSourceGroup == oldName)) {
      s.bookSourceGroup = newName;
      await _db.updateSource(s);
    }
    await _loadSources();
    if (mounted) {
      // 刷新分组管理弹窗内容
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已重命名为「$newName」')));
    }
  }

  Future<void> _batchAction(String action) async {
    final selected = _sources.where((s) => _selectedIds.contains(s.bookSourceUrl)).toList();
    switch (action) {
      case 'enable_explore':
        for (final s in selected) { s.enabledExplore = true; await _db.updateSource(s); }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已启用${selected.length}个书源的发现')));
        break;
      case 'disable_explore':
        for (final s in selected) { s.enabledExplore = false; await _db.updateSource(s); }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已禁用${selected.length}个书源的发现')));
        break;
      case 'to_top':
        for (var i = 0; i < selected.length; i++) { selected[i].customOrder = -(i + 1); await _db.updateSource(selected[i]); }
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已置顶')));
        break;
      case 'to_bottom':
        for (var i = 0; i < selected.length; i++) { selected[i].customOrder = i + 1; await _db.updateSource(selected[i]); }
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已置底')));
        break;
      case 'add_group':
        _showBatchGroupDialog(selected, true);
        return;
      case 'remove_group':
        for (final s in selected) { s.bookSourceGroup = null; await _db.updateSource(s); }
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已移除分组')));
        break;
      case 'check':
        Navigator.pop(context);
        final sel = _sources.where((s) => _selectedIds.contains(s.bookSourceUrl)).toList();
        _validateSources(sel.isNotEmpty ? sel : null);
        return;
      case 'invert':
        final all = _filteredSources.map((s) => s.bookSourceUrl).toSet();
        setState(() { final inverted = all.difference(_selectedIds); _selectedIds.clear(); _selectedIds.addAll(inverted); });
        return;
    }
    await _loadSources();
    setState(() { _selectMode = false; _selectedIds.clear(); });
  }

  void _showBatchGroupDialog(List selected, bool add) {
    final controller = TextEditingController();
    showDialog(context: context, builder: (context) => AlertDialog(
      title: Text(add ? '添加到分组' : '移除分组'),
      content: TextField(controller: controller, decoration: const InputDecoration(labelText: '分组名称')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: () async {
          for (final s in selected) { s.bookSourceGroup = controller.text; await _db.updateSource(s); }
          if (mounted) { Navigator.pop(context); await _loadSources(); setState(() { _selectMode = false; _selectedIds.clear(); }); }
        }, child: const Text('确定')),
      ],
    ));
  }

  Future<void> _batchEnable(bool enabled) async {
    for (final id in _selectedIds) {
      final source = _sources.where((s) => s.bookSourceUrl == id).firstOrNull;
      if (source != null) { source.enabled = enabled; await _db.updateSource(source); }
    }
    await _loadSources();
    setState(() { _selectMode = false; _selectedIds.clear(); });
  }

  Future<void> _batchDelete() async {
    for (final id in _selectedIds) { await _db.deleteSource(id); }
    await _loadSources();
    setState(() { _selectMode = false; _selectedIds.clear(); });
  }

  Future<void> _batchExport() async {
    final selected = _sources.where((s) => _selectedIds.contains(s.bookSourceUrl)).toList();
    if (selected.isEmpty) return;
    final jsonStr = const JsonEncoder.withIndent('  ').convert(selected.map((s) => s.toJson()).toList());
    await Clipboard.setData(ClipboardData(text: jsonStr));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已导出${selected.length}个书源到剪贴板')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _selectMode ? Text('已选 ${_selectedIds.length} 个') : Text('书源管理 (${_sources.length})'),
        leading: _selectMode ? IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() { _selectMode = false; _selectedIds.clear(); })) : null,
        actions: _selectMode ? [
          IconButton(icon: const Icon(Icons.select_all), tooltip: '全选', onPressed: () => setState(() => _selectedIds.addAll(_filteredSources.map((s) => s.bookSourceUrl)))),
          IconButton(icon: const Icon(Icons.check_circle_outline), tooltip: '启用', onPressed: () => _batchEnable(true)),
          IconButton(icon: const Icon(Icons.remove_circle_outline), tooltip: '禁用', onPressed: () => _batchEnable(false)),
          IconButton(icon: const Icon(Icons.ios_share), tooltip: '导出', onPressed: _batchExport),
          PopupMenuButton<String>(
            onSelected: (v) => _batchAction(v),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'enable_explore', child: Text('启用发现')),
              PopupMenuItem(value: 'disable_explore', child: Text('禁用发现')),
              PopupMenuItem(value: 'to_top', child: Text('选中置顶')),
              PopupMenuItem(value: 'to_bottom', child: Text('选中置底')),
              PopupMenuItem(value: 'add_group', child: Text('添加分组')),
              PopupMenuItem(value: 'remove_group', child: Text('移除分组')),
              PopupMenuItem(value: 'check', child: Text('校验选中')),
              PopupMenuItem(value: 'invert', child: Text('反选')),
            ],
          ),
          IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), tooltip: '删除', onPressed: () => showDialog(context: context, builder: (context) => AlertDialog(title: const Text('删除选中'), content: Text('确定删除${_selectedIds.length}个书源吗？'), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')), FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () { Navigator.pop(context); _batchDelete(); }, child: const Text('删除'))]))),
        ] : [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              showSearch(
                context: context,
                delegate: SourceSearchDelegate(_sources, (source) {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => SourceEditScreen(source: source))).then((_) => _loadSources());
                }),
              );
            },
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'enable_all':
                  for (final s in _sources) { s.enabled = true; _db.updateSource(s); }
                  setState(() {});
                  break;
                case 'disable_all':
                  for (final s in _sources) { s.enabled = false; _db.updateSource(s); }
                  setState(() {});
                  break;
                case 'select_mode':
                  setState(() { _selectMode = true; _selectedIds.clear(); });
                  break;
                case 'sort':
                  _showSortDialog();
                  break;
                case 'group_manage':
                  _showGroupManageDialog();
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'select_mode', child: Text('多选模式')),
              PopupMenuItem(value: 'sort', child: Text('排序')),
              PopupMenuItem(value: 'group_manage', child: Text('分组管理')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'enable_all', child: Text('全部启用')),
              PopupMenuItem(value: 'disable_all', child: Text('全部禁用')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_groups.isNotEmpty)
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  FilterChip(
                    label: const Text('全部'),
                    selected: _selectedGroup == null,
                    onSelected: (_) => setState(() => _selectedGroup = null),
                  ),
                  const SizedBox(width: 8),
                  ..._groups.map((g) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(g),
                      selected: _selectedGroup == g,
                      onSelected: (_) => setState(() => _selectedGroup = g),
                    ),
                  )),
                ],
              ),
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredSources.isEmpty
                    ? _buildEmptyState()
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _filteredSources.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final source = _filteredSources[index];
                          final selected = _selectedIds.contains(source.bookSourceUrl);
                    return Card(
                      color: selected ? Theme.of(context).colorScheme.primaryContainer : null,
                      child: ListTile(
                        leading: _selectMode
                            ? Checkbox(value: selected, onChanged: (_) => setState(() => selected ? _selectedIds.remove(source.bookSourceUrl) : _selectedIds.add(source.bookSourceUrl)))
                            : CircleAvatar(
                          backgroundColor: source.enabled == true
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(context).colorScheme.surfaceContainerHighest,
                          child: Text(
                            source.bookSourceName.isNotEmpty ? source.bookSourceName[0] : '?',
                            style: TextStyle(color: source.enabled == true ? Theme.of(context).colorScheme.primary : Colors.grey),
                          ),
                        ),
                        title: Text(source.bookSourceName, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(source.bookSourceUrl, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                            if (source.bookSourceGroup != null && source.bookSourceGroup!.isNotEmpty)
                              Text('分组: ${source.bookSourceGroup}', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.primary)),
                          ],
                        ),
                        trailing: _selectMode ? null : Switch(
                          value: source.enabled == true,
                          onChanged: (value) => _toggleSource(source, value),
                        ),
                        onTap: () {
                          if (_selectMode) {
                            setState(() => selected ? _selectedIds.remove(source.bookSourceUrl) : _selectedIds.add(source.bookSourceUrl));
                          } else {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => SourceEditScreen(source: source))).then((_) => _loadSources());
                          }
                        },
                        onLongPress: () => _selectMode ? setState(() => selected ? _selectedIds.remove(source.bookSourceUrl) : _selectedIds.add(source.bookSourceUrl)) : _showSourceOptions(source),
                      ),
                    );
                  },
                ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddMenu,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.source_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text('暂无书源', style: TextStyle(fontSize: 18, color: Colors.grey[600])),
          const SizedBox(height: 8),
          Text('点击右下角添加或导入书源', style: TextStyle(color: Colors.grey[500])),
        ],
      ),
    );
  }

  Future<void> _validateSources([List<BookSource>? targets]) async {
    final sources = targets ?? await _db.getAllSources();
    if (sources.isEmpty) return;
    final engine = BookSourceEngine();
    int valid = 0, invalid = 0, done = 0;
    showDialog(context: context, barrierDismissible: false, builder: (c) => StatefulBuilder(builder: (c, setS) {
      void upd() { if (c.mounted) setS(() {}); }
      upd();
      return AlertDialog(title: const Text('书源校验'), content: Column(mainAxisSize: MainAxisSize.min, children: [
        LinearProgressIndicator(value: sources.isEmpty ? 0 : done / sources.length),
        const SizedBox(height: 12),
        Text('进度 $done/${sources.length}  有效$valid 无效$invalid'),
      ]), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('后台运行'))]);
    }));
    const concurrency = 6;
    int cursor = 0;
    Future<void> worker() async {
      while (cursor < sources.length) {
        final s = sources[cursor++];
        try {
          // 真实校验：有搜索地址则执行搜索，能解析出书籍列表才算有效；空结果视为失效
          bool ok = false;
          if ((s.searchUrl ?? '').isNotEmpty) {
            final keyword = (s.checkKeyWord ?? '').isNotEmpty ? s.checkKeyWord! : '的';
            final r = await engine.search(s, keyword, page: 1).timeout(const Duration(seconds: 15), onTimeout: () => []);
            ok = r.isNotEmpty; // 搜索必须返回有效书籍列表
          } else if ((s.exploreUrl ?? '').isNotEmpty) {
            // 无搜索但有发现：尝试拉取第一个发现分类
            final kinds = engine.getExploreKinds(s);
            if (kinds.isNotEmpty) {
              final r = await engine.exploreByUrl(s, kinds.first['url'] ?? '', page: 1).timeout(const Duration(seconds: 15), onTimeout: () => []);
              ok = r.isNotEmpty;
            }
          } else {
            final client = HttpClient();
            try {
              final req = await client.getUrl(Uri.parse(s.bookSourceUrl)).timeout(const Duration(seconds: 8));
              final resp = await req.close().timeout(const Duration(seconds: 8));
              ok = resp.statusCode < 400;
            } finally { client.close(); }
          }
          ok ? valid++ : invalid++;
        } catch (_) { invalid++; }
        done++;
        if (mounted) setState(() {});
      }
    }
    await Future.wait(List.generate(concurrency.clamp(1, sources.length), (_) => worker()));
    if (mounted) { Navigator.of(context).pop(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('校验完成: 有效$valid个, 无效$invalid个'))); }
  }

  void _showSourceOptions(BookSource source) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('编辑'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => SourceEditScreen(source: source))).then((_) => _loadSources());
              },
            ),
            ListTile(
              leading: Icon(source.enabled == true ? Icons.toggle_off : Icons.toggle_on),
              title: Text(source.enabled == true ? '禁用' : '启用'),
              onTap: () {
                Navigator.pop(context);
                _toggleSource(source, !(source.enabled == true));
              },
            ),
            ListTile(
              leading: const Icon(Icons.content_copy),
              title: const Text('复制书源JSON'),
              onTap: () async {
                Navigator.pop(context);
                final jsonStr = const JsonEncoder.withIndent('  ').convert(source.toJson());
                await Clipboard.setData(ClipboardData(text: jsonStr));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('书源JSON已复制到剪贴板')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.bug_report),
              title: const Text('调试书源'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => SourceDebugScreen(source: source)));
              },
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('分享书源'),
              onTap: () async {
                Navigator.pop(context);
                final jsonStr = const JsonEncoder.withIndent('  ').convert(source.toJson());
                await Share.share(jsonStr, subject: source.bookSourceName);
              },
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_2),
              title: const Text('分享二维码'),
              subtitle: const Text('生成书源二维码，供其它设备扫码导入'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => QrShareScreen(source: source)));
              },
            ),
            ListTile(
              leading: const Icon(Icons.push_pin_outlined),
              title: Text(source.customOrder > 0 ? '取消置顶' : '置顶'),
              onTap: () {
                Navigator.pop(context);
                source.customOrder = source.customOrder > 0 ? 0 : -1;
                _db.updateSource(source);
                _loadSources();
              },
            ),
            ListTile(
              leading: const Icon(Icons.vertical_align_bottom),
              title: const Text('置底'),
              onTap: () {
                Navigator.pop(context);
                source.customOrder = 1;
                _db.updateSource(source);
                _loadSources();
              },
            ),
            ListTile(
              leading: const Icon(Icons.login),
              title: const Text('登录'),
              onTap: () {
                Navigator.pop(context);
                _showSourceLogin(source);
              },
            ),
            ListTile(
              leading: Icon(source.enabledExplore ? Icons.explore_off : Icons.explore),
              title: Text(source.enabledExplore ? '禁用发现' : '启用发现'),
              onTap: () {
                Navigator.pop(context);
                source.enabledExplore = !source.enabledExplore;
                _db.updateSource(source);
                _loadSources();
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('书源详情'),
              onTap: () {
                Navigator.pop(context);
                showDialog(context: context, builder: (context) => AlertDialog(
                  title: Text(source.bookSourceName),
                  content: SingleChildScrollView(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('URL: ${source.bookSourceUrl}'),
                      const SizedBox(height: 8),
                      Text('分组: ${source.bookSourceGroup ?? "默认"}'),
                      const SizedBox(height: 8),
                      Text('类型: ${source.bookSourceType == 0 ? "文本" : source.bookSourceType == 1 ? "音频" : source.bookSourceType == 2 ? "图片" : source.bookSourceType == 3 ? "文件" : "视频"}'),
                      const SizedBox(height: 8),
                      Text('搜索URL: ${source.searchUrl ?? "无"}'),
                      const SizedBox(height: 8),
                      Text('发现URL: ${source.exploreUrl ?? "无"}'),
                      const SizedBox(height: 8),
                      Text('响应时间: ${source.respondTime}ms'),
                      const SizedBox(height: 8),
                      Text('权重: ${source.weight}'),
                      const SizedBox(height: 8),
                      Text('备注: ${source.bookSourceComment ?? "无"}'),
                    ],
                  )),
                  actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
                ));
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _deleteSource(source);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class SourceSearchDelegate extends SearchDelegate<BookSource> {
  final List<BookSource> sources;
  final Function(BookSource) onSelect;

  SourceSearchDelegate(this.sources, this.onSelect);

  @override
  List<Widget> buildActions(BuildContext context) => [
    IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
  ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () => Navigator.pop(context),
  );

  @override
  Widget buildResults(BuildContext context) => buildSuggestions(context);

  @override
  Widget buildSuggestions(BuildContext context) {
    final results = query.isEmpty
        ? sources
        : sources.where((s) => s.bookSourceName.contains(query) || s.bookSourceUrl.contains(query)).toList();
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final source = results[index];
        return ListTile(
          title: Text(source.bookSourceName),
          subtitle: Text(source.bookSourceUrl, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => onSelect(source),
        );
      },
    );
  }
}

/* ===== 由 qr_scanner_screen.dart 合并 ===== */

/// 通用二维码/条码扫描页，扫描成功后 pop 返回识别到的文本
class QrScannerScreen extends StatefulWidget {
  final String title;
  const QrScannerScreen({super.key, this.title = '扫描二维码'});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture cap) {
    if (_handled) return;
    final code = cap.barcodes.isNotEmpty ? cap.barcodes.first.rawValue : null;
    if (code != null && code.isNotEmpty) {
      _handled = true;
      Navigator.pop(context, code);
    }
  }

  /// 从相册选择图片识别二维码
  Future<void> _pickFromGallery() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      final path = result?.files.single.path;
      if (path == null || !mounted) return;
      final ok = await _controller.analyzeImage(path);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未能从图片中识别出二维码')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('读取图片失败')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(icon: const Icon(Icons.photo_library_outlined), tooltip: '从相册选择',
            onPressed: _pickFromGallery),
          IconButton(icon: const Icon(Icons.flash_on), tooltip: '闪光灯',
            onPressed: () => _controller.toggleTorch()),
          IconButton(icon: const Icon(Icons.cameraswitch), tooltip: '切换镜头',
            onPressed: () => _controller.switchCamera()),
        ],
      ),
      body: Stack(alignment: Alignment.center, children: [
        MobileScanner(controller: _controller, onDetect: _onDetect),
        // 取景框
        Container(width: 240, height: 240,
          decoration: BoxDecoration(border: Border.all(color: Colors.white.withOpacity(0.8), width: 3), borderRadius: BorderRadius.circular(12))),
        Positioned(bottom: 48, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
          child: const Text('将二维码放入框内自动识别', style: TextStyle(color: Colors.white, fontSize: 13)),
        )),
      ]),
    );
  }
}

