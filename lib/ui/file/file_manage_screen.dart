import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:legado_md3/help/device/native_bridge.dart';
import 'package:legado_md3/utils/alphanum_comparator.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';

/// 文件管理页面 - 对齐原版FileManage
/// 浏览应用数据目录下的书籍、缓存、备份、导出文件；
/// 文件支持打开（外部应用）/ 分享 / 重命名 / 删除，全部真实生效。
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

  /// 扩展名 → MIME（供 NativeBridge.openFile / shareFile 使用）
  static const Map<String, String> _mimeMap = <String, String>{
    'txt': 'text/plain',
    'epub': 'application/epub+zip',
    'pdf': 'application/pdf',
    'json': 'application/json',
    'html': 'text/html',
    'htm': 'text/html',
    'xml': 'application/xml',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'mp4': 'video/mp4',
    'mkv': 'video/x-matroska',
    'webm': 'video/webm',
    'mp3': 'audio/mpeg',
    'm4a': 'audio/mp4',
    'zip': 'application/zip',
    'cbz': 'application/zip',
    'rar': 'application/x-rar-compressed',
  };

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
        // 自然排序：第 2 章 < 第 10 章
        return AlphanumComparator.naturalCompare(a.path, b.path);
      });
      setState(() {
        _entities = list;
        _loading = false;
      });
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
      _showFileMenu(e as File);
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

  String _nameOf(FileSystemEntity e) =>
      e.uri.pathSegments.where((s) => s.isNotEmpty).last;

  String _mimeOf(String path) {
    final dot = path.lastIndexOf('.');
    final ext = dot >= 0 ? path.substring(dot + 1).toLowerCase() : '';
    return _mimeMap[ext] ?? 'application/octet-stream';
  }

  void _tip(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 长按 / 点击 / 更多按钮：文件动作菜单（打开 / 分享 / 重命名 / 删除）。
  void _showFileMenu(File f) {
    final name = _nameOf(f);
    final size = f.existsSync() ? f.lengthSync() : 0;
    showAppMenuSheet(
      context,
      title: '$name · ${_fmtSize(size)}',
      items: [
        AppMenuSheetItem(
          title: '打开文件',
          icon: Icons.open_in_new_outlined,
          subtitle: '按 ${_mimeOf(f.path)} 交给外部应用',
          onTap: () => _openFile(f),
        ),
        AppMenuSheetItem(
          title: '分享文件',
          icon: Icons.share_outlined,
          onTap: () => _shareFile(f),
        ),
        AppMenuSheetItem(
          title: '重命名',
          icon: Icons.drive_file_rename_outline,
          onTap: () => _renameFile(f),
        ),
        AppMenuSheetItem(
          title: '删除文件',
          icon: Icons.delete_outline,
          onTap: () => _deleteFile(f),
        ),
      ],
    );
  }

  Future<void> _openFile(File f) async {
    final mime = _mimeOf(f.path);
    final ok = await NativeBridge.instance.openFile(f.path, mime: mime);
    _tip(ok
        ? '已请求外部应用打开（$mime）'
        : '当前平台不支持外部打开，文件仍在：${f.path}');
  }

  Future<void> _shareFile(File f) async {
    final mime = _mimeOf(f.path);
    final ok = await NativeBridge.instance.shareFile(
      f.path,
      mime: mime,
      title: _nameOf(f),
    );
    _tip(ok ? '已打开系统分享面板（$mime）' : '当前平台不支持系统分享，文件仍在：${f.path}');
  }

  Future<void> _renameFile(File f) async {
    final ctl = TextEditingController(text: _nameOf(f));
    final v = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: ctl,
          decoration: const InputDecoration(hintText: '新文件名（含扩展名）'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(c, ctl.text),
              child: const Text('确定')),
        ],
      ),
    );
    if (v == null || v.trim().isEmpty) return;
    final target =
        '${f.parent.path}${Platform.pathSeparator}${v.trim()}';
    if (File(target).existsSync()) {
      _tip('同名文件已存在');
      return;
    }
    try {
      await f.rename(target);
      await _listDir();
      _tip('已重命名为 ${v.trim()}');
    } catch (e) {
      _tip('重命名失败：$e');
    }
  }

  Future<void> _deleteFile(File f) async {
    final ok = await showAppConfirmDialog(
      context,
      title: '删除文件',
      content: '确定删除「${_nameOf(f)}」吗？此操作不可恢复。',
      confirmText: '删除',
      danger: true,
    );
    if (!ok) return;
    try {
      await f.delete();
      await _listDir();
      _tip('已删除');
    } catch (e) {
      _tip('删除失败：$e');
    }
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
    final cs = Theme.of(context).colorScheme;
    final filtered = _searchQuery.isEmpty ? _entities : _entities.where((e) => e.path.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    final relPath = _current.path.replaceFirst(_root.path, '.');
    return PopScope(
      canPop: _history.isEmpty,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) _back(); },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(tooltip: '返回', icon: const Icon(Icons.arrow_back), onPressed: _back),
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('文件管理', style: TextStyle(fontSize: 16)),
            Text(relPath, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.normal), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
          actions: [
            IconButton(tooltip: '新建文件夹', icon: const Icon(Icons.create_new_folder_outlined), onPressed: _createFolder),
          ],
        ),
        body: Column(children: [
          Padding(padding: const EdgeInsets.all(8), child: TextField(
            decoration: InputDecoration(hintText: '搜索文件', prefixIcon: const Icon(Icons.search_outlined), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
            onChanged: (v) => setState(() => _searchQuery = v),
          )),
          Expanded(child: _loading
            ? const Center(child: CircularProgressIndicator())
            : filtered.isEmpty
              ? const AppEmptyState(
                  icon: Icons.folder_open_outlined,
                  title: '空目录',
                  message: '当前目录下没有文件',
                )
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final e = filtered[i];
                    final isDir = e is Directory;
                    final name = _nameOf(e);
                    return ListTile(
                      leading: Icon(
                          isDir ? Icons.folder_outlined : Icons.insert_drive_file_outlined,
                          color: isDir ? cs.primary : cs.onSurfaceVariant),
                      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: isDir ? null : FutureBuilder<FileStat>(
                        future: e.stat(),
                        builder: (_, snap) => Text(snap.hasData ? _fmtSize(snap.data!.size) : '', style: const TextStyle(fontSize: 11)),
                      ),
                      trailing: isDir
                          ? const Icon(Icons.chevron_right)
                          : IconButton(
                              tooltip: '文件操作',
                              icon: const Icon(Icons.more_vert_outlined, size: 20),
                              onPressed: () => _showFileMenu(e as File),
                            ),
                      onTap: () => _open(e),
                      onLongPress: isDir ? null : () => _showFileMenu(e as File),
                    );
                  },
                )),
        ]),
      ),
    );
  }
}

/* ===== 由 file_helper.dart 合并 ===== */

class FileHelper {
  static Future<String> readFile(String path) => File(path).readAsString();

  /// 应用数据根目录
  static Future<Directory> getAppDataDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/legado');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// 书籍缓存目录
  static Future<Directory> getBookCacheDir() async {
    final root = await getAppDataDir();
    final dir = Directory('${root.path}/book_cache');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// 备份目录
  static Future<Directory> getBackupDir() async {
    final root = await getAppDataDir();
    final dir = Directory('${root.path}/backup');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// 导出目录
  static Future<Directory> getExportDir() async {
    final root = await getAppDataDir();
    final dir = Directory('${root.path}/export');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  static Future<int> dirSize(Directory dir) async {
    int total = 0;
    if (!dir.existsSync()) return 0;
    await for (final e in dir.list(recursive: true)) {
      if (e is File) total += e.lengthSync();
    }
    return total;
  }
}
