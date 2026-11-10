
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:legado_md3/common/app_name.dart';
import 'package:legado_md3/constant/app_theme.dart';
import 'package:legado_md3/constant/e_placement.dart';
import 'package:legado_md3/help/web/web_service.dart';
import 'package:legado_md3/help/web/web_tile_channel.dart';
import 'package:legado_md3/ui/about/about_screen.dart';
import 'package:legado_md3/ui/backup/backup_screen.dart';
import 'package:legado_md3/ui/book/source/source_manage_screen.dart';
import 'package:legado_md3/ui/bookmark/bookmark_screen.dart';
import 'package:legado_md3/ui/config/dict_rule_screen.dart';
import 'package:legado_md3/ui/config/replace_rule_screen.dart';
import 'package:legado_md3/ui/config/other_config_screen.dart';
import 'package:legado_md3/ui/config/settings_screen.dart';
import 'package:legado_md3/ui/config/theme_manage_screen.dart';
import 'package:legado_md3/ui/config/txt_toc_rule_screen.dart';
import 'package:legado_md3/ui/config/auto_task_screen.dart';
import 'package:legado_md3/ui/config/homepage_module_screen.dart';
import 'package:legado_md3/ui/config/cloud_tts_screen.dart';
import 'package:legado_md3/ui/cache/download_manage_screen.dart';
import 'package:legado_md3/ui/file/file_manage_screen.dart';
import 'package:legado_md3/ui/stats/read_record_screen.dart';
import 'package:legado_md3/ui/stats/reading_stats_screen.dart';
import 'package:legado_md3/ui/ai/ai_chat_screen.dart';
import 'package:legado_md3/ui/ai/agent_tool_screen.dart';
import 'package:legado_md3/ui/welcome/welcome_config_screen.dart';
import 'package:legado_md3/ui/config/app_icon_screen.dart';
import 'package:legado_md3/ui/config/video_setting_screen.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// 本项目 GitHub 仓库
const _kRepoUrl = 'https://github.com/ReTyne/legado-Klys';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final WebService _webService = WebService();
  static const _wakeChannel = MethodChannel('legado/wakelock');
  bool _webServiceRunning = false;
  /// 动态版本号（package_info_plus），形如 "3.30.0 (2)"
  String _versionLabel = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        // pubspec 版本为规范三段式，展示层归一掉无意义的尾缀 .0（1.0.0 -> 1.0）
        final v = info.version.replaceFirst(RegExp(r'\.0$'), '');
        _versionLabel = '$v (${info.buildNumber})';
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _webService.stop();
    super.dispose();
  }

  Future<void> _toggleWebService(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    // 与「设置 → Web 服务」共用同一个开关 key，两处状态保持一致
    await prefs.setBool('oc_webAutoStart', value);
    if (value) {
      final port = prefs.getInt('oc_webPort') ?? 1122;
      await _webService.start(port: port);
      setState(() => _webServiceRunning = true);
      await WebTileChannel.syncFromUi();
      // Web 服务唤醒锁（oc_webWakeLock）
      if (prefs.getBool('oc_webWakeLock') ?? false) {
        try { await _wakeChannel.invokeMethod('enable'); } catch (_) {}
      }
      if (mounted) {
        final addr = await _webService.address;
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Web服务已启动: $addr')));
      }
    } else {
      await _webService.stop();
      setState(() => _webServiceRunning = false);
      await WebTileChannel.syncFromUi();
      try { await _wakeChannel.invokeMethod('disable'); } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Web服务已停止')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
        // E 版 main_my.xml 顶部菜单仅「帮助」1 项
        actions: [
          EOverflowMenuButton(
            items: eOverflowItemsFrom(
              EPlacement.mainMenus['my']!,
              onTapFor: (_) => () => _showHelp(context),
            ),
          ),
        ],
      ),
      body: ListView(
        children: [
          // ── 顶层 6 项（EPlacement.myTop，无分区标题）──
          _eTile(EPlacement.myTop[0], Icons.menu_book_outlined, '管理网络书源',
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SourceManageScreen()))),
          _eTile(EPlacement.myTop[1], Icons.list_alt_outlined, '本地TXT目录识别',
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TxtTocRuleScreen()))),
          _eTile(EPlacement.myTop[2], Icons.find_replace_outlined, '正文内容替换规则',
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReplaceRuleScreen()))),
          _eTile(EPlacement.myTop[3], Icons.translate_outlined, '文字替换字典',
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DictRuleScreen()))),
          _buildThemeModeTile(context, EPlacement.myTop[4]),
          SwitchListTile(
            key: Key(EPlacement.myTop[5].key),
            secondary: const Icon(Icons.web_outlined),
            title: Text(EPlacement.myTop[5].zh),
            subtitle: Text(_webServiceRunning ? '端口: ${_webService.port} (浏览器访问设备IP)' : '通过浏览器管理书架'),
            value: _webServiceRunning,
            onChanged: _toggleWebService,
          ),
          if (_webServiceRunning)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
              child: Text('在浏览器中打开上述地址即可管理书架、书源、RSS等', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ),

          // ── 分区「设置」（EPlacement.mySettingCategory）──
          _buildSectionHeader(EPlacement.myCategoryTitles[0]),
          _eTile(EPlacement.mySettingCategory[0], Icons.backup_outlined, 'WebDAV云同步与本地备份',
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BackupScreen()))),
          _eTile(EPlacement.mySettingCategory[1], Icons.palette_outlined, '自定义主题',
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ThemeManageScreen()))),
          _eTile(EPlacement.mySettingCategory[2], Icons.settings_outlined, '应用设置',
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OtherConfigScreen()))),

          // ── 分区「其它」（EPlacement.myOtherCategory）──
          _buildSectionHeader(EPlacement.myCategoryTitles[1]),
          _eTile(EPlacement.myOtherCategory[0], Icons.bookmark_border, '所有书签',
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BookmarkScreen()))),
          _eTile(EPlacement.myOtherCategory[1], Icons.history_outlined, '每本书的阅读明细',
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReadRecordScreen()))),
          _eTile(EPlacement.myOtherCategory[2], Icons.folder_outlined, '本地文件',
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FileManageScreen()))),
          _eTile(EPlacement.myOtherCategory[3], Icons.info_outline, '应用信息',
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutScreen()))),
          _eTile(EPlacement.myOtherCategory[4], Icons.exit_to_app_outlined, '退出应用',
              () => SystemNavigator.pop()),

          // ── K 版独有功能：默认折叠的次级分区（E 主落点优先，功能不删）──
          _buildMoreFeatures(context),

          const SizedBox(height: AppSpacing.xl),
          Center(
            child: Text(
              _versionLabel.isEmpty ? appDisplayName : '$appDisplayName v$_versionLabel',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          ),
          const SizedBox(height: AppSpacing.l),
        ],
      ),
    );
  }

  /// E 主落点列表项：文案 / Key / 顺序全部由 [EPlacement] 常量驱动，
  /// onTap 沿用原有跳转，tile 结构复用 [_buildMenuItem]。
  Widget _eTile(EMenuItem e, IconData icon, String subtitle, VoidCallback onTap) =>
      _buildMenuItem(context, icon, e.zh, subtitle, onTap, key: Key(e.key));

  /// 主题模式选择（对齐 legado-E pref_main 的 themeMode NameListPreference）
  Widget _buildThemeModeTile(BuildContext context, EMenuItem e) {
    final appTheme = context.watch<AppTheme>();
    const labels = ['跟随系统', '浅色', '深色'];
    return ListTile(
      key: Key(e.key),
      leading: const Icon(Icons.brightness_6_outlined),
      title: Text(e.zh),
      subtitle: Text(labels[appTheme.themeMode.index.clamp(0, 2)], style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showThemeModeDialog(context, appTheme),
    );
  }

  Future<void> _showThemeModeDialog(BuildContext context, AppTheme appTheme) async {
    const labels = ['跟随系统', '浅色', '深色'];
    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('主题模式'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(ThemeMode.values.length, (i) {
            return RadioListTile<int>(
              value: i,
              groupValue: appTheme.themeMode.index,
              title: Text(labels[i]),
              onChanged: (v) async {
                if (v == null) return;
                await appTheme.setThemeMode(ThemeMode.values[v]);
                if (c.mounted) Navigator.pop(c);
              },
            );
          }),
        ),
      ),
    );
  }

  /// E 版 main_my.xml 顶部菜单仅「帮助」1 项：给出应用用法说明。
  void _showHelp(BuildContext context) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('帮助'),
        content: const Text(
          '使用说明：\n'
          '· 在「我的」页管理书源、TXT 目录规则、替换净化与字典规则；\n'
          '· 通过「设置」分区进入备份与恢复、主题设置、其它设置；\n'
          '· 开启 Web 服务后可在浏览器中管理书架、书源与 RSS；\n'
          '· 更多增强功能收在页面底部「更多功能」分区中。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('知道了')),
        ],
      ),
    );
  }

  /// K 版独有功能（[EPlacement.kSecondary] 的 'profile' 清单）：
  /// 不删、不建独立扩展页，收在本页底部默认折叠的次级分区，E 主落点优先。
  /// 原 ListTile + 原跳转 / 回调原样保留，类名仍在本文件中。
  Widget _buildMoreFeatures(BuildContext context) {
    return ExpansionTile(
      key: const Key('profile::more_features'),
      initiallyExpanded: false,
      leading: const Icon(Icons.more_horiz),
      title: const Text('更多功能'),
      children: [
        _buildMenuItem(context, Icons.dashboard_customize_outlined, '首页模块', '自定义发现首页的模块与排序', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HomepageModuleScreen()))),
        _buildMenuItem(context, Icons.schedule_outlined, '定时任务', '定时刷新书架 / 缓存 / 备份 / 脚本', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AutoTaskScreen()))),
        _buildMenuItem(context, Icons.record_voice_over_outlined, '朗读引擎', '云端 / 自定义 HTTP TTS 与语音', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CloudTtsScreen()))),
        _buildMenuItem(context, Icons.download_outlined, '下载管理', '离线缓存队列与进度', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DownloadManageScreen()))),
        _buildMenuItem(context, Icons.smart_toy_outlined, 'AI 助手', '对话与智能体', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AiChatScreen()))),
        _buildMenuItem(context, Icons.build_circle_outlined, '智能体工具', 'AI 工具注册与启停', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AgentToolScreen()))),
        _buildMenuItem(context, Icons.waving_hand_outlined, '欢迎页设置', '首次启动引导与展示配置', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WelcomeConfigScreen()))),
        _buildMenuItem(context, Icons.apps_outlined, '桌面图标', '切换应用图标样式', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AppIconScreen()))),
        _buildMenuItem(context, Icons.video_settings_outlined, '视频设置', '播放、弹幕与画中画', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VideoSettingScreen()))),
        _buildMenuItem(context, Icons.bar_chart_outlined, '阅读统计', '时长与书籍分布', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReadingStatsScreen()))),
        _buildMenuItem(context, Icons.tune, '完整设置（旧版单页）', '分类导航页 + 旧版全部设置项', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()))),
        const Divider(),
        _buildMenuItem(context, Icons.code, 'GitHub项目', '打开项目仓库', () => launchUrl(Uri.parse(_kRepoUrl), mode: LaunchMode.externalApplication)),
        _buildMenuItem(context, Icons.share, '分享应用', '分享给好友', () => _shareApp()),
        _buildMenuItem(context, Icons.star_outline, '评分', '前往仓库页评分', () => _rateApp()),
      ],
    );
  }

  /// 分享应用：应用名 + GitHub 仓库链接
  Future<void> _shareApp() async {
    await Share.share('$appDisplayName —— Material 3 风格的跨平台开源阅读器\n$_kRepoUrl',
        subject: appDisplayName);
  }

  /// 评分：跳转 GitHub 仓库页面
  Future<void> _rateApp() async {
    try {
      final ok = await launchUrl(Uri.parse(_kRepoUrl), mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('无法打开页面')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('打开失败: $e')));
      }
    }
  }

  // 关于页 9 项能力已迁至 AboutScreen（lib/ui/about/about_screen.dart）；
  // 旧 _showAbout 弹窗移除，K 独有的 GitHub 项目 / 分享应用 / 评分入口已迁至
  // 上方「更多功能」默认折叠分区。

  Widget _buildSectionHeader(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(AppSpacing.l, AppSpacing.l, AppSpacing.l, AppSpacing.s),
    child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
  );

  Widget _buildMenuItem(BuildContext context, IconData icon, String title, String subtitle, VoidCallback onTap, {Key? key}) {
    return ListTile(
      key: key,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

// 对齐 legado-E pref_main：我的页无「实验室」入口，原 lab_config_screen 合并残留的
// LabConfigScreen 为全项目无引用的死代码，已移除，避免暴露 E 没有的实验性功能界面。

