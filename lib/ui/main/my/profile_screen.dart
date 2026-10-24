
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:legado_md3/help/config/app_config.dart';
import 'package:legado_md3/common/app_name.dart';
import 'package:legado_md3/help/storage/crash_log_helper.dart';
import 'package:legado_md3/help/web/web_service.dart';
import 'package:legado_md3/help/web/web_tile_channel.dart';
import 'package:legado_md3/ui/ai/ai_chat_screen.dart';
import 'package:legado_md3/ui/backup/backup_screen.dart';
import 'package:legado_md3/ui/book/source/opds_screen.dart';
import 'package:legado_md3/ui/book/source/source_manage_screen.dart';
import 'package:legado_md3/ui/bookmark/book_marking_screen.dart';
import 'package:legado_md3/ui/bookmark/bookmark_screen.dart';
import 'package:legado_md3/ui/cache/cache_manage_screen.dart';
import 'package:legado_md3/ui/config/cloud_tts_screen.dart';
import 'package:legado_md3/ui/config/dict_rule_screen.dart';
import 'package:legado_md3/ui/config/highlight_tag_rule_screen.dart';
import 'package:legado_md3/ui/config/replace_rule_screen.dart';
import 'package:legado_md3/ui/config/settings_screen.dart';
import 'package:legado_md3/ui/config/tag_group_rule_screen.dart';
import 'package:legado_md3/ui/config/theme_manage_screen.dart';
import 'package:legado_md3/ui/config/translation_screen.dart';
import 'package:legado_md3/ui/config/txt_toc_rule_screen.dart';
import 'package:legado_md3/ui/file/file_manage_screen.dart';
import 'package:legado_md3/ui/main/homepage/homepage_manage_screen.dart';
import 'package:legado_md3/ui/main/subscribe/subscribe_screen.dart';
import 'package:legado_md3/ui/rss/rule_subscription_screen.dart';
import 'package:legado_md3/ui/stats/reading_stats_screen.dart';
import 'package:legado_md3/ui/stats/read_record_screen.dart';
import 'package:legado_md3/ui/cache/download_manage_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// 本项目 GitHub 仓库
const _kRepoUrl = 'https://github.com/ReTyne/legado-Klys';
/// 最新 release 查询接口（GitHub API）
const _kReleasesLatestApi =
    'https://api.github.com/repos/ReTyne/legado-Klys/releases/latest';

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
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        children: [
          _buildSectionHeader('规则分段'),
          _buildMenuItem(context, Icons.menu_book_outlined, '书源管理', '管理网络书源', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SourceManageScreen()))),
          _buildMenuItem(context, Icons.cloud_sync_outlined, 'OPDS书源', 'OPDS 目录浏览', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OpdsScreen()))),
          _buildMenuItem(context, Icons.find_replace_outlined, '替换净化', '正文内容替换规则', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReplaceRuleScreen()))),
          _buildMenuItem(context, Icons.list_alt_outlined, 'TXT目录规则', '本地TXT目录识别', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TxtTocRuleScreen()))),
          _buildMenuItem(context, Icons.translate_outlined, '字典规则', '文字替换字典', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DictRuleScreen()))),
          _buildMenuItem(context, Icons.tag_outlined, '高亮标签配置', '阅读内容高亮', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HighlightTagRuleScreen()))),
          _buildMenuItem(context, Icons.dashboard_customize, '首页模块', '自定义首页模块', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HomepageManageScreen()))),
          _buildMenuItem(context, Icons.account_tree_outlined, '标签分组规则', '按标签自动分组', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TagGroupRuleScreen()))),

          const Divider(),

          _buildSectionHeader('其他'),
          if (AppConfig.enableAiChat)
            _buildMenuItem(context, Icons.smart_toy_outlined, 'AI聊天', 'AI助手对话', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AiChatScreen()))),
          _buildMenuItem(context, Icons.rss_feed_outlined, 'RSS订阅', '订阅源管理', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SubscribeScreen()))),
          _buildMenuItem(context, Icons.cloud_outlined, '云盘同步', 'WebDAV云同步', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BackupScreen()))),
          _buildMenuItem(context, Icons.subscriptions_outlined, '规则订阅', '订阅书源规则', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RuleSubscriptionScreen()))),
          _buildMenuItem(context, Icons.download_outlined, '下载管理', '管理下载任务', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DownloadManageScreen()))),
          _buildMenuItem(context, Icons.palette_outlined, '主题管理', '自定义主题', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ThemeManageScreen()))),
          _buildMenuItem(context, Icons.record_voice_over_outlined, 'TTS设置', '朗读引擎设置', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CloudTtsScreen()))),
          _buildMenuItem(context, Icons.translate_outlined, '翻译设置', '翻译引擎配置', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TranslationScreen()))),
          _buildMenuItem(context, Icons.science_outlined, '实验室', '实验性功能', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LabConfigScreen()))),
          _buildMenuItem(context, Icons.flag_outlined, '书籍标记', '标记管理', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BookMarkingScreen(bookName: '', author: '')))),
          _buildMenuItem(context, Icons.settings_outlined, '设置', '应用设置', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()))),
          _buildMenuItem(context, Icons.bookmark_border, '书签', '所有书签', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BookmarkScreen()))),
          _buildMenuItem(context, Icons.history_outlined, '阅读记录', '每本书的阅读明细', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReadRecordScreen()))),
          _buildMenuItem(context, Icons.bar_chart_outlined, '阅读统计', '时长与趋势', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReadingStatsScreen()))),
          _buildMenuItem(context, Icons.cleaning_services_outlined, '缓存管理', '书籍缓存', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CacheManageScreen()))),
          _buildMenuItem(context, Icons.backup_outlined, '备份恢复', '数据备份', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BackupScreen()))),
          _buildMenuItem(context, Icons.folder_outlined, '文件管理', '本地文件', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FileManageScreen()))),
          _buildMenuItem(context, Icons.info_outline, '关于', '应用信息', () => _showAbout(context)),

          const Divider(),

          _buildSectionHeader('Web服务'),
          SwitchListTile(
            secondary: const Icon(Icons.web_outlined),
            title: const Text('Web服务'),
            subtitle: Text(_webServiceRunning ? '端口: ${_webService.port} (浏览器访问设备IP)' : '通过浏览器管理书架'),
            value: _webServiceRunning,
            onChanged: _toggleWebService,
          ),
          if (_webServiceRunning)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('在浏览器中打开上述地址即可管理书架、书源、RSS等', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ),

          const SizedBox(height: 24),
          Center(
            child:             Text(
              _versionLabel.isEmpty ? appDisplayName : '$appDisplayName v$_versionLabel',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Future<void> _checkUpdate() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('正在检查更新...')));
    try {
      // 当前版本用 package_info_plus 动态获取，不再写死
      final info = await PackageInfo.fromPlatform();
      final cur = _parseVersion(info.version);
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 15)));
      final resp = await dio.get(_kReleasesLatestApi);
      final tag = (resp.data['tag_name'] ?? '').toString();
      final body = (resp.data['body'] ?? '').toString();
      final htmlUrl = (resp.data['html_url'] ?? _kRepoUrl).toString();
      final latest = _parseVersion(tag);
      bool hasNew = false;
      for (var i = 0; i < 3; i++) {
        final l = i < latest.length ? latest[i] : 0;
        if (l > cur[i]) { hasNew = true; break; }
        if (l < cur[i]) break;
      }
      if (!mounted) return;
      if (hasNew) {
        showDialog(context: context, builder: (d) => AlertDialog(
          title: Text('发现新版本 $tag'),
          content: Text(body.isEmpty ? '是否前往下载最新版本？' : body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('稍后')),
            FilledButton(onPressed: () { Navigator.pop(d); launchUrl(Uri.parse(htmlUrl), mode: LaunchMode.externalApplication); }, child: const Text('前往下载')),
          ],
        ));
      } else {
        messenger.showSnackBar(const SnackBar(content: Text('当前已是最新版本')));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('检查更新失败: $e')));
    }
  }

  static List<int> _parseVersion(String v) => v
      .replaceAll(RegExp(r'[^0-9.]'), '')
      .split('.')
      .map((e) => int.tryParse(e) ?? 0)
      .toList();

  /// 内置更新日志（本项目已完成的主要功能）
  static const _changelog = <String>[
    '全新 Material 3 界面，书架支持列表/网格/封面流多种布局与封面样式配置',
    '书架分组管理：分组页签、折叠/平铺分组样式、待更新数量与批量移动分组',
    'URL 添加书籍：粘贴书籍链接自动匹配书源，抓取详情与目录后加入书架',
    '书架导入导出：JSON 格式导出/导入书架（含分组、书源、目录与阅读进度）',
    '书源管理：规则编辑、书源调试、导入导出、OPDS 书源与网络导入',
    '阅读引擎：JS 规则解析正文，支持替换净化、TXT 目录规则与正文朗读 TTS',
    '阅读体验：主题管理、阅读页精细设置、书签、书籍标记与章节缓存管理',
    '发现与 RSS：首页模块自定义、RSS 订阅源管理与文章阅读',
    '备份与同步：WebDAV 云同步、本地备份恢复与 WebDAV 远程书籍导入',
    '阅读统计：阅读时长/天数统计、连续阅读打卡与近 30 天阅读趋势图',
  ];

  void _showChangelog() {
    showDialog(context: context, builder: (context) => AlertDialog(
      title: const Text('更新日志'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < _changelog.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${i + 1}. ',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      Expanded(child: Text(_changelog[i])),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
      ],
    ));
  }

  /// 保存日志：读取崩溃日志并通过 share_plus 分享
  Future<void> _saveCrashLog() async {
    final logs = await CrashLogHelper.instance.readLogs();
    if (!mounted) return;
    if (logs.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('暂无崩溃日志')));
      return;
    }
    try {
      final file = File('${Directory.systemTemp.path}/crash_log.txt');
      await file.writeAsString(logs, flush: true);
      await Share.shareXFiles([XFile(file.path)], text: '$appDisplayName 崩溃日志');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存日志失败: $e')));
      }
    }
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

  void _showAbout(BuildContext context) {
    showDialog(context: context, builder: (context) => AlertDialog(
      title: const Text('关于'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(appDisplayName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('版本: ${_versionLabel.isEmpty ? '加载中...' : _versionLabel}'),
        const SizedBox(height: 4),
        const Text('基于 legado 的 Material Design 3 跨平台阅读应用，支持Android和iOS'),
        const Divider(height: 24),
        ListTile(
          dense: true, leading: const Icon(Icons.update, size: 20), title: const Text('检查更新'),
          onTap: () { Navigator.pop(context); _checkUpdate(); },
        ),
        ListTile(
          dense: true, leading: const Icon(Icons.history, size: 20), title: const Text('更新日志'),
          onTap: () { Navigator.pop(context); _showChangelog(); },
        ),
        ListTile(
          dense: true, leading: const Icon(Icons.code, size: 20), title: const Text('GitHub项目'),
          onTap: () { Navigator.pop(context); launchUrl(Uri.parse(_kRepoUrl), mode: LaunchMode.externalApplication); },
        ),
        ListTile(
          dense: true, leading: const Icon(Icons.people_outline, size: 20), title: const Text('贡献者'),
          onTap: () { Navigator.pop(context); showDialog(context: context, builder: (c) => const AlertDialog(title: Text('贡献者'), content: Text('Legado开源社区\n\n感谢所有贡献者的支持'))); },
        ),
        ListTile(
          dense: true, leading: const Icon(Icons.share, size: 20), title: const Text('分享应用'),
          onTap: () { Navigator.pop(context); _shareApp(); },
        ),
        ListTile(
          dense: true, leading: const Icon(Icons.star_outline, size: 20), title: const Text('评分'),
          onTap: () { Navigator.pop(context); _rateApp(); },
        ),
        ListTile(
          dense: true, leading: const Icon(Icons.privacy_tip_outlined, size: 20), title: const Text('隐私政策'),
          onTap: () { Navigator.pop(context); showDialog(context: context, builder: (c) => const AlertDialog(title: Text('隐私政策'), content: Text('本应用不会收集任何个人信息，所有数据均存储在本地设备上。'))); },
        ),
        ListTile(
          dense: true, leading: const Icon(Icons.gavel, size: 20), title: const Text('开源协议'),
          onTap: () { Navigator.pop(context); showDialog(context: context, builder: (c) => const AlertDialog(title: Text('开源协议'), content: Text('GNU General Public License v3.0'))); },
        ),
        ListTile(
          dense: true, leading: const Icon(Icons.warning_amber_outlined, size: 20), title: const Text('免责声明'),
          onTap: () { Navigator.pop(context); showDialog(context: context, builder: (c) => const AlertDialog(title: Text('免责声明'), content: Text('本应用仅供学习交流使用，不提供任何书籍内容，所有书源均由用户自行添加。'))); },
        ),
        ListTile(
          dense: true, leading: const Icon(Icons.save_alt, size: 20), title: const Text('保存日志'),
          onTap: () { Navigator.pop(context); _saveCrashLog(); },
        ),
        ListTile(
          dense: true, leading: const Icon(Icons.bug_report, size: 20), title: const Text('崩溃日志'),
          onTap: () { Navigator.pop(context); _showCrashLog(); },
        ),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
    ));
  }

  Future<void> _showCrashLog() async {
    final logs = await CrashLogHelper.instance.readLogs();
    if (!mounted) return;
    final cs = Theme.of(context).colorScheme;
    showDialog(context: context, builder: (c) => AlertDialog(
      title: const Text('崩溃日志'),
      content: SizedBox(
        width: double.maxFinite,
        child: logs.trim().isEmpty
            ? Text('暂无崩溃日志', style: TextStyle(color: cs.onSurfaceVariant))
            : SingleChildScrollView(child: SelectableText(logs, style: const TextStyle(fontSize: 11, fontFamily: 'monospace'))),
      ),
      actions: [
        if (logs.trim().isNotEmpty) TextButton(onPressed: () async { await CrashLogHelper.instance.clear(); if (mounted) { Navigator.pop(c); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已清空崩溃日志'))); } }, child: const Text('清空')),
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭')),
      ],
    ));
  }

  Widget _buildSectionHeader(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
  );

  Widget _buildMenuItem(BuildContext context, IconData icon, String title, String subtitle, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

/* ===== 由 lab_config_screen.dart 合并 ===== */

/// 实验室 - 对齐原版LabConfigScreen
class LabConfigScreen extends StatefulWidget {
  const LabConfigScreen({super.key});

  @override
  State<LabConfigScreen> createState() => _LabConfigScreenState();
}

class _LabConfigScreenState extends State<LabConfigScreen> {
  bool _labEnabled = false;
  bool _eink = false;
  bool _pageEstimateDiag = false;
  bool _textSelectable = false;
  bool _accelerateDownload = false;
  bool _webDavSyncOnOpen = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _labEnabled = p.getBool('lab_enabled') ?? false;
      _eink = p.getBool('lab_eink') ?? false;
      _pageEstimateDiag = p.getBool('lab_pageDiag') ?? false;
      _textSelectable = p.getBool('lab_selectable') ?? false;
      _accelerateDownload = p.getBool('lab_accDownload') ?? false;
      _webDavSyncOnOpen = p.getBool('lab_webdavOpen') ?? false;
    });
  }

  Future<void> _set(String k, bool v) async {
    (await SharedPreferences.getInstance()).setBool(k, v);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('实验室')),
      body: ListView(children: [
        SwitchListTile(
          secondary: const Icon(Icons.science_outlined),
          title: const Text('启用实验室功能'),
          subtitle: const Text('开启后可使用实验性功能，可能不稳定', style: TextStyle(fontSize: 11)),
          value: _labEnabled, onChanged: (v) { setState(() => _labEnabled = v); _set('lab_enabled', v); }),
        const Divider(),
        Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text('显示', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary))),
        SwitchListTile(dense: true, title: const Text('墨水屏(E-ink)显示优化'), subtitle: const Text('去除动画、提高对比度', style: TextStyle(fontSize: 11)),
          value: _eink, onChanged: _labEnabled ? (v) { setState(() => _eink = v); _set('lab_eink', v); } : null),
        SwitchListTile(dense: true, title: const Text('正文可自由选择复制'),
          value: _textSelectable, onChanged: _labEnabled ? (v) { setState(() => _textSelectable = v); _set('lab_selectable', v); } : null),
        Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text('诊断', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary))),
        SwitchListTile(dense: true, title: const Text('分页估算诊断'), subtitle: const Text('显示章节分页计算过程', style: TextStyle(fontSize: 11)),
          value: _pageEstimateDiag, onChanged: _labEnabled ? (v) { setState(() => _pageEstimateDiag = v); _set('lab_pageDiag', v); } : null),
        Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text('性能', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary))),
        SwitchListTile(dense: true, title: const Text('加速下载（多连接）'),
          value: _accelerateDownload, onChanged: _labEnabled ? (v) { setState(() => _accelerateDownload = v); _set('lab_accDownload', v); } : null),
        SwitchListTile(dense: true, title: const Text('打开应用时自动WebDAV同步'),
          value: _webDavSyncOnOpen, onChanged: _labEnabled ? (v) { setState(() => _webDavSyncOnOpen = v); _set('lab_webdavOpen', v); } : null),
        const SizedBox(height: 24),
        Center(child: Text('实验性功能可能随时变更或移除', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant))),
      ]),
    );
  }
}

