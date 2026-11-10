import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:legado_md3/common/app_name.dart';
import 'package:legado_md3/constant/e_placement.dart';
import 'package:legado_md3/help/storage/crash_log_helper.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';

/// 本项目 GitHub 仓库
const _kRepoUrl = 'https://github.com/ReTyne/legado-Klys';

/// 最新 release 查询接口（GitHub API）
const _kReleasesLatestApi =
    'https://api.github.com/repos/ReTyne/legado-Klys/releases/latest';

/// 关于页（对齐 legado-E xml/about.xml：独立页面 9 项，非弹窗）。
/// 顶部为应用名 + 版本 + 简介；顶层 3 项 = [EPlacement.aboutTop]；
/// 分区「其它」6 项 = [EPlacement.aboutOtherCategory]，顺序严格按常量。
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        children: [
          // 顶部：应用名 + 版本 + 简介
          Padding(
            padding: const EdgeInsets.all(AppSpacing.l),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(appDisplayName,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: AppSpacing.s),
                Text('版本: ${_versionLabel.isEmpty ? '加载中...' : _versionLabel}'),
                const SizedBox(height: AppSpacing.xs),
                const Text(
                    '基于 legado 的 Material Design 3 跨平台阅读应用，支持Android和iOS'),
              ],
            ),
          ),
          const Divider(),
          // 顶层 3 项（贡献者 / 更新日志 / 检查更新）
          for (final e in EPlacement.aboutTop) _buildAboutTile(e),
          // 分区「其它」6 项
          _buildSectionHeader('其它'),
          for (final e in EPlacement.aboutOtherCategory) _buildAboutTile(e),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  Widget _buildAboutTile(EMenuItem e) {
    const icons = <String, IconData>{
      'contributors': Icons.people_outline,
      'update_log': Icons.history,
      'check_update': Icons.update,
      'crashLog': Icons.bug_report,
      'saveLog': Icons.save_alt,
      'createHeapDump': Icons.memory,
      'privacyPolicy': Icons.privacy_tip_outlined,
      'license': Icons.gavel,
      'disclaimer': Icons.warning_amber_outlined,
    };
    return ListTile(
      key: Key(e.key),
      leading: Icon(icons[e.id] ?? Icons.info_outline),
      title: Text(e.zh),
      onTap: () => _onItemTap(e.id),
    );
  }

  /// 各项按 [EMenuItem.id] 分发，顺序由常量列表决定，逻辑与旧弹窗等价。
  void _onItemTap(String id) {
    switch (id) {
      case 'contributors':
        _showInfoDialog('贡献者', 'Legado开源社区\n\n感谢所有贡献者的支持');
        break;
      case 'update_log':
        _showChangelog();
        break;
      case 'check_update':
        _checkUpdate();
        break;
      case 'crashLog':
        _showCrashLog();
        break;
      case 'saveLog':
        _saveCrashLog();
        break;
      case 'createHeapDump':
        _showHeapDumpUnsupported();
        break;
      case 'privacyPolicy':
        _showInfoDialog(
            '隐私政策', '本应用不会收集任何个人信息，所有数据均存储在本地设备上。');
        break;
      case 'license':
        _showInfoDialog('开源协议', 'GNU General Public License v3.0');
        break;
      case 'disclaimer':
        _showInfoDialog(
            '免责声明', '本应用仅供学习交流使用，不提供任何书籍内容，所有书源均由用户自行添加。');
        break;
    }
  }

  void _showInfoDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('关闭')),
        ],
      ),
    );
  }

  /// 对齐 [EPlacement.degradations] 的 'about.xml createHeapDump'：
  /// 创建堆栈转储（HeapDump）为 Android 专属能力，Flutter 无等价实现，
  /// 保留该项但显式标注平台降级、给出提示，不伪造功能。
  void _showHeapDumpUnsupported() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('当前平台不支持创建堆栈转储')),
    );
  }

  Widget _buildSectionHeader(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.l, AppSpacing.l, AppSpacing.l, AppSpacing.s),
        child: Text(title,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary)),
      );

  Future<void> _checkUpdate() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('正在检查更新...')));
    try {
      // 当前版本用 package_info_plus 动态获取，不再写死
      final info = await PackageInfo.fromPlatform();
      final cur = _parseVersion(info.version);
      final dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15)));
      final resp = await dio.get(_kReleasesLatestApi);
      final tag = (resp.data['tag_name'] ?? '').toString();
      final body = (resp.data['body'] ?? '').toString();
      final htmlUrl = (resp.data['html_url'] ?? _kRepoUrl).toString();
      final latest = _parseVersion(tag);
      bool hasNew = false;
      for (var i = 0; i < 3; i++) {
        final l = i < latest.length ? latest[i] : 0;
        if (l > cur[i]) {
          hasNew = true;
          break;
        }
        if (l < cur[i]) break;
      }
      if (!mounted) return;
      if (hasNew) {
        showDialog(
            context: context,
            builder: (d) => AlertDialog(
                  title: Text('发现新版本 $tag'),
                  content:
                      Text(body.isEmpty ? '是否前往下载最新版本？' : body),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(d),
                        child: const Text('稍后')),
                    FilledButton(
                        onPressed: () {
                          Navigator.pop(d);
                          launchUrl(Uri.parse(htmlUrl),
                              mode: LaunchMode.externalApplication);
                        },
                        child: const Text('前往下载')),
                  ],
                ));
      } else {
        messenger
            .showSnackBar(const SnackBar(content: Text('当前已是最新版本')));
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

  /// 内置更新日志 —— 对齐 legado-E：仅描述 E 具备的功能，
  /// 不再列 E 没有的入口（首页模块自定义 / 阅读统计 / 书籍标记）。
  static const _changelog = <String>[
    '全新 Material 3 界面，书架支持列表/网格/封面流多种布局与封面样式配置',
    '书架分组管理：分组页签、折叠/平铺分组样式、待更新数量与批量移动分组',
    'URL 添加书籍：粘贴书籍链接自动匹配书源，抓取详情与目录后加入书架',
    '书架导入导出：JSON 格式导出/导入书架（含分组、书源、目录与阅读进度）',
    '书源管理：规则编辑、书源调试、导入导出、OPDS 书源与网络导入',
    '阅读引擎：JS 规则解析正文，支持替换净化、TXT 目录规则与正文朗读 TTS',
    '阅读体验：主题管理、阅读页精细设置、书签与章节缓存管理',
    '发现与 RSS：书源分类发现、RSS 订阅源管理与文章阅读',
    '备份与同步：WebDAV 云同步、本地备份恢复与 WebDAV 远程书籍导入',
    '我的：书源/TXT目录/替换净化/词典规则、主题模式与 Web 服务设置',
  ];

  void _showChangelog() {
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
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
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              Expanded(child: Text(_changelog[i])),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('关闭')),
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
      await Share.shareXFiles(
          [XFile(file.path)], text: '$appDisplayName 崩溃日志');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存日志失败: $e')));
      }
    }
  }

  Future<void> _showCrashLog() async {
    final logs = await CrashLogHelper.instance.readLogs();
    if (!mounted) return;
    final cs = Theme.of(context).colorScheme;
    showDialog(
        context: context,
        builder: (c) => AlertDialog(
              title: const Text('崩溃日志'),
              content: SizedBox(
                width: double.maxFinite,
                child: logs.trim().isEmpty
                    ? Text('暂无崩溃日志',
                        style: TextStyle(color: cs.onSurfaceVariant))
                    : SingleChildScrollView(
                        child: SelectableText(logs,
                            style: const TextStyle(
                                fontSize: 11, fontFamily: 'monospace'))),
              ),
              actions: [
                if (logs.trim().isNotEmpty)
                  TextButton(
                      onPressed: () async {
                        await CrashLogHelper.instance.clear();
                        if (mounted && c.mounted && context.mounted) {
                          Navigator.pop(c);
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('已清空崩溃日志')));
                        }
                      },
                      child: const Text('清空')),
                TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: const Text('关闭')),
              ],
            ));
  }
}
