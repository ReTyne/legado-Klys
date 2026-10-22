import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/di/book_provider.dart';

/// 下载缓存配置
///
/// 本页只保留「有真实消费方」的设置与「可执行动作」：
/// - 更新/下载线程数 `bk_updateThreads`：auto_update_service.dart:182 读取，限制刷新书架并发；
/// - 预下载后续章节 `ReadConfig.preDownloadCount`：reading_screen.dart:174 读取，
///   进入章节后按该数量后台缓存后续章节正文；
/// - 缓存大小统计、图片缓存清理、正文缓存清理、数据库收缩：均为可执行动作。
/// 原 dc_coverCache / dc_mangaCache / dc_bitmapCache / dc_imageRetain / dc_userAgent
/// 等无任何消费方的假开关/假滑杆已移除。
class DownloadCacheConfigScreen extends StatefulWidget {
  const DownloadCacheConfigScreen({super.key});

  @override
  State<DownloadCacheConfigScreen> createState() => _DownloadCacheConfigScreenState();
}

class _DownloadCacheConfigScreenState extends State<DownloadCacheConfigScreen> {
  final _db = DatabaseService();
  int _updateThreads = 32;
  bool _preDownloadEnabled = true;
  int _preDownloadCount = 5;
  String _cacheSize = '计算中…';

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    // 先同步取 ReadConfig（阅读页真实消费 preDownloadCount），再 await，避免跨异步使用 context
    final cfg = context.read<ReadProvider>().config;
    final p = await SharedPreferences.getInstance();
    final threads = p.getInt('bk_updateThreads') ?? 32;
    if (!mounted) return;
    setState(() {
      _updateThreads = threads < 1 ? 1 : (threads > 64 ? 64 : threads);
      _preDownloadEnabled = cfg.preDownloadCount > 0;
      _preDownloadCount = cfg.preDownloadCount > 0 ? cfg.preDownloadCount : 5;
    });
    _calcCacheSize();
  }

  /// 统计已缓存的章节正文估算大小（与设置页同口径）
  Future<void> _calcCacheSize() async {
    try {
      int bytes = 0;
      final books = await _db.getAllBooks();
      for (final b in books) {
        final chs = await _db.getChapters(b.name, b.author);
        for (final ch in chs) { bytes += (ch.content ?? '').length; }
      }
      bytes = bytes * 2;
      String size;
      if (bytes < 1024) { size = '$bytes B'; }
      else if (bytes < 1024 * 1024) { size = '${(bytes / 1024).toStringAsFixed(1)} KB'; }
      else { size = '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB'; }
      if (mounted) setState(() => _cacheSize = size);
    } catch (_) {}
  }

  void _setPreDownload(bool enabled) {
    setState(() => _preDownloadEnabled = enabled);
    context.read<ReadProvider>().updateConfig((c) => c.preDownloadCount = enabled ? _preDownloadCount : 0);
  }

  void _setPreDownloadCount(int count) {
    setState(() => _preDownloadCount = count);
    if (_preDownloadEnabled) {
      context.read<ReadProvider>().updateConfig((c) => c.preDownloadCount = count);
    }
  }

  Future<void> _setThreads(int count) async {
    setState(() => _updateThreads = count);
    await (await SharedPreferences.getInstance()).setInt('bk_updateThreads', count);
  }

  Widget _section(String t) => Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
    child: Text(t, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('下载缓存配置')),
      body: ListView(children: [
        _section('阅读预下载'),
        SwitchListTile(
          dense: true,
          title: const Text('预下载后续章节'),
          subtitle: const Text('进入章节后在后台缓存后续章节正文，翻页无需等待（阅读时生效）', style: TextStyle(fontSize: 11)),
          value: _preDownloadEnabled,
          onChanged: _setPreDownload,
        ),
        if (_preDownloadEnabled)
          ListTile(
            dense: true,
            title: Text('预下载章节数: $_preDownloadCount'),
            subtitle: Slider(
              value: _preDownloadCount.clamp(1, 20).toDouble(),
              min: 1, max: 20, divisions: 19,
              label: '$_preDownloadCount',
              onChanged: (v) => _setPreDownloadCount(v.toInt()),
            ),
          ),
        _section('下载并发'),
        ListTile(
          dense: true,
          title: Text('更新/下载线程数: $_updateThreads'),
          subtitle: const Text('刷新书架时同时更新的书籍数量（bk_updateThreads）', style: TextStyle(fontSize: 11)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Slider(
            value: _updateThreads.clamp(1, 64).toDouble(),
            min: 1, max: 64, divisions: 63,
            label: '$_updateThreads',
            onChanged: (v) => setState(() => _updateThreads = v.toInt()),
            onChangeEnd: (v) => _setThreads(v.toInt()),
          ),
        ),
        _section('缓存'),
        ListTile(
          dense: true,
          leading: const Icon(Icons.storage_outlined),
          title: Text('正文缓存: $_cacheSize'),
          subtitle: const Text('已缓存的章节正文估算大小', style: TextStyle(fontSize: 11)),
        ),
        ListTile(
          dense: true,
          leading: const Icon(Icons.image_outlined),
          title: const Text('清理封面/图片缓存'),
          subtitle: const Text('清空内存中的封面与插图位图，立即释放内存（不影响已下载文件）', style: TextStyle(fontSize: 11)),
          onTap: _clearImageCache,
        ),
        ListTile(
          dense: true,
          leading: const Icon(Icons.cleaning_services),
          title: const Text('清理缓存'),
          subtitle: const Text('清空已缓存的章节正文与临时数据（不影响书架与目录）', style: TextStyle(fontSize: 11)),
          onTap: _clearCache,
        ),
        ListTile(
          dense: true,
          leading: const Icon(Icons.compress),
          title: const Text('收缩数据库'),
          subtitle: const Text('回收数据库空闲空间', style: TextStyle(fontSize: 11)),
          onTap: _vacuum,
        ),
        const SizedBox(height: 24),
      ]),
    );
  }

  Future<void> _clearImageCache() async {
    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('封面/图片缓存已清理')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('清理失败: $e')));
    }
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('清理缓存'),
        content: const Text('将清空所有已缓存的章节正文与临时数据，确定继续吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('清理')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _db.clearChapterContent();
      await _db.clearCaches();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('缓存已清理')));
        _calcCacheSize();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('清理失败: $e')));
    }
  }

  Future<void> _vacuum() async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在收缩数据库...')));
    try {
      await _db.vacuum();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('数据库收缩完成')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('收缩失败: $e')));
    }
  }
}
