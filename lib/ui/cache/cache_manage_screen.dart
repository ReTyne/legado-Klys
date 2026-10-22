import 'dart:io';

import 'package:flutter/material.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/help/storage/backup_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  /// 正文内容缓存上限（MB，cache_contentMaxMB）
  int _cacheMaxMB = 500;
  /// 当前正文缓存估算字节数（与设置页一致：字符数 × 2）
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
    _cacheMaxMB = prefs.getInt('cache_contentMaxMB') ?? 500;
    _books = await _db.getAllBooks();
    _chapterCounts = {};
    var bytes = 0;
    for (final book in _books) {
      final chapters = await _db.getChapters(book.name, book.author);
      final cached = chapters.where((c) => c.content != null && c.content!.isNotEmpty).toList();
      _chapterCounts['${book.name}_${book.author}'] = cached.length;
      for (final c in cached) {
        bytes += c.content!.length;
      }
    }
    _cacheSizeBytes = bytes * 2;
    await _loadBackupInfo();
    if (mounted) setState(() => _isLoading = false);
  }

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

  /// 按 `cache_contentMaxMB` 上限执行 LRU 清理：
  /// book_chapters 表无 content 的访问时间字段（accessTime 不存在，且数据库文件不可改），
  /// 因此以 book_progress.lastReadTime 作为「最近使用」信号做书籍级 LRU：
  /// 从最久未读（含从未读过）的书开始清缓存，保留最近阅读的一本书。
  Future<void> _enforceCacheLimit() async {
    final limitBytes = _cacheMaxMB * 1024 * 1024;
    if (!_overLimit) {
      _tip('当前缓存未超过上限（${_formatBytes(_cacheSizeBytes)} / ${_cacheMaxMB}MB）');
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
    // 保护最近阅读的一本书（通常是正在读的书），其余按 LRU 顺序清理
    final clearable = sorted.length > 1 ? sorted.sublist(0, sorted.length - 1) : <Book>[];
    var remaining = _cacheSizeBytes;
    var clearedBooks = 0;
    for (final book in clearable) {
      if (remaining <= limitBytes) break;
      final chapters = await _db.getChapters(book.name, book.author);
      for (final c in chapters) {
        if (c.content != null && c.content!.isNotEmpty) remaining -= c.content!.length * 2;
      }
      await _db.clearBookChapterContent(book.name, book.author);
      clearedBooks++;
    }
    await _loadCache();
    if (!mounted) return;
    if (_overLimit) {
      _tip('已清理 $clearedBooks 本书缓存，仍超出上限（保留最近阅读书籍），当前 ${_formatBytes(_cacheSizeBytes)} / ${_cacheMaxMB}MB');
    } else {
      _tip('已按 LRU 清理 $clearedBooks 本书缓存，当前 ${_formatBytes(_cacheSizeBytes)} / ${_cacheMaxMB}MB');
    }
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除缓存'),
        content: Text('确定要清除《${book.name}》的所有章节缓存吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('清除')),
        ],
      ),
    );
    if (confirmed == true) {
      await _db.clearBookChapterContent(book.name, book.author);
      _loadCache();
    }
  }

  Future<void> _clearAllCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除全部缓存'),
        content: const Text('确定要清除所有书籍的章节缓存吗？此操作不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('全部清除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      // 清空全部章节正文缓存（与具体书籍无关，执行一次即可）
      await _db.clearChapterContent();
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
          if (_books.isNotEmpty)
            TextButton(
              onPressed: _clearAllCache,
              child: const Text('全部清除'),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                if (_overLimit)
                  Container(
                    margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '正文缓存已超出上限：${_formatBytes(_cacheSizeBytes)} / ${_cacheMaxMB}MB',
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
                  padding: const EdgeInsets.all(16),
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('共 ${_books.length} 本书'),
                      Text('已缓存 $_totalCachedChapters 章 · ${_formatBytes(_cacheSizeBytes)} / ${_cacheMaxMB}MB'),
                    ],
                  ),
                ),
                if (_books.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Column(
                      children: [
                        Icon(Icons.cleaning_services, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('没有缓存的书籍', style: TextStyle(color: Colors.grey)),
                      ],
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

  Widget _buildBookTile(Book book) {
    final cached = _chapterCounts['${book.name}_${book.author}'] ?? 0;
    return ListTile(
      leading: book.coverUrl != null && book.coverUrl!.isNotEmpty
          ? Image.network(book.coverUrl!, width: 40, height: 60, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _buildDefaultCover())
          : _buildDefaultCover(),
      title: Text(book.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${book.author} · 已缓存 $cached 章'),
      trailing: cached > 0
          ? TextButton(
              onPressed: () => _clearBookCache(book),
              child: const Text('清除'),
            )
          : const Text('无缓存', style: TextStyle(color: Colors.grey, fontSize: 12)),
    );
  }

  /// 本地备份卡片：展示 backup_path 解析结果、备份文件与「清理旧备份（保留 N 份）」
  Widget _buildBackupSection(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('本地备份', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Text(
            _backupDirPath.isEmpty ? '目录读取中…' : '目录: $_backupDirPath',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          if (_backupDirWarning != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '$_backupDirWarning，已回退默认目录',
                style: TextStyle(fontSize: 11, color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: 4),
          Text(
            '${_backupFiles.length} 个备份 · ${_formatBytes(_backupTotalBytes)} · 保留最近 $_keepCount 份',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 8),
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

  Widget _buildDefaultCover() {
    return Container(
      width: 40,
      height: 60,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Icon(Icons.book, size: 20, color: Colors.grey),
    );
  }
}
