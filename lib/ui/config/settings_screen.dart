import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:legado_md3/common/app_name.dart';
import 'package:legado_md3/constant/app_theme.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/read_config.dart';
import 'package:legado_md3/di/book_provider.dart';
import 'package:legado_md3/help/web/web_service.dart';
import 'package:legado_md3/help/web/web_tile_channel.dart';
import 'package:legado_md3/ui/backup/backup_screen.dart';
import 'package:legado_md3/ui/book/detail/book_detail_screen.dart';
import 'package:legado_md3/ui/book/manga/manga_config_screen.dart';
import 'package:legado_md3/ui/book/read/config/reading_settings_screen.dart';
import 'package:legado_md3/ui/cache/cache_manage_screen.dart';
import 'package:legado_md3/ui/cache/download_manage_screen.dart';
import 'package:legado_md3/ui/config/cloud_tts_screen.dart';
import 'package:legado_md3/ui/config/cover_config_screen.dart';
import 'package:legado_md3/ui/config/dict_rule_screen.dart';
import 'package:legado_md3/ui/config/download_cache_config_screen.dart';
import 'package:legado_md3/ui/config/highlight_tag_rule_screen.dart';
import 'package:legado_md3/ui/config/other_config_screen.dart';
import 'package:legado_md3/ui/config/keyboard_assist_screen.dart';
import 'package:legado_md3/ui/config/replace_rule_screen.dart';
import 'package:legado_md3/ui/config/theme_manage_screen.dart';
import 'package:legado_md3/ui/config/translation_screen.dart';
import 'package:legado_md3/ui/config/txt_toc_rule_screen.dart';
import 'package:legado_md3/ui/main/bookshelf/bookshelf_config_screen.dart';
import 'package:legado_md3/ui/main/homepage/homepage_manage_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  bool _webServiceEnabled = false;
  final WebService _webService = WebService();
  String _lanIp = 'localhost';
  bool _autoCleanCache = false;
  String _cacheSize = '0 MB';
  // 阅读辅助：导出文件名模板 / 目录章节字数开关
  String _exportNameTpl = '{name}';
  bool _tocCountWords = false;
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

  // ===== 补齐项：书籍 =====
  /// 仅更新已读完的书籍（only_update_read）
  bool _onlyUpdateRead = false;
  /// 书架是否显示本地导入书籍（bs_showLocalBook）
  bool _showLocalBook = false;
  /// 显示「发现」页（showDiscovery）
  bool _showDiscovery = true;
  /// 显示「订阅/RSS」页（showRss）
  bool _showRss = true;
  /// 默认首页页签（defaultHomePage：0书架 1发现 2订阅）
  int _defaultHomePage = 0;
  /// 新加入的书籍默认不更新（bk_bookUpdateDisable，对应 legado-E Book.canUpdate 默认值）
  bool _bookUpdateDisable = false;

  // ===== 补齐项：阅读 =====
  bool _clickTurnPage = true;
  bool _volumeKeyReverse = false;
  bool _horizontalPage = false;
  bool _scrollMode = false;
  bool _disableHorizontalScroll = false;
  bool _immersiveRead = false;
  bool _fullScreenRead = false;
  bool _longPressSelect = true;
  int _autoNextPageSpeed = 5;

  // ===== 补齐项：界面 =====
  bool _confirmExit = false;
  int _exitClickCount = 2;

  // ===== 补齐项：线程与并发 =====
  int _updateThreads = 32;

  // ===== 补齐项：缓存 / 备份 / 其它 =====
  int _cacheMaxMB = 500;
  String _cachePath = '';
  int _autoBackupHours = 24;
  String _backupPath = '';
  String _webdavUrl = '';
  bool _webdavSyncProgress = true;
  double _fontScale = 1.0;
  String _readFontPath = '';
  int _readFontCount = -1;

  static const List<String> _pageAnimNames = ['覆盖', '仿真', '滑动', '滚动', '无动画', '上下'];
  static const List<String> _alignNames = ['左对齐', '居中', '两端对齐'];
  static const List<String> _homePageNames = ['书架', '发现', '订阅'];

  /// 导出文件名模板编辑：变量 {name} {author} {group}。
  Future<void> _showExportNameTplDialog() async {
    final ctrl = TextEditingController(text: _exportNameTpl);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导出文件名模板'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(labelText: '模板', hintText: '{name}'),
            ),
            const SizedBox(height: 8),
            const Text('可用变量：{name} 书名 · {author} 作者 · {group} 分组', style: TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final v = ctrl.text.trim();
              final p = await SharedPreferences.getInstance();
              await p.setString('bookExportFileName', v.isEmpty ? '{name}' : v);
              if (mounted) setState(() => _exportNameTpl = v.isEmpty ? '{name}' : v);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    ctrl.dispose();
  }

  @override
  void initState() {
    super.initState();
    _restoreWebService();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    // 在 await 之前取 Provider，避免跨异步使用 context
    final readProvider = Provider.of<ReadProvider>(context, listen: false);
    final cfg = readProvider.config;
    _prefs = await SharedPreferences.getInstance();
    final p = _prefs!;
    setState(() {
      _autoUpdate = p.getBool('auto_update') ?? true;
      _autoUpdateHours = _prefs?.getInt('auto_update_hours') ?? 6;
      // 仅WiFi加载封面与封面配置共用同一键 cover_onlyWifi（bookshelf_screen 消费）
      _wifiOnly = p.getBool('cover_onlyWifi') ?? false;
      _volumeKeyPage = cfg.volumeKeyPage;
      _keepScreenOn = cfg.keepScreenOn;
      _showMenuOnTap = cfg.showMenuOnTap;
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
      _exportNameTpl = _prefs?.getString('bookExportFileName') ?? '{name}';
      _tocCountWords = _prefs?.getBool('tocCountWords') ?? false;

      // 书籍
      _onlyUpdateRead = p.getBool('only_update_read') ?? false;
      _showLocalBook = p.getBool('bs_showLocalBook') ?? false;
      _showDiscovery = p.getBool('showDiscovery') ?? true;
      _showRss = p.getBool('showRss') ?? true;
      _defaultHomePage = p.getInt('defaultHomePage') ?? 0;
      _bookUpdateDisable = p.getBool('bk_bookUpdateDisable') ?? false;

      // 阅读
      _clickTurnPage = cfg.clickTurnPage;
      _volumeKeyReverse = cfg.volumeKeyReverse;
      _horizontalPage = cfg.screenOrientation == 2;
      _scrollMode = cfg.pageAnim == 3;
      _disableHorizontalScroll = p.getBool('read_disableHorizontalSwipe') ?? false;
      _immersiveRead = cfg.immersiveMode;
      _fullScreenRead = cfg.fullScreen;
      _longPressSelect = cfg.longPressSelect;
      _autoNextPageSpeed = cfg.autoNextPageSpeed;

      // 界面
      _confirmExit = p.getBool('ui_confirmExit') ?? false;
      _exitClickCount = p.getInt('ui_exitClickCount') ?? 2;

      // 线程与并发（仅保留有真实消费方的 bk_updateThreads，见 auto_update_service）
      _updateThreads = p.getInt('bk_updateThreads') ?? 32;

      // 缓存 / 备份 / 其它
      _cacheMaxMB = p.getInt('cache_contentMaxMB') ?? 500;
      _autoBackupHours = p.getInt('auto_backup_hours') ?? 24;
      // 自动清理过期内容与其他设置共用同一键 oc_autoClearExpired（main.dart 消费）
      _autoCleanCache = p.getBool('oc_autoClearExpired') ?? false;
      final bd = p.getString('backup_path') ?? '';
      _backupPath = bd.isEmpty ? 'Legado/backup' : bd;
      _webdavUrl = p.getString('webdav_url') ?? '';
      _webdavSyncProgress = p.getBool('webdav_syncProgress') ?? true;
      _fontScale = p.getDouble('fontScale') ?? 1.0;
      _readFontPath = p.getString('read_font_path') ?? '';
    });
    _loadCachePath();
    _calcCacheSize();
  }

  /// 解析缓存目录的实际绝对路径用于展示
  Future<void> _loadCachePath() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      if (!mounted) return;
      setState(() => _cachePath = dir.path);
    } catch (_) {}
  }

  /// 更新阅读配置并持久化（同步到 ReadProvider，阅读界面实时生效）
  void _updateReadConfig(void Function(ReadConfig) updater) {
    Provider.of<ReadProvider>(context, listen: false).updateConfig(updater);
  }

  Future<void> _calcCacheSize() async {
    try {
      final db = DatabaseService();
      // SQL 聚合已缓存正文总字符数，避免遍历所有书 × 章节在内存中累加
      final chars = await db.getCachedContentLength();
      // 中文按 UTF-8 约 3 字节估算
      final bytes = chars * 2;
      String size;
      if (bytes < 1024) { size = '$bytes B'; }
      else if (bytes < 1024 * 1024) { size = '${(bytes / 1024).toStringAsFixed(1)} KB'; }
      else { size = '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB'; }
      if (mounted) setState(() => _cacheSize = size);
    } catch (_) {}
  }

  Future<void> _restoreWebService() async {
    try {
      // 网卡枚举是同步 IO：包一层 Future 让出执行流，避免阻塞启动
      final ifaces = await Future(() => NetworkInterface.list(type: InternetAddressType.IPv4));
      for (final ifc in ifaces) {
        for (final a in ifc.addresses) {
          if (!a.isLoopback) { _lanIp = a.address; break; }
        }
      }
    } catch (_) {}
    final p = await SharedPreferences.getInstance();
    // Web 服务开关与「其他设置-Web服务自动启动」共用同一键 oc_webAutoStart（main.dart 启动时消费）
    if (p.getBool('oc_webAutoStart') ?? false) {
      _webServiceEnabled = true;
      _webService.start().then((_) => WebTileChannel.syncFromUi()).catchError((_) {});
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggleWebService(bool v) async {
    setState(() { _webServiceEnabled = v; });
    await _saveSetting('oc_webAutoStart', v);
    try {
      if (v) {
        final port = (await SharedPreferences.getInstance()).getInt('oc_webPort') ?? 1122;
        await _webService.start(port: port);
        await WebTileChannel.syncFromUi();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Web服务已启动 http://$_lanIp:$port')));
      } else {
        await _webService.stop();
        await WebTileChannel.syncFromUi();
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
          ..._buildBooksSection(),
          _buildSectionHeader('主题设置'),
          ListTile(
            title: const Text('主题模式'),
            subtitle: Text(_themeModeName(theme.themeMode)),
            trailing: DropdownButton<ThemeMode>(
              value: theme.themeMode,
              items: const [
                DropdownMenuItem(value: ThemeMode.system, child: Text('跟随系统')),
                DropdownMenuItem(value: ThemeMode.light, child: Text('浅色')),
                DropdownMenuItem(value: ThemeMode.dark, child: Text('深色')),
              ],
              onChanged: (v) {
                if (v != null) theme.setThemeMode(v);
              },
            ),
          ),
          SwitchListTile(
            title: const Text('Material You 动态取色'),
            subtitle: Text(theme.dynamicColor ? '已开启：按系统动态色偏好' : '已关闭：使用下方固定主题色'),
            value: theme.dynamicColor,
            onChanged: (v) => theme.setDynamicColor(v),
          ),
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
          _buildSectionHeader('阅读辅助'),
          ListTile(
            leading: const Icon(Icons.keyboard),
            title: const Text('键盘助手'),
            subtitle: const Text('规则编辑时快捷插入常用文本'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const KeyboardAssistScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.drive_file_rename_outline),
            title: const Text('导出文件名模板'),
            subtitle: Text(_exportNameTpl),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showExportNameTplDialog,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.numbers),
            title: const Text('目录显示章节字数'),
            subtitle: const Text('在目录列表中显示每章字数'),
            value: _tocCountWords,
            onChanged: (v) async {
              setState(() => _tocCountWords = v);
              final p = await SharedPreferences.getInstance();
              await p.setBool('tocCountWords', v);
            },
          ),
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
          ..._buildReadExtraSection(),
          ..._buildUiSection(),
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
            subtitle: const Text('与「封面配置-仅WiFi加载封面」为同一设置（cover_onlyWifi）'),
            value: _wifiOnly,
            onChanged: (v) => setState(() { _wifiOnly = v; _saveSetting('cover_onlyWifi', v); }),
          ),
          ListTile(
            title: const Text('预下载章节数'),
            trailing: DropdownButton<int>(
              value: _preDownloadCount,
              items: [0, 1, 3, 5, 10, 20].map((v) => DropdownMenuItem(value: v, child: Text('$v章'))).toList(),
              onChanged: (v) => setState(() { _preDownloadCount = v ?? 5; _updateReadConfig((c) => c.preDownloadCount = _preDownloadCount); }),
            ),
          ),
          ..._buildThreadSection(),
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
          ..._buildCacheExtraSection(),
          SwitchListTile(
            title: const Text('自动备份'),
            subtitle: Text(_autoBackupHours > 0
                ? '每 $_autoBackupHours 小时自动备份一次（auto_backup_hours）'
                : '已关闭：将 auto_backup_hours 置 0'),
            value: _autoBackupHours > 0,
            onChanged: (v) => setState(() {
              _autoBackupHours = v ? (_autoBackupHours > 0 ? _autoBackupHours : 24) : 0;
              _saveSetting('auto_backup_hours', _autoBackupHours);
            }),
          ),
          ..._buildBackupExtraSection(),
          SwitchListTile(
            title: const Text('自动清理缓存'),
            subtitle: const Text('超过7天自动清理（与「其他设置-自动清理过期内容」为同一设置 oc_autoClearExpired）'),
            value: _autoCleanCache,
            onChanged: (v) => setState(() {
              _autoCleanCache = v;
              _saveSetting('oc_autoClearExpired', v);
            }),
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
            subtitle: const Text('保存语速偏好 tts_rate（0.3-3.0 倍）；朗读引擎读取该值的接线由 tts_service 完成'),
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
            onChanged: (v) => setState(() { _simulateReading = v; _updateReadConfig((c) => c.simulatedReading = v); }),
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

          ..._buildOtherExtraSection(),
          _buildSectionHeader('其他'),
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

  /* ===== 以下为补齐设置项（对齐 legado-E pref_config_other / pref_main） ===== */

  /// 通用开关项
  Widget _sw(String title, bool value, ValueChanged<bool> onChanged, {String? sub}) => SwitchListTile(
    dense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    title: Text(title, style: const TextStyle(fontSize: 14)),
    subtitle: sub == null ? null : Text(sub, style: const TextStyle(fontSize: 11)),
    value: value,
    onChanged: onChanged,
  );

  /// 整数步进控件（±1）
  Widget _step(String title, int value, int min, int max, ValueChanged<int> onChanged, {String? sub}) => ListTile(
    dense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    title: Text(title, style: const TextStyle(fontSize: 14)),
    subtitle: sub == null ? null : Text(sub, style: const TextStyle(fontSize: 11)),
    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(
        icon: const Icon(Icons.remove_circle_outline),
        tooltip: '减少',
        onPressed: value > min ? () => onChanged(value - 1) : null,
      ),
      SizedBox(
        width: 40,
        child: Text('$value', textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ),
      IconButton(
        icon: const Icon(Icons.add_circle_outline),
        tooltip: '增加',
        onPressed: value < max ? () => onChanged(value + 1) : null,
      ),
    ]),
  );

  /// 通用跳转项
  Widget _jump({IconData? icon, required String title, String? sub, required Widget page}) => ListTile(
    leading: icon == null ? null : Icon(icon),
    title: Text(title),
    subtitle: sub == null ? null : Text(sub),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
  );

  /// 书籍类设置（对齐 legado-E pref_config_other 的 main_activity 分类）
  List<Widget> _buildBooksSection() => [
    _buildSectionHeader('书架与书籍'),
    _sw('仅更新已读完的书籍', _onlyUpdateRead, (v) {
      setState(() => _onlyUpdateRead = v);
      _saveSetting('only_update_read', v);
    }, sub: '更新时只刷新已读完的书籍'),
    _sw('书架显示本地书籍', _showLocalBook, (v) {
      setState(() => _showLocalBook = v);
      _saveSetting('bs_showLocalBook', v);
    }, sub: '导入到本机的 TXT/EPUB 一并显示在书架'),
    _sw('显示发现页', _showDiscovery, (v) {
      setState(() => _showDiscovery = v);
      _saveSetting('showDiscovery', v);
    }),
    _sw('显示订阅页', _showRss, (v) {
      setState(() => _showRss = v);
      _saveSetting('showRss', v);
    }),
    ListTile(
      dense: true,
      title: const Text('默认首页'),
      subtitle: Text(_homePageNames[_defaultHomePage.clamp(0, _homePageNames.length - 1)], style: const TextStyle(fontSize: 11)),
      trailing: DropdownButton<int>(
        value: _defaultHomePage,
        items: List.generate(_homePageNames.length, (i) => DropdownMenuItem(value: i, child: Text(_homePageNames[i]))),
        onChanged: (v) {
          final nv = v ?? 0;
          setState(() => _defaultHomePage = nv);
          _saveSetting('defaultHomePage', nv);
        },
      ),
    ),
    _sw('新书默认不更新', _bookUpdateDisable, (v) {
      setState(() => _bookUpdateDisable = v);
      _saveSetting('bk_bookUpdateDisable', v);
    }, sub: '加入书架的书籍默认关闭自动更新'),
    _jump(icon: Icons.grid_view_outlined, title: '书架布局与排序', sub: '分组/排序/网格/角标', page: const BookshelfConfigScreen()),
  ];

  /// 阅读类补充设置（走 ReadProvider<ReadConfig>，阅读界面即时生效）
  List<Widget> _buildReadExtraSection() => [
    _buildSectionHeader('阅读设置补充'),
    _sw('点击翻页区域', _clickTurnPage, (v) {
      setState(() => _clickTurnPage = v);
      _updateReadConfig((c) => c.clickTurnPage = v);
    }, sub: '关闭后点击屏幕不翻页'),
    _sw('音量键反向翻页', _volumeKeyReverse, (v) {
      setState(() => _volumeKeyReverse = v);
      _updateReadConfig((c) => c.volumeKeyReverse = v);
    }),
    _sw('横向翻页', _horizontalPage, (v) {
      setState(() => _horizontalPage = v);
      _updateReadConfig((c) => c.screenOrientation = v ? 2 : 0);
    }, sub: '阅读时强制横屏'),
    _sw('滚屏模式', _scrollMode, (v) {
      setState(() => _scrollMode = v);
      _updateReadConfig((c) => c.pageAnim = v ? 3 : 0);
    }, sub: '等价于翻页动画=滚动'),
    _sw('禁用水平滑动', _disableHorizontalScroll, (v) {
      setState(() => _disableHorizontalScroll = v);
      _saveSetting('read_disableHorizontalSwipe', v);
    }, sub: '禁止左右滑动切换章节'),
    _sw('沉浸式阅读', _immersiveRead, (v) {
      setState(() => _immersiveRead = v);
      _updateReadConfig((c) => c.immersiveMode = v);
    }),
    _sw('阅读全屏', _fullScreenRead, (v) {
      setState(() => _fullScreenRead = v);
      _updateReadConfig((c) => c.fullScreen = v);
    }),
    _sw('长按选择文字', _longPressSelect, (v) {
      setState(() => _longPressSelect = v);
      _updateReadConfig((c) => c.longPressSelect = v);
    }),
    ListTile(
      dense: true,
      title: Text('自动翻页间隔: $_autoNextPageSpeed 秒'),
      subtitle: Slider(
        value: _autoNextPageSpeed.clamp(1, 20).toDouble(),
        min: 1, max: 20, divisions: 19,
        label: '$_autoNextPageSpeed 秒',
        onChanged: (v) {
          setState(() => _autoNextPageSpeed = v.toInt());
          _updateReadConfig((c) => c.autoNextPageSpeed = v.toInt());
        },
      ),
    ),
    _jump(icon: Icons.menu_book_outlined, title: '完整阅读设置', sub: '字体/间距/页边距/反馈区域', page: const ReadingSettingsScreen()),
  ];

  /// 界面设置（沉浸式/全屏/退出确认）
  /// 说明：阅读页沉浸/横屏由 ReadConfig.immersiveMode / fullScreen / screenOrientation
  /// 驱动（见 reading_screen._applyScreenMode），已在「阅读设置补充」中提供真实开关，
  /// 此处的 ui_immersionStatusBar / landscape_lock 预置键无消费方，已移除。
  List<Widget> _buildUiSection() => [
    _buildSectionHeader('界面'),
    ListTile(
      dense: true,
      title: const Text('全屏显示'),
      subtitle: const Text('隐藏系统状态栏与导航栏', style: TextStyle(fontSize: 11)),
      trailing: const Icon(Icons.fullscreen),
      onTap: () async {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已进入全屏，上滑可临时唤出系统栏')));
      },
    ),
    _sw('返回键退出确认', _confirmExit, (v) {
      setState(() => _confirmExit = v);
      _saveSetting('ui_confirmExit', v);
    }, sub: '在首页按返回时提示再按一次退出'),
    _step('连续点击退出次数', _exitClickCount, 2, 5, (v) {
      setState(() => _exitClickCount = v);
      _saveSetting('ui_exitClickCount', v);
    }, sub: '需要连续点击几次返回键才退出'),
  ];

  /// 线程与并发（只保留有真实消费方的项；其余无消费点已移除）
  List<Widget> _buildThreadSection() => [
    _buildSectionHeader('线程与并发'),
    _step('更新线程数', _updateThreads, 1, 64, (v) {
      setState(() => _updateThreads = v);
      _saveSetting('bk_updateThreads', v);
    }, sub: '刷新书架时同时更新的书籍数量（bk_updateThreads）'),
  ];

  /// 缓存（大小/路径/清理入口）
  List<Widget> _buildCacheExtraSection() => [
    _buildSectionHeader('缓存'),
    ListTile(
      dense: true,
      title: Text('内容缓存上限: ${_cacheMaxMB}MB'),
      subtitle: Slider(
        value: _cacheMaxMB.clamp(50, 2048).toDouble(),
        min: 50, max: 2048, divisions: 39,
        label: '${_cacheMaxMB}MB',
        onChanged: (v) {
          final nv = (v / 50).round() * 50;
          setState(() => _cacheMaxMB = nv);
          _saveSetting('cache_contentMaxMB', nv);
        },
      ),
    ),
    ListTile(
      dense: true,
      leading: const Icon(Icons.folder_open_outlined),
      title: const Text('缓存路径'),
      subtitle: Text(_cachePath.isEmpty ? '读取中…' : _cachePath, style: const TextStyle(fontSize: 11)),
    ),
    ListTile(
      dense: true,
      leading: const Icon(Icons.cleaning_services_outlined),
      title: const Text('缓存清理'),
      subtitle: Text('当前已缓存正文: $_cacheSize / 上限 ${_cacheMaxMB}MB', style: const TextStyle(fontSize: 11)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CacheManageScreen())),
    ),
  ];

  /// 备份（自动备份间隔/路径/WebDAV）
  List<Widget> _buildBackupExtraSection() => [
    _buildSectionHeader('备份'),
    _step('自动备份间隔（小时）', _autoBackupHours, 0, 168, (v) {
      setState(() => _autoBackupHours = v);
      _saveSetting('auto_backup_hours', v);
    }, sub: _autoBackupHours == 0 ? '当前为 0：关闭自动备份' : '每 $_autoBackupHours 小时执行一次，0 表示关闭'),
    ListTile(
      dense: true,
      leading: const Icon(Icons.folder_outlined),
      title: const Text('本地备份路径'),
      subtitle: Text(_backupPath, style: const TextStyle(fontSize: 11)),
      trailing: const Icon(Icons.edit, size: 18),
      onTap: () async {
        final ctl = TextEditingController(text: _backupPath);
        if (!mounted) return;
        final v = await showDialog<String>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('备份路径'),
            content: TextField(controller: ctl, decoration: const InputDecoration(hintText: 'Legado/backup')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
              FilledButton(onPressed: () => Navigator.pop(c, ctl.text), child: const Text('确定')),
            ],
          ),
        );
        if (v != null && v.isNotEmpty) {
          setState(() => _backupPath = v);
          _saveSetting('backup_path', v);
        }
      },
    ),
    ListTile(
      dense: true,
      leading: const Icon(Icons.cloud_outlined),
      title: const Text('WebDAV 配置'),
      subtitle: Text(_webdavUrl.isEmpty ? '未配置' : _webdavUrl, style: const TextStyle(fontSize: 11)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => const BackupScreen()));
        if (!mounted) return;
        final p = await SharedPreferences.getInstance();
        setState(() {
          _webdavUrl = p.getString('webdav_url') ?? '';
          _webdavSyncProgress = p.getBool('webdav_syncProgress') ?? true;
        });
      },
    ),
    _sw('同步阅读进度', _webdavSyncProgress, (v) {
      setState(() => _webdavSyncProgress = v);
      _saveSetting('webdav_syncProgress', v);
    }, sub: '备份时同时上传阅读进度（webdav_syncProgress）'),
  ];

  /// 其它（字体/字体大小/动态色）
  List<Widget> _buildOtherExtraSection() => [
    _buildSectionHeader('其它'),
    ListTile(
      dense: true,
      leading: const Icon(Icons.font_download_outlined),
      title: const Text('阅读字体'),
      subtitle: Text(_fontSubtitle(), style: const TextStyle(fontSize: 11)),
      trailing: const Icon(Icons.chevron_right),
      onTap: _showFontPicker,
    ),
    ListTile(
      dense: true,
      title: Text('界面字体缩放: ${(_fontScale * 100).round()}%'),
      subtitle: Slider(
        value: _fontScale,
        min: 0.8, max: 1.6, divisions: 16,
        label: '${(_fontScale * 100).round()}%',
        onChanged: (v) {
          setState(() => _fontScale = v);
          _saveSetting('fontScale', v);
        },
      ),
    ),
  ];

  String _readFontName() {
    if (_readFontPath.isEmpty) return '系统默认';
    final parts = _readFontPath.split(RegExp(r'[\\/]'));
    return parts.isEmpty ? _readFontPath : parts.last;
  }

  String _themeModeName(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return '跟随系统明暗切换（theme_mode）';
      case ThemeMode.light:
        return '始终浅色';
      case ThemeMode.dark:
        return '始终深色';
    }
  }

  /// Flutter FontLoader 仅支持 ttf/otf/ttc，woff 无法加载，扫描时过滤
  static const List<String> _fontExtensions = ['.ttf', '.otf', '.ttc'];

  String _fontSubtitle() {
    final name = _readFontName();
    if (_readFontCount < 0) return name;
    return '（共扫描到 $_readFontCount 个字体）$name';
  }

  String _baseName(String path) {
    final parts = path.split(RegExp(r'[\\/]'));
    final file = parts.isEmpty ? path : parts.last;
    final dot = file.lastIndexOf('.');
    return dot > 0 ? file.substring(0, dot) : file;
  }

  /// 扫描字体：内置 assets/web/fonts + 应用文档目录 + 外部存储 Fonts 目录
  Future<List<_FontEntry>> _scanFonts() async {
    final result = <_FontEntry>[];
    final seen = <String>{};

    void add(_FontEntry e) {
      if (seen.add('${e.source}|${e.name}')) result.add(e);
    }

    // 1) 内置资源（AssetManifest 列出真实文件清单）
    try {
      final manifest = jsonDecode(await rootBundle.loadString('AssetManifest.json')) as Map<String, dynamic>;
      for (final key in manifest.keys) {
        final lower = key.toLowerCase();
        if (!lower.startsWith('assets/web/fonts/')) continue;
        if (!_fontExtensions.any(lower.endsWith)) continue;
        add(_FontEntry(path: key, name: _baseName(key), source: '内置资源', asset: true));
      }
    } catch (_) {}

    // 2) 应用文档目录 +（Android）外部存储 Fonts 目录
    final roots = <Directory>[];
    try {
      roots.add(await getApplicationDocumentsDirectory());
      if (Platform.isAndroid) {
        final ext = await getExternalStorageDirectory();
        if (ext != null) roots.add(ext);
      }
    } catch (_) {}

    for (final root in roots) {
      for (final sub in <String>['Fonts', 'fonts', '']) {
        final dir = sub.isEmpty ? root : Directory('${root.path}${Platform.pathSeparator}$sub');
        if (!await dir.exists()) continue;
        try {
          await for (final entity in dir.list()) {
            if (entity is! File) continue;
            final lower = entity.path.toLowerCase();
            if (!_fontExtensions.any(lower.endsWith)) continue;
            add(_FontEntry(path: entity.path, name: _baseName(entity.path), source: '本机文件', asset: false));
          }
        } catch (_) {}
      }
    }
    return result..sort((a, b) => a.name.compareTo(b.name));
  }

  /// 字体选择：列出真实字体文件名，选择后加载并持久化 read_font_path
  Future<void> _showFontPicker() async {
    final fonts = await _scanFonts();
    if (!mounted) return;
    setState(() => _readFontCount = fonts.length);

    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(children: [
              const Icon(Icons.font_download_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text('选择阅读字体（${fonts.length}）', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
            ]),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                RadioListTile<String>(
                  title: const Text('系统默认'),
                  value: '',
                  groupValue: _readFontPath,
                  onChanged: (_) => _resetFont(sheetCtx),
                ),
                if (fonts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('未扫描到字体文件\n可将 .ttf/.otf 放入应用文档的 Fonts 目录', textAlign: TextAlign.center)),
                  ),
                ...fonts.map((f) => RadioListTile<String>(
                      title: Text(f.name, style: TextStyle(fontFamily: _loadedFamilies.contains(f.name) ? f.name : null)),
                      subtitle: Text('${f.source} · ${f.path}', style: const TextStyle(fontSize: 11)),
                      value: f.path,
                      groupValue: _readFontPath,
                      onChanged: (_) => _applyFont(f, sheetCtx),
                    )),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  /// 已在本会话通过 FontLoader 载入成功的字体族名
  final Set<String> _loadedFamilies = <String>{};

  /// 恢复系统默认字体
  Future<void> _resetFont(BuildContext sheetCtx) async {
    _updateReadConfig((c) => c.fontFamily = null);
    final p = await SharedPreferences.getInstance();
    await p.setString('read_font_path', '');
    if (!mounted) return;
    setState(() => _readFontPath = '');
    if (sheetCtx.mounted) Navigator.pop(sheetCtx);
  }

  /// 应用选中字体：加载字体 + 写入 ReadConfig.fontFamily（阅读界面即时生效）+ 持久化 read_font_path
  Future<void> _applyFont(_FontEntry font, BuildContext sheetCtx) async {
    try {
      final ByteData data = font.asset
          ? await rootBundle.load(font.path)
          : ByteData.sublistView(await File(font.path).readAsBytes());
      final family = font.name;
      final loader = FontLoader(family)..addFont(Future<ByteData>.value(data));
      await loader.load();
      _loadedFamilies.add(family);
      _updateReadConfig((c) => c.fontFamily = family);
      final p = await SharedPreferences.getInstance();
      await p.setString('read_font_path', font.path);
      await p.setString('font_family', family);
      if (!mounted) return;
      setState(() => _readFontPath = font.path);
      if (sheetCtx.mounted) Navigator.pop(sheetCtx);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已应用字体「$family」')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('字体加载失败: $e')));
    }
  }

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

  void _showAboutDialog() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    // pubspec 版本为规范三段式，展示层归一掉无意义的尾缀 .0（1.0.0 -> 1.0）
    final version = info.version.replaceFirst(RegExp(r'\.0$'), '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('关于$appDisplayName'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('版本: $version'),
          const SizedBox(height: 8),
          const Text('基于 legado 的 Material Design 3 跨平台阅读应用'),
          const SizedBox(height: 8),
          const Text('支持Android和iOS'),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('确定'))],
      ),
    );
  }
}

