import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/db_models.dart';
import 'package:legado_md3/help/storage/backup_service.dart';
import 'package:legado_md3/help/storage/download_service.dart';
import 'package:legado_md3/ui/cache/export_config_screen.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 缓存管理：精确统计 caches 表 content 长度、章节正文真实字节与本地文件体积，
/// 并接入 [DownloadService] 写缓存 LRU 的两个阈值键
/// （imageRetainNum / cache_contentMaxMB），提供手动 LRU 清理。
class CacheManageScreen extends StatefulWidget {
  const CacheManageScreen({super.key});

  @override
  State<CacheManageScreen> createState() => _CacheManageScreenState();
}

class _CacheManageScreenState extends State<CacheManageScreen> {
  final _db = DatabaseService();
  List<Book> _books = [];
  Map<String, int> _chapterCounts = {};
  bool _isLoading = true;

  /// 正文内容缓存上限（MB，cache_contentMaxMB，与 DownloadService 共用）
  int _cacheMaxMB = 500;
  /// 缓存保留章节数上限（imageRetainNum，与 DownloadService 写缓存 LRU 共用）
  int _imageRetainNum = 0;

  /// caches 表 content 的真实 UTF-8 字节数
  int _cacheTableBytes = 0;
  /// book_chapters.content 的真实 UTF-8 字节数
  int _chapterBytes = 0;
  /// 本地缓存 / 导入 / 导出目录文件的真实体积
  int _fileBytes = 0;
  /// 总缓存占用 = 表 + 章节正文 + 文件（不再用字符数 ×2 估算）
  int _cacheSizeBytes = 0;

  // 本地备份信息（backup_path / 保留份数）
  List<File> _backupFiles = [];
  String _backupDirPath = '';
  String? _backupDirWarning;
  int _keepCount = BackupService.defaultKeepCount;

  bool get _overLimit => _cacheSizeBytes > _cacheMaxMB * 1024 * 1024;

  @override
  void initState() {
    super.initState();
    _loadCache();
  }

  Future<void> _loadCache() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    _cacheMaxMB =
        prefs.getInt(DownloadService.keyCacheContentMaxMB) ?? 500;
    _imageRetainNum = prefs.getInt(DownloadService.keyImageRetainNum) ?? 0;

    _books = await _db.getAllBooks();
    _chapterCounts = {};
    var chapterBytes = 0;
    for (final book in _books) {
      final chapters = await _db.getChapters(book.name, book.author);
      final cached = chapters
          .where((c) => c.content != null && c.content!.isNotEmpty)
          .toList();
      _chapterCounts['${book.name}_${book.author}'] = cached.length;
      for (final c in cached) {
        // 真实 UTF-8 字节，替代旧的 content.length × 2 粗估
        chapterBytes += utf8.encode(c.content!).length;
      }
    }

    var tableBytes = 0;
    for (final c in await _db.getCaches()) {
      tableBytes += c.content != null && c.content!.isNotEmpty
          ? utf8.encode(c.content!).length
          : c.size;
    }

    _chapterBytes = chapterBytes;
    _cacheTableBytes = tableBytes;
    _fileBytes = await _localFileBytes();
    _cacheSizeBytes = tableBytes + chapterBytes + _fileBytes;

