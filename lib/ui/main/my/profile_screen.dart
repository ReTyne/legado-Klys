import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:legado_md3/help/web/web_service.dart';
import 'package:legado_md3/ui/book/source/source_manage_screen.dart';
import 'package:legado_md3/ui/config/replace_rule_screen.dart';
import 'package:legado_md3/ui/config/txt_toc_rule_screen.dart';
import 'package:legado_md3/ui/config/dict_rule_screen.dart';
import 'package:legado_md3/ui/config/highlight_tag_rule_screen.dart';
import 'package:legado_md3/ui/config/settings_screen.dart';
import 'package:legado_md3/ui/bookmark/bookmark_screen.dart';
import 'package:legado_md3/ui/stats/reading_stats_screen.dart';
import 'package:legado_md3/ui/cache/cache_manage_screen.dart';
import 'package:legado_md3/ui/backup/backup_screen.dart';
import 'package:legado_md3/ui/main/homepage/homepage_manage_screen.dart';
import 'package:legado_md3/ui/config/theme_manage_screen.dart';
import 'package:legado_md3/ui/config/cloud_tts_screen.dart';
import 'package:legado_md3/ui/config/translation_screen.dart';
import 'package:legado_md3/ui/config/tag_group_rule_screen.dart';
import 'package:legado_md3/ui/rss/rule_subscription_screen.dart';
import 'package:legado_md3/ui/file/file_manage_screen.dart';
import 'package:legado_md3/ui/bookmark/book_marking_screen.dart';
import 'package:legado_md3/ui/config/lab_config_screen.dart';
import 'package:legado_md3/ui/main/subscribe/subscribe_screen.dart';
import 'package:legado_md3/help/storage/crash_log_helper.dart';
import 'package:legado_md3/help/config/app_config.dart';
import 'package:legado_md3/ui/ai/ai_chat_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final WebService _webService = WebService();
  bool _webServiceRunning = false;

  @override
  void dispose() {
    _webService.stop();
    super.dispose();
  }

  Future<void> _toggleWebService(bool value) async {
    if (value) {
      await _webService.start(port: 1122);
      setState(() => _webServiceRunning = true);
      if (mounted) {
        final addr = await _webService.address;
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Web服务已启动: $addr')));
      }
    } else {
      await _webService.stop();
      setState(() => _webServiceRunning = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Web服务已停止')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        children: [
          _buildSectionHeader('规则分段'),
          _buildMenuItem(context, Icons.menu_book_outlined, '书源管理', '管理网络书源', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SourceManageScreen()))),
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
          _buildMenuItem(context, Icons.download_outlined, '下载管理', '管理下载任务', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CacheManageScreen()))),
          _buildMenuItem(context, Icons.palette_outlined, '主题管理', '自定义主题', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ThemeManageScreen()))),
          _buildMenuItem(context, Icons.record_voice_over_outlined, 'TTS设置', '朗读引擎设置', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CloudTtsScreen()))),
          _buildMenuItem(context, Icons.translate_outlined, '翻译设置', '翻译引擎配置', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TranslationScreen()))),
          _buildMenuItem(context, Icons.science_outlined, '实验室', '实验性功能', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LabConfigScreen()))),
          _buildMenuItem(context, Icons.flag_outlined, '书籍标记', '标记管理', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BookMarkingScreen(bookName: '', author: '')))),
          _buildMenuItem(context, Icons.settings_outlined, '设置', '应用设置', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()))),
          _buildMenuItem(context, Icons.bookmark_border, '书签', '所有书签', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BookmarkScreen()))),
          _buildMenuItem(context, Icons.bar_chart_outlined, '阅读记录', '阅读统计', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReadingStatsScreen()))),
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
              child: Text('在浏览器中打开上述地址即可管理书架、书源、RSS等', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ),

          const SizedBox(height: 24),
          const Center(child: Text('Legado MD3 v3.30.0', style: TextStyle(color: Colors.grey, fontSize: 12))),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Future<void> _checkUpdate() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('正在检查更新...')));
    try {
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 15)));
      final resp = await dio.get('https://api.github.com/repos/stwy0716/legado-K/releases/latest');
      final tag = (resp.data['tag_name'] ?? '').toString();
      final body = (resp.data['body'] ?? '').toString();
      final htmlUrl = (resp.data['html_url'] ?? 'https://github.com/stwy0716/legado-K/releases').toString();
      final latest = tag.replaceAll(RegExp(r'[^0-9.]'), '').split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final cur = [3, 29, 0];
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

  void _showAbout(BuildContext context) {
    showDialog(context: context, builder: (context) => AlertDialog(
      title: const Text('关于'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Legado MD3', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('版本: 3.30.0'),
        const SizedBox(height: 4),
        const Text('基于Legado MD3风格的跨平台阅读应用，支持Android和iOS'),
        const Divider(height: 24),
        ListTile(
          dense: true, leading: const Icon(Icons.update, size: 20), title: const Text('检查更新'),
          onTap: () { Navigator.pop(context); _checkUpdate(); },
        ),
        ListTile(
          dense: true, leading: const Icon(Icons.code, size: 20), title: const Text('GitHub项目'),
          onTap: () { Navigator.pop(context); launchUrl(Uri.parse('https://github.com/stwy0716/legado-K'), mode: LaunchMode.externalApplication); },
        ),
        ListTile(
          dense: true, leading: const Icon(Icons.people_outline, size: 20), title: const Text('贡献者'),
          onTap: () { Navigator.pop(context); showDialog(context: context, builder: (c) => const AlertDialog(title: Text('贡献者'), content: Text('Legado开源社区\n\n感谢所有贡献者的支持'))); },
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
    showDialog(context: context, builder: (c) => AlertDialog(
      title: const Text('崩溃日志'),
      content: SizedBox(
        width: double.maxFinite,
        child: logs.trim().isEmpty
            ? const Text('暂无崩溃日志', style: TextStyle(color: Colors.grey))
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
