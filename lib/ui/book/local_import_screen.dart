import 'dart:io';

import 'package:flutter/material.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/help/storage/import_book_service.dart';
import 'package:legado_md3/help/storage/local_import_browse.dart';
import 'package:legado_md3/ui/book/reader_router.dart';
import 'package:legado_md3/ui/book/import/remote_book_screen.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 浏览式本地书导入页：逐层浏览目录、递归扫描、批量导入、按文件名规则导入。
class LocalImportScreen extends StatefulWidget {
  const LocalImportScreen({super.key});

  @override
  State<LocalImportScreen> createState() => _LocalImportScreenState();
}

class _LocalImportScreenState extends State<LocalImportScreen> {
  final ImportBookService _importService = ImportBookService();
  final DatabaseService _db = DatabaseService();

  late Directory _currentDir;
  List<FileSystemEntity> _entries = <FileSystemEntity>[];
  List<ScannedBook> _scanResults = <ScannedBook>[];

  LocalSortMode _sortMode = LocalSortMode.name;
  bool _showScanResults = false;
  bool _showImported = true;
  final Set<String> _selectedPaths = <String>{};
  List<Book> _allBooks = <Book>[];

  bool _isImporting = false;
  bool _isScanning = false;
  double _progress = 0;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _currentDir = Directory.systemTemp;
    _bootstrap();
  }

  /// 解析初始目录：优先外部存储目录，其次公共存储根，最后退回应用私有目录。
  /// 任一步骤遇到权限异常都不让页面失效，至少保证私有目录可浏览。
  Future<void> _bootstrap() async {
    final dir = await _resolveInitialDirectory();
    if (!mounted) return;
    setState(() => _currentDir = dir);
    await _loadBooks();
    await _refresh();
  }

  Future<Directory> _resolveInitialDirectory() async {
    try {
      final ext = await getExternalStorageDirectory();
      if (ext != null && await _isReadable(ext)) return ext;
    } catch (_) {}
    for (final candidate in <String>['/storage/emulated/0', '/sdcard']) {
      final d = Directory(candidate);
      try {
        if (await _isReadable(d)) return d;
      } catch (_) {}
    }
    try {
      final docs = await getApplicationDocumentsDirectory();
      if (await _isReadable(docs)) return docs;
    } catch (_) {}
    return Directory.systemTemp;
  }

  Future<bool> _isReadable(Directory dir) async {
    if (!await dir.exists()) return false;
    await dir.list().first;
    return true;
  }

  /// 从应用私有目录重新进入，供权限不足时的一键降级。
  Future<void> _openPrivateDir() async {
    Directory dir;
    try {
      dir = await getApplicationDocumentsDirectory();
    } catch (_) {
      dir = Directory.systemTemp;
    }
    if (!mounted) return;
    setState(() {
      _currentDir = dir;
      _showScanResults = false;
      _selectedPaths.clear();
      _notice = null;
    });
    await _loadBooks();
    await _refresh();
  }

  Future<void> _loadBooks() async {
    try {
      _allBooks = await _db.getAllBooks();
    } catch (_) {
      _allBooks = <Book>[];
    }
  }

  /// 读取当前目录并排序。隐藏已入库文件由开关控制；权限异常给出友好提示。
  Future<void> _refresh() async {
    String? notice;
    List<FileSystemEntity> entries = <FileSystemEntity>[];
    try {
      final listed = await _currentDir.list(followLinks: false).toList();
      for (final e in listed) {
        if (!_showImported && e is File && isBookFile(e.path) && isImported(e.path, _allBooks)) {
          continue;
        }
        entries.add(e);
      }
      entries = sortDirectoryEntries(entries, _sortMode);
    } on FileSystemException catch (e) {
      notice = '无存储权限或目录不可读：${e.message}';
    } catch (e) {
      notice = '读取目录失败：$e';
    }
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _notice = notice;
    });
  }

  void _enterDirectory(Directory dir) {
    setState(() {
      _currentDir = dir;
      _showScanResults = false;
      _selectedPaths.clear();
      _notice = null;
    });
    _refresh();
  }

  void _goParent() {
    final parent = p.dirname(_currentDir.path);
    if (parent == _currentDir.path) return;
    _enterDirectory(Directory(parent));
  }

  List<MapEntry<String, Directory>> _breadcrumbs() {
    final parts = _currentDir.path
        .split(RegExp(r'[\\/]'))
        .where((s) => s.isNotEmpty)
        .toList();
    final crumbs = <MapEntry<String, Directory>>[];
    final acc = StringBuffer(_currentDir.path.startsWith('/') ? '/' : '');
    for (final part in parts) {
      if (acc.isEmpty || acc.toString() == '/') {
        acc.write(part);
      } else {
        acc.write('/$part');
      }
      crumbs.add(MapEntry(part, Directory(acc.toString())));
    }
    if (crumbs.isEmpty) {
      crumbs.add(MapEntry(_currentDir.path, _currentDir));
    }
    return crumbs;
  }

  void _setSort(LocalSortMode mode) {
    setState(() => _sortMode = mode);
    if (_showScanResults) {
      setState(() => _scanResults = _sortedScanned(_scanResults));
    } else {
      _refresh();
    }
  }

  List<ScannedBook> _sortedScanned(List<ScannedBook> src) {
    final copy = <ScannedBook>[...src];
    copy.sort((a, b) {
      switch (_sortMode) {
        case LocalSortMode.name:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case LocalSortMode.size:
          final c = b.size.compareTo(a.size);
          return c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case LocalSortMode.time:
          final c = b.modifiedMs.compareTo(a.modifiedMs);
          return c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
    });
    return copy;
  }

  Future<void> _scanCurrent() async {
    setState(() => _isScanning = true);
    try {
      final results = await scanDirectory(_currentDir);
      if (!mounted) return;
      setState(() {
        _scanResults = _sortedScanned(results);
        _showScanResults = true;
        _selectedPaths.clear();
        _isScanning = false;
      });
      if (results.isEmpty) {
        _snack('当前目录下未发现可导入的书籍文件');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isScanning = false);
      _snack('扫描失败：$e');
    }
  }

  void _toggleSelected(String path) {
    setState(() {
      if (_selectedPaths.contains(path)) {
        _selectedPaths.remove(path);
      } else {
        _selectedPaths.add(path);
      }
    });
  }

  void _selectAllVisible() {
    final paths = _showScanResults
        ? _scanResults.map((s) => s.path)
        : _entries.whereType<File>().map((f) => f.path);
    setState(() {
      final list = paths.toList();
      final allSelected = list.isNotEmpty && list.every(_selectedPaths.contains);
      _selectedPaths.clear();
      if (!allSelected) _selectedPaths.addAll(list);
    });
  }

  /// 批量导入：逐本走统一导入服务并展示进度。
  Future<void> _importSelected() async {
    final paths = _selectedPaths.toList();
    if (paths.isEmpty) return;
    setState(() {
      _isImporting = true;
      _progress = 0;
    });
    var ok = 0;
    for (var i = 0; i < paths.length; i++) {
      try {
        await _importService.importPath(paths[i]);
        ok++;
      } catch (e) {
        debugPrint('导入失败: $e');
      }
      if (mounted) setState(() => _progress = (i + 1) / paths.length);
    }
    if (!mounted) return;
    setState(() {
      _isImporting = false;
      _selectedPaths.clear();
    });
    await _loadBooks();
    await _refresh();
    _snack('成功导入 $ok/${paths.length} 个文件${ok > 0 ? '，可到书架查看' : ''}');
  }

  /// 按文件名规则导入：解析出的书名/作者覆盖文件内容里解析出的元数据。
  Future<void> _importByFileName(String rule) async {
    final paths = _selectedPaths.toList();
    if (paths.isEmpty) {
      _snack('请先勾选要导入的文件');
      return;
    }
    setState(() {
      _isImporting = true;
      _progress = 0;
    });
    var ok = 0;
    for (var i = 0; i < paths.length; i++) {
      final info = parseBookNameFromFileName(p.basename(paths[i]), rule: rule);
      try {
        await _importWithMeta(paths[i], info.name, info.author);
        ok++;
      } catch (e) {
        debugPrint('按文件名导入失败: $e');
      }
      if (mounted) setState(() => _progress = (i + 1) / paths.length);
    }
    if (!mounted) return;
    setState(() {
      _isImporting = false;
      _selectedPaths.clear();
    });
    await _loadBooks();
    await _refresh();
    _snack('按文件名导入 $ok/${paths.length} 个文件${ok > 0 ? '，可到书架查看' : ''}');
  }

  /// 复用 importPath 完成内容解析与入库，再把书名/作者改为文件名解析结果。
  Future<void> _importWithMeta(String path, String name, String author) async {
    final result = await _importService.importPath(path);
    final book = result.book;
    if (book.name == name && book.author == author) return;

    final oldName = book.name;
    final oldAuthor = book.author;
    final chapters = await _db.getChapters(oldName, oldAuthor);
    book
      ..name = name
      ..author = author;
    await _db.deleteBook(oldName, oldAuthor);
    await _db.insertBook(book);
    if (chapters.isNotEmpty) await _db.saveChapters(name, author, chapters);
  }

  void _openBookAt(String path) {
    Book? matched;
    for (final b in _allBooks) {
      if (isImported(path, <Book>[b])) {
        matched = b;
        break;
      }
    }
    if (matched == null) {
      _snack('未找到对应的已入库书籍');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => readerForBook(matched!)),
    );
  }

  Future<void> _confirmDeleteSource(String path) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除源文件'),
        content: Text('确定删除「${p.basename(path)}」吗？\n仅删除磁盘文件，书架中的书籍会保留。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await File(path).delete();
      _selectedPaths.remove(path);
      _scanResults.removeWhere((s) => s.path == path);
      await _refresh();
      _snack('已删除源文件，书架书籍保留');
    } catch (e) {
      _snack('删除失败：$e');
    }
  }

  void _showFileMenu(String path) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除源文件'),
              subtitle: Text(p.basename(path), maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDeleteSource(path);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showFileNameRuleDialog() {
    final controller = TextEditingController(text: defaultFileNameRule);
    final previewPaths = _selectedPaths.toList();
    final previewName = previewPaths.isEmpty ? '示例：三体 - 刘慈欣.txt' : p.basename(previewPaths.first);
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setDialogState) {
          void updatePreview() {
            setDialogState(() {});
          }

          final livePreview =
              parseBookNameFromFileName(previewName.replaceFirst('示例：', ''), rule: controller.text);
          return AlertDialog(
            title: const Text('按文件名导入'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('用命名分组 name / author 的正则解析文件名：'),
                  const SizedBox(height: AppSpacing.s),
                  TextField(
                    controller: controller,
                    onChanged: (_) => updatePreview(),
                    maxLines: 3,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: r'^(?<name>.+?)\s*-\s*(?<author>.+)$',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.m),
                  Text('预览：$previewName', style: const TextStyle(fontSize: 12)),
                  Text('书名：${livePreview.name}　作者：${livePreview.author}',
                      style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: AppSpacing.xs),
                  const Text('内置兜底：作者《书名》', style: TextStyle(fontSize: 11)),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
              FilledButton(
                onPressed: () {
                  final rule = controller.text;
                  Navigator.pop(ctx);
                  _importByFileName(rule);
                },
                child: const Text('解析并导入'),
              ),
            ],
          );
        });
      },
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _sortButton() {
    final label = switch (_sortMode) {
      LocalSortMode.name => '名称',
      LocalSortMode.size => '大小',
      LocalSortMode.time => '时间',
    };
    return PopupMenuButton<LocalSortMode>(
      onSelected: _setSort,
      itemBuilder: (ctx) => const [
        PopupMenuItem(value: LocalSortMode.name, child: Text('按名称')),
        PopupMenuItem(value: LocalSortMode.size, child: Text('按大小')),
        PopupMenuItem(value: LocalSortMode.time, child: Text('按时间')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.sort, size: 18),
          const SizedBox(width: AppSpacing.xs),
          Text(label, style: const TextStyle(fontSize: 13)),
        ]),
      ),
    );
  }

  Widget _breadcrumbBar() {
    final cs = Theme.of(context).colorScheme;
    final crumbs = _breadcrumbs();
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_upward),
          tooltip: '返回上级',
          onPressed: _goParent,
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < crumbs.length; i++) ...[
                  if (i > 0) const Text(' / ', style: TextStyle(color: Colors.grey)),
                  InkWell(
                    onTap: () => _enterDirectory(crumbs[i].value),
                    child: Text(
                      crumbs[i].key,
                      style: TextStyle(
                        color: i == crumbs.length - 1
                            ? cs.primary
                            : cs.onSurfaceVariant,
                        fontSize: 13,
                        fontWeight: i == crumbs.length - 1 ? FontWeight.w600 : null,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _toolbar() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            TextButton.icon(
              onPressed: _isScanning ? null : _scanCurrent,
              icon: const Icon(Icons.travel_explore_outlined, size: 18),
              label: Text(_showScanResults ? '重新扫描' : '扫描当前目录'),
            ),
            TextButton.icon(
              onPressed: _showFileNameRuleDialog,
              icon: const Icon(Icons.text_fields, size: 18),
              label: const Text('按文件名导入'),
            ),
            TextButton.icon(
              onPressed: _selectAllVisible,
              icon: const Icon(Icons.select_all, size: 18),
              label: const Text('全选/取消'),
            ),
          ],
        ),
        AppSwitchTile(
          title: '显示已入库文件',
          subtitle: '关闭后列表中隐藏可打开阅读的书籍',
          icon: Icons.visibility_outlined,
          value: _showImported,
          onChanged: (v) {
            setState(() => _showImported = v);
            _refresh();
          },
        ),
        if (_selectedPaths.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: FilledButton.icon(
              onPressed: _isImporting ? null : _importSelected,
              icon: const Icon(Icons.file_download_outlined),
              label: Text('批量导入选中 (${_selectedPaths.length})'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(40)),
            ),
          ),
      ],
    );
  }

  Widget _buildDirectoryTile(FileSystemEntity entity) {
    if (entity is Directory) {
      return ListTile(
        leading: const Icon(Icons.folder),
        title: Text(entityName(entity), maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: const Text('目录'),
        onTap: () => _enterDirectory(entity),
      );
    }
    final file = entity as File;
    final path = file.path;
    final imported = isImported(path, _allBooks);
    int size = 0;
    try {
      size = file.statSync().size;
    } catch (_) {}
    if (imported) {
      return ListTile(
        leading: const Icon(Icons.menu_book, color: Colors.green),
        title: Text(entityName(file), maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('已入库 · ${(size / 1024).toStringAsFixed(1)} KB · 点击阅读'),
        onTap: () => _openBookAt(path),
        onLongPress: () => _showFileMenu(path),
      );
    }
    return GestureDetector(
      onLongPress: () => _showFileMenu(path),
      child: CheckboxListTile(
        value: _selectedPaths.contains(path),
        onChanged: (_) => _toggleSelected(path),
        secondary: const Icon(Icons.description),
        title: Text(entityName(file), maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('${(size / 1024).toStringAsFixed(1)} KB'),
      ),
    );
  }

  Widget _buildScannedTile(ScannedBook item) {
    final imported = isImported(item.path, _allBooks);
    if (imported) {
      return ListTile(
        leading: const Icon(Icons.menu_book, color: Colors.green),
        title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: const Text('已入库 · 点击阅读'),
        onTap: () => _openBookAt(item.path),
        onLongPress: () => _showFileMenu(item.path),
      );
    }
    return GestureDetector(
      onLongPress: () => _showFileMenu(item.path),
      child: CheckboxListTile(
        value: _selectedPaths.contains(item.path),
        onChanged: (_) => _toggleSelected(item.path),
        secondary: const Icon(Icons.description),
        title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('${(item.size / 1024).toStringAsFixed(1)} KB'),
      ),
    );
  }

  Widget _buildList() {
    if (_notice != null) {
      return AppEmptyState(
        icon: Icons.lock_outline,
        title: _notice!,
        message: '可切换到应用私有目录继续浏览和导入书籍',
        action: FilledButton(
          onPressed: _openPrivateDir,
          child: const Text('打开私有目录'),
        ),
      );
    }
    if (_showScanResults) {
      if (_scanResults.isEmpty) {
        return const AppEmptyState(
          icon: Icons.search_off,
          title: '未发现书籍文件',
          message: '当前目录子树没有可导入的 txt/epub/pdf/mobi 等文件',
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('扫描结果（${_scanResults.length}）',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                TextButton(
                  onPressed: () => setState(() => _showScanResults = false),
                  child: const Text('返回浏览'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _scanResults.length,
              itemBuilder: (ctx, i) => _buildScannedTile(_scanResults[i]),
            ),
          ),
        ],
      );
    }
    if (_entries.isEmpty) {
      return const AppEmptyState(
        icon: Icons.folder_off_outlined,
        title: '空目录',
        message: '此目录没有可显示的文件或子目录',
      );
    }
    return ListView.builder(
      itemCount: _entries.length,
      itemBuilder: (ctx, i) => _buildDirectoryTile(_entries[i]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('本地导入'),
        actions: [
          _sortButton(),
          IconButton(
            tooltip: '远程书籍',
            icon: const Icon(Icons.cloud_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RemoteBookScreen()),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_isImporting) LinearProgressIndicator(value: _progress),
            if (_isScanning) const LinearProgressIndicator(),
            _breadcrumbBar(),
            const Divider(height: 1),
            _toolbar(),
            const Divider(height: 1),
            Expanded(child: _buildList()),
          ],
        ),
      ),
    );
  }
}