    await _loadBackupInfo();
    if (mounted) setState(() => _isLoading = false);
  }

  /// 统计应用文档目录下 import / download / book_cache / export 里真实文件体积。
  Future<int> _localFileBytes() async {
    try {
      final base = await getApplicationDocumentsDirectory();
      var total = 0;
      for (final name in ['import', 'download', 'book_cache', 'export']) {
        final dir = Directory(p.join(base.path, name));
        if (!dir.existsSync()) continue;
        await for (final e in dir.list(recursive: true, followLinks: false)) {
          if (e is File) {
            try {
              total += await e.length();
            } catch (_) {}
          }
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  static int _cacheRowBytes(Cache c) => c.content != null && c.content!.isNotEmpty
      ? utf8.encode(c.content!).length
      : c.size;

  /// 读取备份目录（backup_path）与备份文件列表；路径不可用时记录提示
  Future<void> _loadBackupInfo() async {
    try {
      final resolved = await BackupService.resolveBackupDirectory();
      _backupDirPath = resolved.directory.path;
      _backupDirWarning = resolved.fallback ? resolved.error : null;
      _backupFiles = await BackupService().getBackupFiles();
      _keepCount = await BackupService().getKeepCount();
    } catch (e) {
      _backupDirWarning = '读取备份目录失败: $e';
      _backupFiles = [];
    }
  }

  /// 手动 LRU 清理 caches 表：按 saveTime 从最旧开始删，直到同时满足
  /// imageRetainNum（条目数）与 cache_contentMaxMB（体积）两个阈值。
  /// 与 [DownloadService] 写缓存时的自动 LRU 使用完全相同的键与判定口径。
  Future<int> _manualLruClean() async {
    final db = await _db.database;
    final caches = await _db.getCaches(); // saveTime DESC
    final limitBytes = _cacheMaxMB * 1024 * 1024;
    var bytes = 0;
    for (final c in caches) {
      bytes += _cacheRowBytes(c);
    }
    final oldest = List<Cache>.from(caches)
      ..sort((a, b) => a.saveTime.compareTo(b.saveTime));
    var count = caches.length;
    var deleted = 0;
    for (final c in oldest) {
      final overCount = _imageRetainNum > 0 && count > _imageRetainNum;
      final overSize = bytes > limitBytes;
      if (!overCount && !overSize) break;
      if (c.id != null) {
        await db.delete('caches', where: 'id = ?', whereArgs: [c.id]);
      }
      bytes -= _cacheRowBytes(c);
      count--;
      deleted++;
    }
    return deleted;
  }

  /// 阈值触发的 LRU：先清 caches 行，再按 book_progress.lastReadTime 做书籍级
  /// 章节正文 LRU（保留最近阅读的一本书），最后重算精确体积。
  Future<void> _enforceCacheLimit() async {
    if (!_overLimit) {
      _tip('当前缓存未超过上限（${_formatBytes(_cacheSizeBytes)} / ${_cacheMaxMB}MB）');
      return;
    }
    final deletedRows = await _manualLruClean();
    await _loadCache();
    if (!_overLimit) {
      _tip('已按 LRU 清理 $deletedRows 条缓存记录，当前 ${_formatBytes(_cacheSizeBytes)} / ${_cacheMaxMB}MB');
      return;
    }
    // 每本书最近一次阅读时间（无记录按 0 处理，最优先清理）
    final progressMap = <String, int>{};
    for (final pg in await _db.getAllBookProgress()) {
      progressMap['${pg.bookName}_${pg.author}'] = pg.lastReadTime;
    }
    final sorted = [..._books]..sort((a, b) {
        final ta = progressMap['${a.name}_${a.author}'] ?? 0;
        final tb = progressMap['${b.name}_${b.author}'] ?? 0;
        return ta.compareTo(tb);
      });
    final clearable =
        sorted.length > 1 ? sorted.sublist(0, sorted.length - 1) : <Book>[];
    var clearedBooks = 0;
    for (final book in clearable) {
      final chapters = await _db.getChapters(book.name, book.author);
      if (chapters.every((c) => c.content == null || c.content!.isEmpty)) {
        continue;
      }
      await _db.clearBookChapterContent(book.name, book.author);
      clearedBooks++;
      await _loadCache();
      if (!_overLimit) break;
    }
    await _loadCache();
    if (!mounted) return;
    if (_overLimit) {
      _tip('已清理 $deletedRows 条缓存、$clearedBooks 本书正文，仍超出上限（保留最近阅读书籍），当前 ${_formatBytes(_cacheSizeBytes)} / ${_cacheMaxMB}MB');
    } else {
      _tip('已按 LRU 清理 $deletedRows 条缓存、$clearedBooks 本书正文，当前 ${_formatBytes(_cacheSizeBytes)} / ${_cacheMaxMB}MB');
    }
  }

  Future<void> _setMaxMB(int v) async {
    setState(() => _cacheMaxMB = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(DownloadService.keyCacheContentMaxMB, v);
  }

  Future<void> _setRetainNum(int v) async {
    setState(() => _imageRetainNum = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(DownloadService.keyImageRetainNum, v);
  }

  Future<void> _cleanOldBackups() async {
    try {
      final deleted = await BackupService().cleanOldBackups();
      await _loadCache();
      if (!mounted) return;
      _tip(deleted > 0 ? '已清理 $deleted 个旧备份（保留最近 $_keepCount 份）' : '没有需要清理的备份（保留最近 $_keepCount 份）');
    } catch (e) {
      if (!mounted) return;
      _tip('清理备份失败: $e');
    }
  }

  Future<void> _clearBookCache(Book book) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: '清除缓存',
      content: '确定要清除《${book.name}》的所有章节缓存吗？',
      confirmText: '清除',
      danger: true,
    );
    if (confirmed) {
      await _db.clearBookChapterContent(book.name, book.author);
      _loadCache();
    }
  }

  Future<void> _clearAllCache() async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: '清除全部缓存',
      content: '确定要清除所有书籍的章节缓存吗？此操作不可恢复。',
      confirmText: '全部清除',
      danger: true,
    );
    if (confirmed) {
      await _db.clearChapterContent();
      await _db.clearCaches();
      _loadCache();
    }
  }

  void _tip(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  static String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${bytes}B';
  }

  int get _totalCachedChapters => _chapterCounts.values.fold(0, (a, b) => a + b);

  int get _backupTotalBytes => _backupFiles.fold(0, (a, f) {
        try {
          return a + f.lengthSync();
        } catch (_) {
          return a;
        }
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('缓存管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share_outlined),
            tooltip: '导出配置',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ExportConfigScreen())),
          ),
          if (_books.isNotEmpty)
            TextButton(
              onPressed: _clearAllCache,
              child: const Text('全部清除'),
            ),
        ],
      ),
      body: _isLoading
          ? const AppLoadingIndicator()
          : ListView(
              children: [
                if (_overLimit)
                  Container(
                    margin: const EdgeInsets.fromLTRB(AppSpacing.m, AppSpacing.m, AppSpacing.m, 0),
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l, vertical: AppSpacing.s),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: AppRadius.mAll,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '缓存已超出上限：${_formatBytes(_cacheSizeBytes)} / ${_cacheMaxMB}MB',
                            style: TextStyle(color: theme.colorScheme.onErrorContainer, fontSize: 13),
                          ),
                        ),
                        TextButton(
                          onPressed: _enforceCacheLimit,
                          child: const Text('按上限清理'),
                        ),
                      ],
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.l),
                  color: theme.colorScheme.primaryContainer,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('共 ${_books.length} 本书'),
                      Text('已缓存 $_totalCachedChapters 章 · ${_formatBytes(_cacheSizeBytes)} / ${_cacheMaxMB}MB'),
                    ],
                  ),
                ),
                // 精确体积明细（真实 UTF-8 字节与文件体积，不再 ×2 估算）
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.l, AppSpacing.s, AppSpacing.l, AppSpacing.s),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sizeRow('caches 表正文', _cacheTableBytes),
                      _sizeRow('章节正文缓存', _chapterBytes),
                      _sizeRow('本地文件', _fileBytes),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '体积按 content 的真实 UTF-8 字节与文件实际大小统计；'
                        '写缓存时 DownloadService 依下列阈值自动 LRU。',
                        style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                const AppSectionHeader('LRU 阈值（与写缓存共用）'),
                ListTile(
                  dense: true,
                  title: Text('缓存体积上限: ${_cacheMaxMB}MB'),
                  subtitle: Slider(
                    value: _cacheMaxMB.clamp(50, 2048).toDouble(),
                    min: 50, max: 2048, divisions: 39,
                    label: '${_cacheMaxMB}MB',
                    onChanged: (v) => setState(
                        () => _cacheMaxMB = (v / 50).round() * 50),
                    onChangeEnd: (v) => _setMaxMB((v / 50).round() * 50),
                  ),
                ),
                ListTile(
                  dense: true,
                  title: Text('缓存保留章节数: ${_imageRetainNum == 0 ? "不限" : _imageRetainNum}'),
                  subtitle: Slider(
                    value: _imageRetainNum.clamp(0, 500).toDouble(),
                    min: 0, max: 500, divisions: 25,
                    label: '$_imageRetainNum',
                    onChanged: (v) =>
                        setState(() => _imageRetainNum = (v / 20).round() * 20),
                    onChangeEnd: (v) => _setRetainNum((v / 20).round() * 20),
                  ),
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.cleaning_services_outlined),
                  title: const Text('立即按 LRU 手动清理'),
                  subtitle: const Text('按 saveTime 从最旧开始删 caches 行，直至满足两个阈值',
                      style: TextStyle(fontSize: 11)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final deleted = await _manualLruClean();
                    await _loadCache();
                    _tip('已按 LRU 清理 $deleted 条缓存记录，当前 ${_formatBytes(_cacheSizeBytes)}');
                  },
                ),
                const Divider(height: 1),
                if (_books.isEmpty)
                  const SizedBox(
                    height: 200,
                    child: AppEmptyState(
                      icon: Icons.cleaning_services_outlined,
                      title: '没有缓存的书籍',
                      message: '缓存章节后可在此查看与清理',
                    ),
                  )
                else
                  for (final book in _books)
                    _buildBookTile(book),
                const Divider(height: 1),
                _buildBackupSection(theme),
              ],
            ),
    );
  }

  Widget _sizeRow(String label, int bytes) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 12)),
            Text(_formatBytes(bytes), style: const TextStyle(fontSize: 12)),
          ],
        ),
      );

  Widget _buildBookTile(Book book) {
    final cached = _chapterCounts['${book.name}_${book.author}'] ?? 0;
    return ListTile(
      leading: BookCover(
        name: book.name,
        coverUrl: book.coverUrl,
        localPath: book.coverUrl != null && book.coverUrl!.startsWith('/')
            ? book.coverUrl
            : null,
        width: 40,
        height: 60,
        radius: 6,
      ),
      title: Text(book.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${book.author} · 已缓存 $cached 章'),
      trailing: cached > 0
          ? TextButton(
              onPressed: () => _clearBookCache(book),
              child: const Text('清除'),
            )
          : Text('无缓存', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
    );
  }

  /// 本地备份卡片：展示 backup_path 解析结果、备份文件与「清理旧备份（保留 N 份）」
  Widget _buildBackupSection(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('本地备份', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.s),
          Text(
            _backupDirPath.isEmpty ? '目录读取中…' : '目录: $_backupDirPath',
            style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
          ),
          if (_backupDirWarning != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                '$_backupDirWarning，已回退默认目录',
                style: TextStyle(fontSize: 11, color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${_backupFiles.length} 个备份 · ${_formatBytes(_backupTotalBytes)} · 保留最近 $_keepCount 份',
            style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.s),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: _cleanOldBackups,
              icon: const Icon(Icons.delete_sweep_outlined, size: 18),
              label: const Text('清理旧备份'),
            ),
          ),
        ],
      ),
    );
  }
}
