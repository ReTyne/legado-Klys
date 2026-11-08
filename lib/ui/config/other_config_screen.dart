import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/help/config/app_config.dart';
import 'package:legado_md3/help/device/native_bridge.dart';
import 'package:legado_md3/help/storage/download_service.dart';
import 'package:legado_md3/help/storage/import_old_data.dart';
import 'package:legado_md3/ui/config/direct_link_upload_config.dart';
import 'package:legado_md3/ui/config/video_setting_screen.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 其他设置 - 对齐原版OtherConfigScreen
///
/// 存储约定：开关类统一使用 oc_ 前缀，与原版预置项对齐的键沿用原版命名
/// （例如 updateToVariant / mediaButtonOnExit / loadCoverOnlyWifi）。
class OtherConfigScreen extends StatefulWidget {
  const OtherConfigScreen({super.key});

  @override
  State<OtherConfigScreen> createState() => _OtherConfigScreenState();
}

class _OtherConfigScreenState extends State<OtherConfigScreen> {
  final Map<String, dynamic> _prefs = {};

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    // 全局持久化配置加载进 AppPrefs 内存（静态 getter 同步读取）
    AppPrefs.loadFrom(p);
    setState(() {
      _prefs['autoCheckUpdate'] = p.getBool('oc_autoCheckUpdate') ?? true;
      _prefs['webAutoStart'] = p.getBool('oc_webAutoStart') ?? false;
      _prefs['autoRefresh'] = p.getBool('oc_autoRefresh') ?? false;
      _prefs['defaultRead'] = p.getBool('oc_defaultRead') ?? false;
      _prefs['antiAlias'] = p.getBool('oc_antiAlias') ?? true;
      _prefs['replaceDefault'] = p.getBool('oc_replaceDefault') ?? true;
      _prefs['autoClearExpired'] = p.getBool('oc_autoClearExpired') ?? false;
      _prefs['showAddShelfTip'] = p.getBool('oc_showAddShelfTip') ?? true;
      _prefs['showMangaUi'] = p.getBool('oc_showMangaUi') ?? true;
      _prefs['webWakeLock'] = p.getBool('oc_webWakeLock') ?? false;
      _prefs['recordLog'] = p.getBool('oc_recordLog') ?? false;
      _prefs['sourceEditMaxLine'] = p.getInt('oc_sourceEditMaxLine') ?? 10;
      _prefs['webPort'] = p.getInt('oc_webPort') ?? 1122;
      _prefs['language'] = p.getInt('oc_language') ?? 0;
      // ===== 补齐项 =====
      // 本地密码统一使用 oc_password（main.dart 按非空判断），原 oc_localPassword 布尔键无消费方已移除
      _prefs['loadCoverOnlyWifi'] = p.getBool('cover_onlyWifi') ?? false;
      _prefs['mediaButtonOnExit'] = p.getBool('mediaButtonOnExit') ?? true;
      _prefs['readAloudByMediaButton'] = p.getBool('readAloudByMediaButton') ?? false;
      _prefs['ignoreAudioFocus'] = p.getBool('ignoreAudioFocus') ?? false;
      _prefs['updateToVariant'] = p.getString('updateToVariant') ?? 'default_version';
      // 图片保留数量：DownloadService 写缓存 LRU 读取同一个键
      _prefs['imageRetainNum'] = p.getInt(DownloadService.keyImageRetainNum) ?? 0;
    });
  }

  Future<void> _setBool(String key, String prefKey, bool v) async {
    setState(() => _prefs[key] = v);
    final p = await SharedPreferences.getInstance();
    await p.setBool(prefKey, v);
  }

  Future<void> _setString(String key, String prefKey, String v) async {
    setState(() => _prefs[key] = v);
    final p = await SharedPreferences.getInstance();
    await p.setString(prefKey, v);
  }

  Widget _section(String t) => AppSectionHeader(t);

  Widget _sw(String title, String key, String prefKey, {String? sub}) =>
    AppSwitchTile(
      title: title,
      subtitle: sub,
      value: _prefs[key] ?? false,
      onChanged: (v) => _setBool(key, prefKey, v),
    );

  /// 基于 AppPrefs 静态配置的滑条（写入即经 AppPrefs setter 落盘）
  Widget _appSlider(String title, int value, double min, double max, int divisions,
      ValueChanged<double> onChanged, {String? sub}) {
    return ListTile(
      dense: true,
      title: Text('$title: $value'),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (sub != null) Text(sub, style: const TextStyle(fontSize: 11)),
        Slider(
          value: value.clamp(min, max).toDouble(),
          min: min, max: max, divisions: divisions,
          label: '$value',
          onChanged: onChanged,
        ),
      ]),
    );
  }

  /// 文本输入弹窗，返回 null 表示取消
  Future<String?> _textDialog({
    required String title,
    required String initial,
    String? hint,
    int maxLines = 1,
  }) async {
    final ctl = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctl, maxLines: maxLines, decoration: InputDecoration(hintText: hint)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, ctl.text), child: const Text('保存')),
        ],
      ),
    );
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('其他设置')),
      body: ListView(children: [
        _section('常规'),
        ListTile(dense: true, title: const Text('语言'), trailing: DropdownButton<int>(
          value: _prefs['language'] ?? 0, underline: const SizedBox(),
          items: const [DropdownMenuItem(value: 0, child: Text('跟随系统')), DropdownMenuItem(value: 1, child: Text('简体中文')), DropdownMenuItem(value: 2, child: Text('English'))],
          onChanged: (v) async { setState(() => _prefs['language'] = v); (await SharedPreferences.getInstance()).setInt('oc_language', v ?? 0); })),
        _sw('启动时自动检查更新', 'autoCheckUpdate', 'oc_autoCheckUpdate'),
        ListTile(
          dense: true,
          title: const Text('更新通道'),
          subtitle: Text(_variantName('${_prefs['updateToVariant']}'), style: const TextStyle(fontSize: 11)),
          trailing: DropdownButton<String>(
            value: _prefs['updateToVariant'] as String? ?? 'default_version',
            underline: const SizedBox(),
            items: const [
              DropdownMenuItem(value: 'default_version', child: Text('正式版')),
              DropdownMenuItem(value: 'beta_version', child: Text('测试版')),
              DropdownMenuItem(value: 'none', child: Text('不检查')),
            ],
            onChanged: (v) => _setString('updateToVariant', 'updateToVariant', v ?? 'default_version'),
          ),
        ),
        _sw('Web服务自动启动', 'webAutoStart', 'oc_webAutoStart'),
        _section('主界面'),
        _sw('进入自动刷新', 'autoRefresh', 'oc_autoRefresh'),
        _sw('默认直接打开阅读', 'defaultRead', 'oc_defaultRead', sub: '点击书架书籍直接进入阅读而非详情'),
        _section('隐私与安全'),
        ListTile(dense: true, title: const Text('设置本地密码'), trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            final v = await _textDialog(
              title: '本地密码',
              initial: '',
              hint: '输入启动密码（留空清除）',
            );
            if (v == null) return;
            final p = await SharedPreferences.getInstance();
            await p.setString('oc_password', v);
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(v.isEmpty ? '已清除本地密码' : '本地密码已保存')),
            );
          }),
        _section('网络和封面'),
        _sw('仅WiFi下加载封面', 'loadCoverOnlyWifi', 'cover_onlyWifi',
          sub: '移动数据下不加载网络封面（cover_onlyWifi，Android 原生判断）'),
        _section('网络与存储（对照原版）'),
        ListTile(
          dense: true,
          title: const Text('全局 User-Agent'),
          subtitle: Text(
            AppPrefs.userAgent == AppConstants.defaultUserAgent ? '未设置，使用默认 UA' : AppPrefs.userAgent,
            maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
          trailing: const Icon(Icons.edit),
          onTap: () async {
            final v = await _textDialog(
              title: '全局 User-Agent',
              initial: AppPrefs.userAgent == AppConstants.defaultUserAgent ? '' : AppPrefs.userAgent,
              hint: '留空使用默认 UA',
              maxLines: 3,
            );
            if (v == null) return;
            setState(() => AppPrefs.userAgent = v);
          },
        ),
        ListTile(
          dense: true,
          title: const Text('自定义 Host 映射'),
          subtitle: Text(
            AppPrefs.customHosts.isEmpty ? '未设置' : AppPrefs.customHosts,
            maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
          trailing: const Icon(Icons.edit),
          onTap: () async {
            final v = await _textDialog(
              title: '自定义 Host 映射',
              initial: AppPrefs.customHosts,
              hint: '每行一条：host=ip',
              maxLines: 5,
            );
            if (v == null) return;
            setState(() => AppPrefs.customHosts = v);
          },
        ),
        ListTile(
          dense: true,
          title: const Text('默认书籍保存目录'),
          subtitle: Text(
            AppPrefs.defaultBookTreeUri.isEmpty ? '未设置，使用应用默认目录' : AppPrefs.defaultBookTreeUri,
            maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
          trailing: const Icon(Icons.edit),
          onTap: _pickBookTreeUri,
        ),
        ListTile(dense: true, leading: const Icon(Icons.cloud_upload_outlined), title: const Text('上传规则'),
          subtitle: const Text('书籍/备份分享到网盘的直链上传规则（uploadRule）', style: TextStyle(fontSize: 11)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => DirectLinkUploadConfigDialog.show(context)),
        _appSlider('并发线程数', AppPrefs.threadCount, 1, 128, 127,
          (v) => setState(() => AppPrefs.threadCount = v.toInt()),
          sub: '搜索/目录/正文的并发上限（threadCount）'),
        _appSlider('预下载章节数', AppPrefs.preDownloadNum, 0, 10, 10,
          (v) => setState(() => AppPrefs.preDownloadNum = v.toInt()),
          sub: AppPrefs.preDownloadNum == 0 ? '不预下载' : '后台提前缓存后续 ${AppPrefs.preDownloadNum} 章'),
        _appSlider('图片缓存大小', AppPrefs.bitmapCacheSize, 10, 510, 50,
          (v) => setState(() => AppPrefs.bitmapCacheSize = v.toInt()),
          sub: '封面/插图内存缓存上限（MB）'),
        _section('朗读'),
        _sw('媒体键控制朗读', 'readAloudByMediaButton', 'readAloudByMediaButton',
          sub: '使用耳机/蓝牙媒体键开始或暂停朗读'),
        _sw('退出时停止朗读', 'mediaButtonOnExit', 'mediaButtonOnExit',
          sub: '离开应用时自动结束朗读'),
        _sw('忽略音频焦点', 'ignoreAudioFocus', 'ignoreAudioFocus',
          sub: '朗读时不打断其他正在播放的声音'),
        _section('阅读'),
        _sw('文字抗锯齿', 'antiAlias', 'oc_antiAlias'),
        _sw('替换净化默认启用', 'replaceDefault', 'oc_replaceDefault'),
        _sw('自动清理过期内容', 'autoClearExpired', 'oc_autoClearExpired'),
        _sw('显示加入书架提示', 'showAddShelfTip', 'oc_showAddShelfTip'),
        _sw('显示漫画界面', 'showMangaUi', 'oc_showMangaUi'),
        _section('缓存与维护（对照 pref_config_other）'),
        ListTile(
          dense: true,
          leading: const Icon(Icons.image_outlined),
          title: Text('图片/正文缓存保留章节数: ${_prefs['imageRetainNum'] ?? 0}'),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text(
              'imageRetainNum：写缓存时 DownloadService 自动 LRU 按条目清理，0 = 不限条目',
              style: TextStyle(fontSize: 11)),
            Slider(
              value: (_prefs['imageRetainNum'] ?? 0).clamp(0, 200).toDouble(),
              min: 0, max: 200, divisions: 20,
              label: '${_prefs['imageRetainNum'] ?? 0}',
              onChanged: (v) => setState(() => _prefs['imageRetainNum'] = v.toInt()),
              onChangeEnd: (v) async {
                final p = await SharedPreferences.getInstance();
                await p.setInt(DownloadService.keyImageRetainNum, v.toInt());
              },
            ),
          ]),
        ),
        ListTile(
          dense: true,
          leading: const Icon(Icons.compress_outlined),
          title: const Text('压缩数据库'),
          subtitle: const Text('shrinkDatabase：执行 VACUUM 回收已删除数据占用的空间',
              style: TextStyle(fontSize: 11)),
          trailing: const Icon(Icons.chevron_right),
          onTap: _shrinkDatabase,
        ),
        ListTile(
          dense: true,
          leading: const Icon(Icons.video_settings_outlined),
          title: const Text('视频播放器设置'),
          subtitle: const Text('videoSetting：自动播放 / 直接全屏 / 长按倍速 / 底部进度条',
              style: TextStyle(fontSize: 11)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const VideoSettingScreen())),
        ),
        _section('其他'),
        _sw('Web服务唤醒锁', 'webWakeLock', 'oc_webWakeLock'),
        ListTile(dense: true, title: Text('源编辑文本最大行数: ${_prefs['sourceEditMaxLine']}'),
          subtitle: Slider(value: (_prefs['sourceEditMaxLine'] ?? 10).toDouble(), min: 3, max: 30, divisions: 27,
            onChanged: (v) => setState(() => _prefs['sourceEditMaxLine'] = v.toInt()),
            onChangeEnd: (v) async => (await SharedPreferences.getInstance()).setInt('oc_sourceEditMaxLine', v.toInt()))),
        ListTile(dense: true, title: Text('Web服务端口: ${_prefs['webPort']}'),
          onTap: () async {
            final v = await _textDialog(
              title: 'Web端口',
              initial: '${_prefs['webPort']}',
              hint: '1024-65535',
            );
            if (v == null) return;
            final port = int.tryParse(v) ?? 1122;
            setState(() => _prefs['webPort'] = port);
            await (await SharedPreferences.getInstance()).setInt('oc_webPort', port);
          }),
        ListTile(dense: true, leading: const Icon(Icons.history), title: const Text('导入旧版数据'),
          subtitle: const Text('导入 legado 3.x 旧版导出的书架/书源/替换规则（选择含 myBookShelf.json 等的目录）', style: TextStyle(fontSize: 11)),
          trailing: const Icon(Icons.chevron_right),
          onTap: _importOldData),
        ListTile(dense: true,
          leading: const Icon(Icons.cleaning_services_outlined),
          title: const Text('清理WebView数据'),
          subtitle: const Text('clearWebViewData：缓存 / Cookie / Web Storage',
              style: TextStyle(fontSize: 11)),
          trailing: const Icon(Icons.chevron_right),
          onTap: _clearWebViewData),
        _sw('记录日志', 'recordLog', 'oc_recordLog'),
        // 下线说明：process_text（系统文本菜单入口）与 recordHeapDump（堆转储）
        // 在 AppPrefs 中仅持久化、全库无消费方，属记账式死开关，已从本页下架。
        // 原生 ACTION_PROCESS_TEXT 由 N 组在 Manifest 无条件注册，能力本身不受 Dart
        // 布尔开关影响；残留字段 AppPrefs.processText / AppPrefs.recordHeapDump
        // 建议主代理从 app_config.dart 清理（见交付报告「已删除字段清单」）。
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(
            '说明：系统文本菜单入口（PROCESS_TEXT）由原生层统一注册，无需应用内开关；'
            '堆转储记录无对应采集链路。两项记账式开关已从本页下架，避免留下无效开关。',
            style: TextStyle(
                fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 24),
      ]),
    );
  }

  String _variantName(String v) {
    switch (v) {
      case 'beta_version':
        return '测试版（含未发布特性）';
      case 'none':
        return '不检查更新';
      default:
        return '正式版';
    }
  }

  void _tip(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// defaultBookTreeUri：优先走 SAF（原生 ACTION_OPEN_DOCUMENT_TREE）真实授权目录，
  /// 不支持 SAF 的平台可手动输入路径或清除。
  Future<void> _pickBookTreeUri() async {
    await showAppMenuSheet(
      context,
      title: '默认书籍保存目录',
      items: [
        AppMenuSheetItem(
          title: '通过系统文件选择器授权目录',
          icon: Icons.folder_open_outlined,
          subtitle: 'SAF content URI（推荐）',
          onTap: () async {
            final uri = await NativeBridge.instance.pickDocumentTree();
            if (uri == null || uri.isEmpty) {
              _tip('未选择目录，或当前平台不支持 SAF');
              return;
            }
            setState(() => AppPrefs.defaultBookTreeUri = uri);
            _tip('已设置默认书籍目录：$uri');
          },
        ),
        AppMenuSheetItem(
          title: '手动输入路径',
          icon: Icons.edit_outlined,
          onTap: () async {
            final v = await _textDialog(
              title: '默认书籍保存目录',
              initial: AppPrefs.defaultBookTreeUri,
              hint: '本地书籍默认保存/导入目录',
            );
            if (v == null) return;
            setState(() => AppPrefs.defaultBookTreeUri = v);
          },
        ),
        AppMenuSheetItem(
          title: '清除（使用应用默认目录）',
          icon: Icons.delete_outline,
          onTap: () => setState(() => AppPrefs.defaultBookTreeUri = ''),
        ),
      ],
    );
  }

  /// shrinkDatabase：真实执行 VACUUM 重整数据库文件。
  Future<void> _shrinkDatabase() async {
    final ok = await showAppConfirmDialog(
      context,
      title: '压缩数据库',
      content: '将执行 VACUUM 回收已删除数据占用的空闲页，过程中请勿退出应用。',
      confirmText: '压缩',
    );
    if (!ok || !mounted) return;
    try {
      await runWithBusyDialog<void>(
        context,
        message: '正在压缩数据库…',
        task: DatabaseService().shrinkDatabase(),
      );
      if (!mounted) return;
      _tip('数据库已压缩（VACUUM 完成）');
    } catch (e) {
      _tip('压缩失败：$e');
    }
  }

  /// clearWebViewData：清 WebView 缓存 + Cookie + Web Storage（三项真实生效）。
  Future<void> _clearWebViewData() async {
    final ok = await showAppConfirmDialog(
      context,
      title: '清理 WebView 数据',
      content: '将清除网页缓存、Cookie 与 Web Storage（localStorage / IndexedDB）。'
          '已登录的书源 / RSS 站点可能需要重新登录。',
      confirmText: '清理',
      danger: true,
    );
    if (!ok) return;
    var cleared = 0;
    try {
      await InAppWebViewController.clearAllCache();
      cleared++;
    } catch (_) {}
    try {
      await CookieManager.instance().deleteAllCookies();
      cleared++;
    } catch (_) {}
    try {
      await WebStorageManager.instance().deleteAllData();
      cleared++;
    } catch (_) {}
    _tip('WebView 数据已清理（完成 $cleared/3 项：缓存 / Cookie / Web Storage）');
  }

  /// 导入 legado 3.x 旧版数据（E: ImportOldData.importUri）
  Future<void> _importOldData() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null || !mounted) return;
    String summary;
    try {
      final result = await runWithBusyDialog(
        context,
        message: '正在导入旧版数据...',
        task: ImportOldData.importDir(dir),
      );
      summary = result.summary();
    } catch (e) {
      summary = '导入失败: $e';
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(summary)));
  }
}