/* ===== 由 cover_album_screen.dart 合并 ===== */

/// 封面相册 - 以网格展示书架所有书籍封面
class CoverAlbumScreen extends StatefulWidget {
  const CoverAlbumScreen({super.key});

  @override
  State<CoverAlbumScreen> createState() => _CoverAlbumScreenState();
}

class _CoverAlbumScreenState extends State<CoverAlbumScreen> {
  final DatabaseService _db = DatabaseService();
  List<Book> _books = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final books = await _db.getAllBooks();
    if (mounted) setState(() { _books = books; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('封面相册 (${_books.length})')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _books.isEmpty
              ? const Center(child: Text('书架暂无书籍'))
              : GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 0.72),
                  itemCount: _books.length,
                  itemBuilder: (context, i) {
                    final book = _books[i];
                    return GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BookDetailScreen(book: book))),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Expanded(child: _cover(book)),
                        const SizedBox(height: 4),
                        Text(book.name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11)),
                      ]),
                    );
                  },
                ),
    );
  }

  Widget _cover(Book book) {
    final url = book.customCoverUrl?.isNotEmpty == true ? book.customCoverUrl! : book.coverUrl;
    if (url != null && url.isNotEmpty && url.startsWith('http')) {
      return ClipRRect(borderRadius: BorderRadius.circular(6),
        child: Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder(book)));
    }
    return _placeholder(book);
  }

  Widget _placeholder(Book book) => ClipRRect(borderRadius: BorderRadius.circular(6),
    child: Container(
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [Theme.of(context).colorScheme.primaryContainer, Theme.of(context).colorScheme.secondaryContainer])),
      child: Center(child: Padding(padding: const EdgeInsets.all(4), child: Text(book.name, maxLines: 3, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onPrimaryContainer))))));
}

/* ===== 由 import_book_config_screen.dart 合并 ===== */
/// 导入书籍配置已移除：import_path / import_sort / import_nameTpl 无任何消费方，
/// ImportBookService.importPath(path) 仅接收调用方传入的 path 参数。

/// 字体选择列表项：区分内置资源与本机文件，便于 FontLoader 取字节
class _FontEntry {
  final String path;
  final String name;
  final String source;
  final bool asset;
  const _FontEntry({required this.path, required this.name, required this.source, required this.asset});
}

