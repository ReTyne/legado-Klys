import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_chapter.dart';
import 'package:legado_md3/data/model/replace_rule.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';
import 'package:legado_md3/help/config/app_config.dart';
import 'package:legado_md3/help/storage/export_book_service.dart';
import 'package:legado_md3/help/storage/webdav_service.dart';

/// 缓存 / 导出配置（对齐 legado-E ui/book/cache/CacheActivity + res/menu/book_cache.xml）。
///
/// 把 AppPrefs 里此前「定义/持久化但零消费方」的导出开关接到真实导出行为：
/// - exportCharset / exportUseReplace / exportNoChapterName → ExportOptions；
/// - exportToWebDav → 导出后上传 WebDAV；parallelExportBook → 多本并行/串行导出。
/// 无法真实接线的两项按约定从 UI 下架并注释（见 build 内说明），避免假完成。
class ExportConfigScreen extends StatefulWidget {
  const ExportConfigScreen({super.key});

  @override
  State<ExportConfigScreen> createState() => _ExportConfigScreenState();
}

class _ExportConfigScreenState extends State<ExportConfigScreen> {
  final DatabaseService _db = DatabaseService();
  List<Book> _books = [];
  final Map<String, int> _cachedCount = {};
  bool _loading = true;
  bool _busy = false;

