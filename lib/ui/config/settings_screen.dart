import 'dart:io';
import 'package:flutter/material.dart';
import 'package:legado_md3/help/web/web_service.dart';
import 'package:legado_md3/ui/config/theme_manage_screen.dart';
import 'package:legado_md3/ui/config/cover_config_screen.dart';
import 'package:legado_md3/ui/book/manga/manga_config_screen.dart';
import 'package:legado_md3/ui/config/other_config_screen.dart';
import 'package:legado_md3/ui/config/download_cache_config_screen.dart';
import 'package:legado_md3/ui/config/cover_album_screen.dart';
import 'package:legado_md3/ui/config/translation_screen.dart';
import 'package:legado_md3/ui/cache/download_manage_screen.dart';
import 'package:legado_md3/ui/config/replace_rule_screen.dart';
import 'package:legado_md3/ui/config/txt_toc_rule_screen.dart';
import 'package:legado_md3/ui/config/dict_rule_screen.dart';
import 'package:legado_md3/ui/config/highlight_tag_rule_screen.dart';
import 'package:legado_md3/ui/main/homepage/homepage_manage_screen.dart';
import 'package:legado_md3/ui/config/import_book_config_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/ui/config/cloud_tts_screen.dart';
import 'package:legado_md3/ui/cache/cache_manage_screen.dart';
import 'package:legado_md3/ui/backup/backup_screen.dart';
import 'package:provider/provider.dart';
import 'package:legado_md3/constant/app_theme.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/read_config.dart';
import 'package:legado_md3/di/book_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  SharedPreferences? _prefs;
  bool _autoUpdate = true;
  int _autoUpdateHours = 6;
  bool _wifiOnly = false;
  bool _volumeKeyPage = true;
  bool _keepScreenOn = true;
  bool _showMenuOnTap = true;
  bool _showNotification = true;
  bool _landscapeLock = false;
  bool _webServiceEnabled = false;
  final WebService _webService = WebService();
  String _lanIp = 'localhost';
  bool _autoBackup = false;
  bool _autoCleanCache = false;
  String _cacheSize = '0 MB';
  bool _autoNextPage = false;
  bool _translateEnabled = false;
  bool _simulateReading = false;
  bool _boldText = false;
  bool _showStatusBar = true;
  bool _showTitle = true;
  bool _showTime = true;
  bool _showBattery = true;
  bool _showPageNumber = true;
  int _preDownloadCount = 5;
  int _textAlign = 2;
  int _textIndent = 2;
  int _paragraphSpacing = 1;
  int _pageAnim = 0;

  static const List<String> _pageAnimNames = ['覆盖', '仿真', '滑动', '滚动', '无动画', '上下'];
  static const List<String> _alignNames = ['左对齐', '居中', '两端对齐'];

  @override
  void initState() {
    super.initState();
    _restoreWebService();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _prefs = await SharedPreferences.getInstance();
    final readProvider = Provider.of<ReadProvider>(context, listen: false);
    final cfg = readProvider.config;
    setState(() {
      _autoUpdate = _prefs?.getBool('auto_update') ?? true;
      _autoUpdateHours = _prefs?.getInt('auto_update_hours') ?? 6;
      _wifiOnly = _prefs?.getBool('wifi_only') ?? false;
      _volumeKeyPage = cfg.volumeKeyPage;
      _keepScreenOn = cfg.keepScreenOn;
      _showMenuOnTap = cfg.showMenuOnTap;
      _showNotification = _prefs?.getBool('show_notification') ?? true;
      _landscapeLock = _prefs?.getBool('landscape_lock') ?? false;
      _autoNextPage = cfg.autoNextPage;
      _translateEnabled = _prefs?.getBool('translate_enabled') ?? false;
      _simulateReading = cfg.simulatedReading;
      _boldText = cfg.boldText;
      _showStatusBar = cfg.statusBarVisibility;
      _showTitle = cfg.titleVisibility;
      _showTime = cfg.timeVisibility;
      _showBattery = cfg.batteryVisibility;
      _showPageNumber = cfg.pageNumberVisibility;
      _preDownloadCount = cfg.preDownloadCount;
      _textAlign = cfg.textAlign;
      _textIndent = cfg.textIndent;
      _paragraphSpacing = cfg.paragraphSpacing;
      _pageAnim = cfg.pageAnim;
    });
    _calcCacheSize();
  }

  /// 更新阅读配置并持久化（同步到 ReadProvider，阅读界面实时生效）
  void _updateReadConfig(void Function(ReadConfig) updater) {
    Provider.of<ReadProvider>(context, listen: false).updateConfig(updater);
  }

  Future<void> _calcCacheSize() async {
    try {
      final db = DatabaseService();
      int bytes = 0;
      final books = await db.getAllBooks();
      for (final b in books) {
        final chs = await db.getChapters(b.name, b.author);
        for (final ch in chs) { bytes += (ch.content ?? '').length; }
      }
      // 中文按 UTF-8 约 3 字节估算
      bytes = bytes * 2;
      String size;
      if (bytes < 1024) { size = '$bytes B'; }
      else if (bytes < 1024 * 1024) { size = '${(bytes / 1024).toStringAsFixed(1)} KB'; }
      else { size = '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB'; }
      if (mounted) setState(() => _cacheSize = size);
    } catch (_) {}
  }

  Future<void> _restoreWebService() async {
    try {
      final ifaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final ifc in ifaces) {
        for (final a in ifc.addresses) {
          if (!a.isLoopback) { _lanIp = a.address; break; }
        }
      }
    } catch (_) {}
    final p = await SharedPreferences.getInstance();
    if (p.getBool('web_service_enabled') ?? false) {
      _webServiceEnabled = true;
      _webService.start().catchError((_) {});
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggleWebService(bool v) async {
    setState(() { _webServiceEnabled = v; });
    await _saveSetting('web_service_enabled', v);
    try {
      if (v) {
        await _webService.start();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Web服务已启动 http://$_lanIp:1122')));
      } else {
        await _webService.stop();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Web服务操作失败: $e')));
    }
  }

  Future<void> _saveSetting(String key, dynamic value) async {
    if (_prefs == null) return;
    if (value is bool) await _prefs!.setBool(key, value);
    else if (value is int) await _prefs!.setInt(key, value);
    else if (value is double) await _prefs!.setDouble(key, value);
    else if (value is String) await _prefs!.setString(key, value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<AppTheme>(context);
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          // 主题设置
          ListTile(
            leading: const Icon(Icons.tune),
            title: const Text('其他设置'),
            subtitle: const Text('语言/更新/密码/阅读偏好'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OtherConfigScreen())),
          ),
          _buildSectionHeader('主题设置'),
          SwitchListTile(
            title: const Text('深色模式'),
            subtitle: Text(theme.themeMode == ThemeMode.dark ? '已开启' : theme.themeMode == ThemeMode.system ? '跟随系统' : '已关闭'),
            value: theme.themeMode == ThemeMode.dark,
            onChanged: (v) => theme.setThemeMode(v ? ThemeMode.dark : ThemeMode.light),
          ),
          SwitchListTile(
            title: const Text('跟随系统'),
            value: theme.themeMode == ThemeMode.system,
            onChanged: (v) => theme.setThemeMode(v ? ThemeMode.system : ThemeMode.light),
          ),
          ListTile(
            title: const Text('主题色'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showColorPicker(theme),
          ),
          ListTile(
            leading: const Icon(Icons.book_outlined),
            title: const Text('封面配置'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CoverConfigScreen())),
          ),
          const Divider(),

          // 阅读设置
          _buildSectionHeader('阅读设置'),
          ListTile(
            title: const Text('翻页动画'),
            trailing: DropdownButton<int>(
              value: _pageAnim,
              items: List.generate(_pageAnimNames.length, (i) => DropdownMenuItem(value: i, child: Text(_pageAnimNames[i]))),
              onChanged: (v) => setState(() { _pageAnim = v ?? 0; _updateReadConfig((c) => c.pageAnim = _pageAnim); }),
            ),
          ),
          SwitchListTile(
            title: const Text('音量键翻页'),
            value: _volumeKeyPage,
            onChanged: (v) => setState(() { _volumeKeyPage = v; _updateReadConfig((c) => c.volumeKeyPage = v); }),
          ),
          SwitchListTile(
            title: const Text('保持屏幕常亮'),
            value: _keepScreenOn,
            onChanged: (v) => setState(() { _keepScreenOn = v; _updateReadConfig((c) => c.keepScreenOn = v); }),
          ),
          SwitchListTile(
            title: const Text('点击中央显示菜单'),
            value: _showMenuOnTap,
            onChanged: (v) => setState(() { _showMenuOnTap = v; _updateReadConfig((c) => c.showMenuOnTap = v); }),
          ),
          SwitchListTile(
            title: const Text('自动翻页'),
            value: _autoNextPage,
            onChanged: (v) => setState(() { _autoNextPage = v; _updateReadConfig((c) => c.autoNextPage = v); }),
          ),
          SwitchListTile(
            title: const Text('粗体文字'),
            value: _boldText,
            onChanged: (v) => setState(() { _boldText = v; _updateReadConfig((c) => c.boldText = v); }),
          ),
          ListTile(
            title: const Text('对齐方式'),
            trailing: DropdownButton<int>(
              value: _textAlign,
              items: List.generate(_alignNames.length, (i) => DropdownMenuItem(value: i, child: Text(_alignNames[i]))),
              onChanged: (v) => setState(() { _textAlign = v ?? 2; _updateReadConfig((c) => c.textAlign = _textAlign); }),
            ),
          ),
          ListTile(
            title: const Text('首行缩进'),
            trailing: DropdownButton<int>(
              value: _textIndent,
              items: List.generate(5, (i) => DropdownMenuItem(value: i, child: Text('${i * 2}字符'))),
              onChanged: (v) => setState(() { _textIndent = v ?? 2; _updateReadConfig((c) => c.textIndent = _textIndent); }),
            ),
          ),
          ListTile(
            title: const Text('段间距'),
            trailing: DropdownButton<int>(
              value: _paragraphSpacing,
              items: List.generate(5, (i) => DropdownMenuItem(value: i, child: Text('$i行'))),
              onChanged: (v) => setState(() { _paragraphSpacing = v ?? 1; _updateReadConfig((c) => c.paragraphSpacing = _paragraphSpacing); }),
            ),
          ),
          SwitchListTile(
            title: const Text('显示状态栏'),
            value: _showStatusBar,
            onChanged: (v) => setState(() { _showStatusBar = v; _updateReadConfig((c) => c.statusBarVisibility = v); }),
          ),
          SwitchListTile(
            title: const Text('显示标题'),
            value: _showTitle,
            onChanged: (v) => setState(() { _showTitle = v; _updateReadConfig((c) => c.titleVisibility = v); }),
          ),
          SwitchListTile(
            title: const Text('显示时间'),
            value: _showTime,
            onChanged: (v) => setState(() { _showTime = v; _updateReadConfig((c) => c.timeVisibility = v); }),
          ),
          SwitchListTile(
            title: const Text('显示电量'),
            value: _showBattery,
            onChanged: (v) => setState(() { _showBattery = v; _updateReadConfig((c) => c.batteryVisibility = v); }),
          ),
          SwitchListTile(
            title: const Text('显示页码'),
            value: _showPageNumber,
            onChanged: (v) => setState(() { _showPageNumber = v; _updateReadConfig((c) => c.pageNumberVisibility = v); }),
          ),
          const Divider(),

          // 网络和更新
          _buildSectionHeader('网络和更新'),
          SwitchListTile(
            title: const Text('自动更新'),
            subtitle: const Text('启动时自动检查书籍更新'),
            value: _autoUpdate,
            onChanged: (v) => setState(() { _autoUpdate = v; _saveSetting('auto_update', v); }),
          ),
          if (_autoUpdate) ListTile(
            dense: true,
            leading: const Icon(Icons.timer_outlined, size: 22),
            title: const Text('自动更新间隔'),
            trailing: DropdownButton<int>(
              value: _autoUpdateHours,
              items: const [DropdownMenuItem(value: 0, child: Text('30分钟')), DropdownMenuItem(value: 1, child: Text('1小时')), DropdownMenuItem(value: 3, child: Text('3小时')), DropdownMenuItem(value: 6, child: Text('6小时')), DropdownMenuItem(value: 12, child: Text('12小时')), DropdownMenuItem(value: 24, child: Text('每天'))],
              onChanged: (v) => setState(() { _autoUpdateHours = v ?? 6; _saveSetting('auto_update_hours', _autoUpdateHours); }),
            ),
          ),
          SwitchListTile(
            title: const Text('仅WiFi下更新'),
            value: _wifiOnly,
            onChanged: (v) => setState(() { _wifiOnly = v; _saveSetting('wifi_only', v); }),
          ),
          ListTile(
            title: const Text('预下载章节数'),
            trailing: DropdownButton<int>(
              value: _preDownloadCount,
              items: [0, 1, 3, 5, 10, 20].map((v) => DropdownMenuItem(value: v, child: Text('$v章'))).toList(),
              onChanged: (v) => setState(() { _preDownloadCount = v ?? 5; _updateReadConfig((c) => c.preDownloadCount = _preDownloadCount); }),
            ),
          ),
          const Divider(),

          // 数据管理
          _buildSectionHeader('数据管理'),
          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: const Text('备份与恢复'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BackupScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.cleaning_services_outlined),
            title: const Text('缓存管理'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CacheManageScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: const Text('清除缓存'),
            subtitle: const Text('清除书籍内容缓存'),
            onTap: () => _showClearCacheDialog(),
          ),
          const Divider(),

          // 主题管理
          _buildSectionHeader('主题管理'),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('自定义主题'),
            subtitle: const Text('管理和创建主题'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ThemeManageScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.photo_outlined),
            title: const Text('封面相册'),
            subtitle: const Text('管理书籍封面'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CoverAlbumScreen())),
          ),

          const Divider(),

          // TTS设置
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('漫画阅读设置'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MangaConfigScreen())),
          ),
          _buildSectionHeader('TTS设置'),
          ListTile(
            leading: const Icon(Icons.record_voice_over_outlined),
            title: const Text('TTS引擎管理'),
            subtitle: const Text('系统/云端TTS引擎'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CloudTtsScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.mic_outlined),
            title: const Text('朗读语速'),
            subtitle: const Text('调整TTS朗读速度'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              double rate = (await SharedPreferences.getInstance()).getDouble('tts_rate') ?? 1.0;
              if (!mounted) return;
              showModalBottomSheet(context: context, builder: (sheetCtx) => StatefulBuilder(builder: (ctx, setSt) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Padding(padding: EdgeInsets.all(16), child: Text('朗读语速', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: Text('${rate.toStringAsFixed(1)} 倍', style: const TextStyle(fontSize: 14))),
                Slider(value: rate, min: 0.3, max: 3.0, divisions: 27, label: '${rate.toStringAsFixed(1)}',
                  onChanged: (v) => setSt(() => rate = v),
                  onChangeEnd: (v) async => (await SharedPreferences.getInstance()).setDouble('tts_rate', v)),
                const SizedBox(height: 12),
              ]))));
            },
          ),

          const Divider(),

          // 下载缓存
          _buildSectionHeader('下载缓存'),
          ListTile(
            leading: const Icon(Icons.tune),
            title: const Text('下载缓存配置'),
            subtitle: const Text('线程/预下载/图片缓存/UA'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DownloadCacheConfigScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('下载管理'),
            subtitle: const Text('管理下载任务'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DownloadManageScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.storage_outlined),
            title: const Text('缓存管理'),
            subtitle: const Text('管理书籍缓存'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CacheManageScreen())),
          ),

          const Divider(),

          // 翻译设置
          _buildSectionHeader('翻译设置'),
          SwitchListTile(
            title: const Text('启用翻译'),
            value: _translateEnabled,
            onChanged: (v) async { await _prefs?.setBool('translate_enabled', v); setState(() => _translateEnabled = v); },
          ),
          ListTile(
            leading: const Icon(Icons.translate_outlined),
            title: const Text('翻译引擎'),
            subtitle: const Text('选择翻译服务'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TranslationScreen())),
          ),

          const Divider(),

          // 实验室
          _buildSectionHeader('实验室'),
          SwitchListTile(
            title: const Text('模拟阅读'),
            subtitle: const Text('自动模拟翻页阅读'),
            value: _simulateReading,
            onChanged: (v) async { await _prefs?.setBool('simulate_reading', v); setState(() => _simulateReading = v); },
          ),

          const Divider(),

          // 其他
          _buildSectionHeader('Web服务'),
          SwitchListTile(
            title: const Text('启用Web服务'),
            subtitle: const Text('通过浏览器管理书籍'),
            value: _webServiceEnabled,
            onChanged: _toggleWebService,
          ),
          ListTile(
            leading: const Icon(Icons.wifi),
            title: const Text('Web服务地址'),
            subtitle: Text(_webServiceEnabled ? 'http://$_lanIp:1122' : '未启用'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showWebServiceDialog(),
          ),
          ListTile(
            leading: const Icon(Icons.security),
            title: const Text('Web服务密码'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showWebPasswordDialog(),
          ),

          _buildSectionHeader('备份和恢复'),
          ListTile(
            leading: const Icon(Icons.backup),
            title: const Text('本地备份'),
            subtitle: const Text('备份到本地文件'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BackupScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('本地恢复'),
            subtitle: const Text('从本地文件恢复'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BackupScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.cloud),
            title: const Text('WebDAV备份'),
            subtitle: const Text('同步到WebDAV服务器'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BackupScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.file_download_outlined),
            title: const Text('导入书籍配置'),
            subtitle: const Text('导入路径/文件名规则/排序'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ImportBookConfigScreen())),
          ),
          SwitchListTile(
            title: const Text('自动备份'),
            subtitle: const Text('每天自动备份'),
            value: _autoBackup,
            onChanged: (v) => setState(() { _autoBackup = v; _saveSetting('auto_backup', v); }),
          ),

          _buildSectionHeader('缓存管理'),
          ListTile(
            leading: const Icon(Icons.cleaning_services),
            title: const Text('清理缓存'),
            subtitle: Text('当前缓存: $_cacheSize'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CacheManageScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.download_done),
            title: const Text('下载管理'),
            subtitle: const Text('管理已下载的章节'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showDownloadManager(),
          ),
          SwitchListTile(
            title: const Text('自动清理缓存'),
            subtitle: const Text('超过7天自动清理'),
            value: _autoCleanCache,
            onChanged: (v) => setState(() { _autoCleanCache = v; _saveSetting('auto_clean_cache', v); }),
          ),

          _buildSectionHeader('规则管理'),
          ListTile(
            leading: const Icon(Icons.find_replace),
            title: const Text('替换净化规则'),
            subtitle: const Text('管理内容替换规则'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showReplaceRuleScreen(),
          ),
          ListTile(
            leading: const Icon(Icons.list_alt),
            title: const Text('TXT目录规则'),
            subtitle: const Text('管理TXT书籍目录识别规则'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showTxtTocRuleScreen(),
          ),
          ListTile(
            leading: const Icon(Icons.menu_book),
            title: const Text('字典规则'),
            subtitle: const Text('管理字典和翻译规则'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showDictRuleScreen(),
          ),
          ListTile(
            leading: const Icon(Icons.label_outline),
            title: const Text('高亮标签配置'),
            subtitle: const Text('管理阅读高亮标签'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showHighlightRuleScreen(),
          ),

          _buildSectionHeader('首页模块'),
          ListTile(
            leading: const Icon(Icons.view_module),
            title: const Text('首页模块管理'),
            subtitle: const Text('自定义首页显示模块'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showHomepageModuleScreen(),
          ),

          _buildSectionHeader('其他'),
          SwitchListTile(
            title: const Text('显示通知栏'),
            value: _showNotification,
            onChanged: (v) => setState(() { _showNotification = v; _saveSetting('show_notification', v); }),
          ),
          SwitchListTile(
            title: const Text('横屏锁定'),
            value: _landscapeLock,
            onChanged: (v) => setState(() { _landscapeLock = v; _saveSetting('landscape_lock', v); }),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('关于'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showAboutDialog(),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
  );

  void _showColorPicker(AppTheme theme) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('主题色'),
        content: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            Colors.blue, Colors.green, Colors.orange, Colors.purple, Colors.red, Colors.teal, Colors.indigo, Colors.pink,
          ].map((color) => GestureDetector(
            onTap: () { theme.setSeedColor(color); Navigator.pop(context); },
            child: Container(width: 40, height: 40, decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: theme.seedColor == color ? Border.all(color: Colors.black, width: 2) : null)),
          )).toList(),
        ),
      ),
    );
  }

  void _showClearCacheDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除缓存'),
        content: const Text('确定要清除所有书籍内容缓存吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: () async {
            final db = DatabaseService();
            await db.clearChapterContent();
            if (mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('缓存已清除'))); }
          }, child: const Text('清除')),
        ],
      ),
    );
  }

  void _showWebServiceDialog() {
    showDialog(context: context, builder: (context) => AlertDialog(
      title: const Text('Web服务'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const ListTile(leading: Icon(Icons.wifi), title: Text('服务地址'), subtitle: Text('http://localhost:1122')),
        ListTile(leading: const Icon(Icons.devices), title: const Text('设备地址'), subtitle: Text('http://$_lanIp:1122')),
        const ListTile(leading: Icon(Icons.info_outline), title: Text('说明'), subtitle: Text('在同一局域网下，通过浏览器访问上述地址管理书籍')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
    ));
  }

  void _showWebPasswordDialog() {
    final controller = TextEditingController();
    showDialog(context: context, builder: (context) => AlertDialog(
      title: const Text('Web服务密码'),
      content: TextField(controller: controller, obscureText: true, decoration: const InputDecoration(hintText: '设置访问密码（留空表示无密码）')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: () { _saveSetting('web_password', controller.text); Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('密码已保存'))); }, child: const Text('保存')),
      ],
    ));
  }





  void _showDownloadManager() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const DownloadManageScreen()));
  }

  void _showReplaceRuleScreen() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ReplaceRuleScreen()));
  }

  void _showTxtTocRuleScreen() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const TxtTocRuleScreen()));
  }

  void _showDictRuleScreen() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const DictRuleScreen()));
  }

  void _showHighlightRuleScreen() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const HighlightTagRuleScreen()));
  }

  void _showHomepageModuleScreen() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const HomepageManageScreen()));
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('关于阅读 MD3'),
        content: const Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('版本: 3.30.0'),
          SizedBox(height: 8),
          Text('基于Legado MD3风格的跨平台阅读应用'),
          SizedBox(height: 8),
          Text('支持Android和iOS'),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('确定'))],
      ),
    );
  }
}
