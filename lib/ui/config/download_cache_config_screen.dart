import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/data/local/app_database.dart';

/// 下载缓存配置 - 对齐原版DownloadCacheConfigScreen
class DownloadCacheConfigScreen extends StatefulWidget {
  const DownloadCacheConfigScreen({super.key});

  @override
  State<DownloadCacheConfigScreen> createState() => _DownloadCacheConfigScreenState();
}

class _DownloadCacheConfigScreenState extends State<DownloadCacheConfigScreen> {
  final _db = DatabaseService();
  int _threads = 16;
  int _bookThreads = 3;
  int _preDownload = 5;
  int _bitmapCache = 20;
  int _imageRetain = 200;
  String _userAgent = '';
  bool _coverCache = true;
  bool _mangaCache = true;

  static const _defaultUA = 'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36';

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _threads = p.getInt('dc_threads') ?? 16;
      _bookThreads = p.getInt('dc_bookThreads') ?? 3;
      _preDownload = p.getInt('dc_preDownload') ?? 5;
      _bitmapCache = p.getInt('dc_bitmapCache') ?? 20;
      _imageRetain = p.getInt('dc_imageRetain') ?? 200;
      _userAgent = p.getString('dc_userAgent') ?? _defaultUA;
      _coverCache = p.getBool('dc_coverCache') ?? true;
      _mangaCache = p.getBool('dc_mangaCache') ?? true;
    });
  }

  Future<void> _set(String k, dynamic v) async {
    final p = await SharedPreferences.getInstance();
    if (v is int) await p.setInt(k, v);
    if (v is bool) await p.setBool(k, v);
    if (v is String) await p.setString(k, v);
  }

  Widget _section(String t) => Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
    child: Text(t, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('下载缓存配置')),
      body: ListView(children: [
        _section('HTTP缓存'),
        SwitchListTile(dense: true, title: const Text('封面缓存'), value: _coverCache, onChanged: (v) { setState(() => _coverCache = v); _set('dc_coverCache', v); }),
        SwitchListTile(dense: true, title: const Text('漫画缓存'), value: _mangaCache, onChanged: (v) { setState(() => _mangaCache = v); _set('dc_mangaCache', v); }),
        _section('下载设置'),
        ListTile(dense: true, title: Text('下载线程数: $_threads'),
          subtitle: Slider(value: _threads.toDouble(), min: 1, max: 32, divisions: 31, label: '$_threads',
            onChanged: (v) => setState(() => _threads = v.toInt()), onChangeEnd: (v) => _set('dc_threads', v.toInt()))),
        ListTile(dense: true, title: Text('缓存书籍线程数: $_bookThreads'),
          subtitle: Slider(value: _bookThreads.toDouble(), min: 1, max: 10, divisions: 9, label: '$_bookThreads',
            onChanged: (v) => setState(() => _bookThreads = v.toInt()), onChangeEnd: (v) => _set('dc_bookThreads', v.toInt()))),
        ListTile(dense: true, title: Text('阅读预下载章节数: $_preDownload'),
          subtitle: Slider(value: _preDownload.toDouble(), min: 0, max: 20, divisions: 20, label: '$_preDownload',
            onChanged: (v) => setState(() => _preDownload = v.toInt()), onChangeEnd: (v) => _set('dc_preDownload', v.toInt()))),
        _section('图片缓存'),
        ListTile(dense: true, title: Text('位图缓存大小: $_bitmapCache MB'),
          subtitle: Slider(value: _bitmapCache.toDouble(), min: 5, max: 100, divisions: 19, label: '$_bitmapCache',
            onChanged: (v) => setState(() => _bitmapCache = v.toInt()), onChangeEnd: (v) => _set('dc_bitmapCache', v.toInt()))),
        ListTile(dense: true, title: Text('图片内存保留数量: $_imageRetain'),
          subtitle: Slider(value: _imageRetain.toDouble(), min: 50, max: 500, divisions: 9, label: '$_imageRetain',
            onChanged: (v) => setState(() => _imageRetain = v.toInt()), onChangeEnd: (v) => _set('dc_imageRetain', v.toInt()))),
        _section('网络'),
        ListTile(dense: true, title: const Text('User Agent'), subtitle: Text(_userAgent, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
          trailing: const Icon(Icons.edit),
          onTap: () {
            final ctl = TextEditingController(text: _userAgent);
            showDialog(context: context, builder: (c) => AlertDialog(
              title: const Text('User Agent'),
              content: TextField(controller: ctl, maxLines: 3),
              actions: [
                TextButton(onPressed: () { ctl.text = _defaultUA; }, child: const Text('重置默认')),
                FilledButton(onPressed: () { setState(() => _userAgent = ctl.text); _set('dc_userAgent', ctl.text); Navigator.pop(c); }, child: const Text('保存')),
              ],
            ));
          }),
        _section('其他'),
        ListTile(dense: true, leading: const Icon(Icons.cleaning_services), title: const Text('清理缓存'),
          subtitle: const Text('清空已缓存的章节正文与临时数据（不影响书架与目录）', style: TextStyle(fontSize: 11)),
          onTap: _clearCache),
        ListTile(dense: true, leading: const Icon(Icons.compress), title: const Text('收缩数据库'), subtitle: const Text('回收数据库空闲空间', style: TextStyle(fontSize: 11)),
          onTap: _vacuum),
        const SizedBox(height: 24),
      ]),
    );
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('缓存已清理')));
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