  // 对齐 E book_cache.xml 的 checkable 项（读取 AppPrefs 持久化值）
  late String _charset; // menu_export_charset
  late bool _useReplace; // menu_enable_replace
  late bool _noChapterName; // menu_export_no_chapter_name
  late bool _toWebDav; // menu_export_web_dav
  late bool _parallel; // menu_parallel_export
  int _exportType = 0; // menu_export_type：0=txt 1=epub（对齐 E exportTypes）
  bool _customExport = false; // menu_enable_custom_export
  String _fileNameTpl = '{name}'; // menu_export_file_name（ExportBookService 已消费）
  String _exportDir = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // 主动把持久化值载入内存，保证 getter 读到的是用户上次设置（不改所有权外的 app_config.dart）
    await AppPrefs.load();
    final p = await SharedPreferences.getInstance();
    final dir = await getApplicationDocumentsDirectory();
    final books = await _db.getAllBooks();
    final cached = <String, int>{};
    for (final b in books) {
      final chapters = await _db.getChapters(b.name, b.author);
      cached['${b.name}_${b.author}'] =
          chapters.where((c) => (c.content ?? '').isNotEmpty).length;
    }
    if (!mounted) return;
    setState(() {
      _charset = AppPrefs.exportCharset;
      _useReplace = AppPrefs.exportUseReplace;
      _noChapterName = AppPrefs.exportNoChapterName;
      _toWebDav = AppPrefs.exportToWebDav;
      _parallel = AppPrefs.parallelExportBook;
      _exportType = p.getInt('exportType') ?? 0;
      _customExport = p.getBool('enableCustomExport') ?? false;
      _fileNameTpl = p.getString('bookExportFileName') ?? '{name}';
      _exportDir = '${dir.path}/export';
      _books = books;
      _cachedCount..clear()..addAll(cached);
      _loading = false;
    });
  }

  void _tip(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 写 AppPrefs 静态 setter（同步改内存 + 异步落盘）后刷新 UI
  void _apply(VoidCallback write) {
    write();
    setState(() {});
  }

  Future<void> _setFileNameTpl() async {
    final ctrl = TextEditingController(text: _fileNameTpl);
    final v = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('导出文件名'),
        content: TextField(
          controller: ctrl,
          maxLines: 2,
          decoration: const InputDecoration(
            hintText: '支持 {name} 书名 / {author} 作者 / {group} 分组',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('保存')),
        ],
      ),
    );
    if (v == null) return;
    final tpl = v.trim().isEmpty ? '{name}' : v.trim();
    final p = await SharedPreferences.getInstance();
    await p.setString('bookExportFileName', tpl);
    if (mounted) setState(() => _fileNameTpl = tpl);
  }

  /// 自定义导出章节范围（对齐 E menu_enable_custom_export 的「选择导出章节」）
  Future<(int, int)?> _askRange(int total) async {
    final s = TextEditingController(text: '1');
    final e = TextEditingController(text: '$total');
    return showDialog<(int, int)>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('选择导出章节'),
        content: Row(children: [
          Expanded(child: TextField(controller: s, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '起始章'))),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('至')),
          Expanded(child: TextField(controller: e, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '结束章'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(onPressed: () {
            final a = int.tryParse(s.text.trim()) ?? 1;
            final b = int.tryParse(e.text.trim()) ?? total;
            final start = a.clamp(1, total);
            final end = b.clamp(start, total);
            Navigator.pop(c, (start - 1, end - 1));
          }, child: const Text('导出')),
        ],
      ),
    );
  }

  /// 导出单本：读取 AppPrefs 配置构造 ExportOptions，按 exportType 选 txt/epub，
  /// 导出后按 exportToWebDav 上传（对齐 E CacheActivity.export / startExport）。
  Future<String?> _exportBook(Book book, {bool showRange = false}) async {
    final all = await _db.getChapters(book.name, book.author);
    if (all.isEmpty) return null;
    List<BookChapter> chapters = all;
    if (showRange) {
      final range = await _askRange(all.length);
      if (range == null) return null;
      chapters = all.sublist(range.$1, range.$2 + 1);
    }
    List<ReplaceRule> rules = const [];
    if (_useReplace) {
      try {
        rules = await _db.getReplaceRules();
      } catch (_) {}
    }
    final options = ExportOptions(
      charset: _charset,
      noChapterName: _noChapterName,
      useReplace: _useReplace,
      replaceRules: rules,
    );
    final path = _exportType == 1
        ? await ExportBookService.exportToEpub(book, chapters, options: options)
        : await ExportBookService.exportToTxt(book, chapters, options: options);
    await _uploadToWebDav(path);
    return path;
  }

  /// 导出到 WebDAV（对齐 E AppConfig.exportToWebDav）：复用详情上传同一 WebDavService
  Future<void> _uploadToWebDav(String path) async {
    if (!_toWebDav) return;
    final p = await SharedPreferences.getInstance();
    final url = p.getString('webdav_url');
    if (url == null || url.trim().isEmpty) {
      _tip('未配置 WebDAV 服务器，已跳过上传');
      return;
    }
    try {
      final dav = WebDavService()
        ..configure(baseUrl: url.trim(), username: p.getString('webdav_user'), password: p.getString('webdav_pass'));
      await dav.uploadBook(path, bookDir: p.getString('webdav_book_dir') ?? '书籍');
    } catch (e) {
      _tip('WebDAV 上传失败: $e');
    }
  }

  Future<void> _exportOne(Book book) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final path = await _exportBook(book, showRange: _customExport);
      if (!mounted) return;
      if (path == null) {
        _tip('《${book.name}》暂无章节可导出');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('已导出: $path'),
          action: SnackBarAction(label: '分享', onPressed: () => Share.shareXFiles([XFile(path)], subject: '书籍导出')),
        ));
      }
    } catch (e) {
      _tip('导出失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 导出全部（对齐 E menu_export_all）；parallelExportBook 决定并行/串行。
  Future<void> _exportAll() async {
    if (_busy || _books.isEmpty) return;
    setState(() => _busy = true);
    int ok = 0, fail = 0;
    Future<void> one(Book b) async {
      try {
        final path = await _exportBook(b);
        if (path != null) ok++;
      } catch (_) {
        fail++;
      }
    }
    Future<void> doExport() async {
      if (_parallel) {
        await Future.wait(_books.map(one));
      } else {
        for (final b in _books) {
          await one(b);
        }
      }
    }
    try {
      await runWithBusyDialog<void>(
        context,
        message: '正在导出...',
        task: doExport(),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _tip('导出完成：成功 $ok 本${fail > 0 ? '，失败 $fail 本' : ''}');
      }
    }
  }

  /// 日志（对齐 E menu_log / AppLogDialog）：展示导出配置诊断
  void _showLog() {
    showDialog(context: context, builder: (c) => AlertDialog(
      title: const Text('日志'),
      content: SingleChildScrollView(child: Text(
        '导出目录：$_exportDir\n导出类型：${_exportType == 1 ? 'EPUB' : 'TXT'}\n'
        '导出编码：$_charset\n替换净化：$_useReplace\n不含章节名：$_noChapterName\n'
        '导出到 WebDAV：$_toWebDav\n并行导出：$_parallel\n文件名模板：$_fileNameTpl\n'
        '书籍数：${_books.length}',
        style: const TextStyle(fontSize: 12, height: 1.5),
      )),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭'))],
    ));
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Text(t, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('缓存导出'),
        actions: [
          // 对齐 E book_cache.xml：menu_export_all / menu_log
          IconButton(icon: const Icon(Icons.receipt_long), tooltip: '日志', onPressed: _showLog),
          if (_books.isNotEmpty)
            TextButton(onPressed: _busy ? null : _exportAll, child: const Text('导出全部')),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(children: [
              _section('导出选项（对齐 E book_cache.xml）'),
              // menu_export_type：导出类型
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(children: [
                  const Text('导出类型'),
                  const SizedBox(width: 12),
                  ChoiceChip(label: const Text('TXT'), selected: _exportType == 0,
                    onSelected: (_) async {
                      final p = await SharedPreferences.getInstance();
                      await p.setInt('exportType', 0);
                      if (mounted) setState(() => _exportType = 0);
                    }),
                  const SizedBox(width: 8),
                  ChoiceChip(label: const Text('EPUB'), selected: _exportType == 1,
                    onSelected: (_) async {
                      final p = await SharedPreferences.getInstance();
                      await p.setInt('exportType', 1);
                      if (mounted) setState(() => _exportType = 1);
                    }),
                ]),
              ),
              // menu_export_charset：导出编码（AppPrefs.exportCharset）
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(children: [
                  const Text('导出编码'),
                  const SizedBox(width: 12),
                  ChoiceChip(label: const Text('UTF-8'), selected: _charset.toUpperCase() != 'GBK',
                    onSelected: (_) => _apply(() => AppPrefs.exportCharset = 'UTF-8')),
                  const SizedBox(width: 8),
                  ChoiceChip(label: const Text('GBK'), selected: _charset.toUpperCase() == 'GBK',
                    onSelected: (_) => _apply(() => AppPrefs.exportCharset = 'GBK')),
                ]),
              ),
              SwitchListTile(
                dense: true,
                title: const Text('替换净化'),
                subtitle: const Text('导出时应用已启用的替换规则（E: menu_enable_replace）', style: TextStyle(fontSize: 11)),
                value: _useReplace,
                onChanged: (v) => _apply(() => AppPrefs.exportUseReplace = v),
              ),
              SwitchListTile(
                dense: true,
                title: const Text('不含章节名'),
                subtitle: const Text('正文直接相连，不插入章节标题（E: menu_export_no_chapter_name）', style: TextStyle(fontSize: 11)),
                value: _noChapterName,
                onChanged: (v) => _apply(() => AppPrefs.exportNoChapterName = v),
              ),
              SwitchListTile(
                dense: true,
                title: const Text('导出到 WebDAV'),
                subtitle: const Text('导出完成后上传到远程书库（E: menu_export_web_dav）', style: TextStyle(fontSize: 11)),
                value: _toWebDav,
                onChanged: (v) => _apply(() => AppPrefs.exportToWebDav = v),
              ),
              SwitchListTile(
                dense: true,
                title: const Text('并行导出'),
                subtitle: const Text('多本书同时导出（E: menu_parallel_export）', style: TextStyle(fontSize: 11)),
                value: _parallel,
                onChanged: (v) => _apply(() => AppPrefs.parallelExportBook = v),
              ),
              SwitchListTile(
                dense: true,
                title: const Text('自定义导出章节'),
                subtitle: const Text('单本导出时选择章节范围（E: menu_enable_custom_export）', style: TextStyle(fontSize: 11)),
                value: _customExport,
                onChanged: (v) async {
                  final p = await SharedPreferences.getInstance();
                  await p.setBool('enableCustomExport', v);
                  if (mounted) setState(() => _customExport = v);
                },
              ),
              // menu_export_file_name：文件名模板（ExportBookService._safeName 消费）
              ListTile(
                dense: true,
                leading: const Icon(Icons.drive_file_rename_outline),
                title: const Text('导出文件名'),
                subtitle: Text(_fileNameTpl, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                trailing: const Icon(Icons.chevron_right),
                onTap: _setFileNameTpl,
              ),
              // 对齐 E menu_export_folder：Klys 导出目录固定为应用文档/export，
              // 未接入系统目录选择（SAF），只读展示实际路径，不放无效开关（避免假完成）。
              ListTile(
                dense: true,
                leading: const Icon(Icons.folder_outlined),
                title: const Text('导出文件夹'),
                subtitle: Text(_exportDir, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
              ),
              // 对齐 E menu_export_pics_file：Klys 导出引擎仅输出纯文本 TXT/EPUB，
              // 不生成独立图片文件引用，无法真实接线，按约定从 UI 下架（AppPrefs.exportPictureFile 不暴露开关）。
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('注：「图片导出为文件」(E: export_pics_file) 因导出引擎不含图片落盘能力，本域从 UI 下架，未做假开关。',
                    style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
              const Divider(height: 1),
              _section('书籍（${_books.length}）'),
              if (_books.isEmpty)
                const SizedBox(
                  height: 180,
                  child: AppEmptyState(
                    icon: Icons.menu_book_outlined,
                    title: '书架为空，暂无可导出书籍',
                  ),
                )
              else
                for (final book in _books)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.menu_book_outlined),
                    title: Text(book.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${book.author} · 已缓存 ${_cachedCount['${book.name}_${book.author}'] ?? 0} 章'),
                    trailing: IconButton(
                      icon: const Icon(Icons.ios_share_outlined),
                      tooltip: '导出',
                      onPressed: _busy ? null : () => _exportOne(book),
                    ),
                  ),
              const SizedBox(height: 24),
            ]),
    );
  }
}
