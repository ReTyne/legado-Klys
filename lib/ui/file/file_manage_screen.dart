import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:legado_md3/help/storage/file_helper.dart';

/// 文件管理页面 - 对齐原版FileManage
/// 浏览应用数据目录下的书籍、缓存、备份、导出文件
class FileManageScreen extends StatefulWidget {
  const FileManageScreen({super.key});

  @override
  State<FileManageScreen> createState() => _FileManageScreenState();
}

class _FileManageScreenState extends State<FileManageScreen> {
  late Directory _root;
  late Directory _current;
  List<FileSystemEntity> _entities = [];
  String _searchQuery = '';
  bool _loading = true;
  final List<Directory> _history = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      _root = await FileHelper.getAppDataDir();
    } catch (_) {
      _root = await getApplicationDocumentsDirectory();
    }
    _current = _root;
    await _listDir();
  }

  Future<void> _listDir() async {
    setState(() => _loading = true);
    try {
      final list = await _current.list().toList();
      list.sort((a, b) {
        final aDir = a is Directory;
        final bDir = b is Directory;
        if (aDir != bDir) return aDir ? -1 : 1;
        return a.path.toLowerCase().compareTo(b.path.toLowerCase());
      });
      setState(() { _entities = list; _loading = false; });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  void _open(FileSystemEntity e) {
    if (e is Directory) {
      _history.add(_current);
      _current = e;
      _listDir();
    } else {
      _showFileInfo(e as File);
    }
  }

  void _back() {
    if (_history.isNotEmpty) {
      _current = _history.removeLast();
      _listDir();
    } else if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  void _showFileInfo(File f) {
    final size = f.existsSync() ? f.lengthSync() : 0;
    showModalBottomSheet(context: context, builder: (context) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: const Icon(Icons.insert_drive_file), title: Text(f.uri.pathSegments.last, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text('大小: ${_fmtSize(size)}')),
      ListTile(leading: const Icon(Icons.delete_outline), title: const Text('删除文件'),
        onTap: () async { f.deleteSync(); Navigator.pop(context); _listDir(); }),
    ])));
  }

  Future<void> _createFolder() async {
    final ctl = TextEditingController();
    showDialog(context: context, builder: (c) => AlertDialog(
      title: const Text('新建文件夹'),
      content: TextField(controller: ctl, decoration: const InputDecoration(hintText: '文件夹名称')),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
        FilledButton(onPressed: () async {
          if (ctl.text.isEmpty) return;
          final dir = Directory('${_current.path}/${ctl.text}');
          if (!dir.existsSync()) dir.createSync(recursive: true);
          if (mounted) { Navigator.pop(c); _listDir(); }
        }, child: const Text('创建'))],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _searchQuery.isEmpty ? _entities : _entities.where((e) => e.path.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    final relPath = _current.path.replaceFirst(_root.path, '.');
    return PopScope(
      canPop: _history.isEmpty,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) _back(); },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _back),
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('文件管理', style: TextStyle(fontSize: 16)),
            Text(relPath, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.normal), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
          actions: [
            IconButton(icon: const Icon(Icons.create_new_folder), onPressed: _createFolder),
          ],
        ),
        body: Column(children: [
          Padding(padding: const EdgeInsets.all(8), child: TextField(
            decoration: InputDecoration(hintText: '搜索文件', prefixIcon: const Icon(Icons.search), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(24))),
            onChanged: (v) => setState(() => _searchQuery = v),
          )),
          Expanded(child: _loading
            ? const Center(child: CircularProgressIndicator())
            : filtered.isEmpty
              ? const Center(child: Text('空目录', style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final e = filtered[i];
                    final isDir = e is Directory;
                    final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
                    return ListTile(
                      leading: Icon(isDir ? Icons.folder : Icons.insert_drive_file_outlined, color: isDir ? Colors.amber[700] : null),
                      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: isDir ? null : FutureBuilder<FileStat>(
                        future: e.stat(),
                        builder: (_, snap) => Text(snap.hasData ? _fmtSize(snap.data!.size) : '', style: const TextStyle(fontSize: 11)),
                      ),
                      trailing: isDir ? const Icon(Icons.chevron_right) : IconButton(
                        icon: const Icon(Icons.more_vert, size: 20),
                        onPressed: () => _showFileInfo(e as File),
                      ),
                      onTap: () => _open(e),
                    );
                  },
                )),
        ]),
      ),
    );
  }
}
