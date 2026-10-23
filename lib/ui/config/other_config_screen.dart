import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:legado_md3/help/config/app_config.dart';
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

  Widget _section(String t) => Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
    child: Text(t, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)));

  Widget _sw(String title, String key, String prefKey, {String? sub}) =>
    SwitchListTile(dense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      subtitle: sub != null ? Text(sub, style: const TextStyle(fontSize: 11)) : null,
      value: _prefs[key] ?? false, onChanged: (v) => _setBool(key, prefKey, v));

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
          sub: '移动网络下不请求网络封面（cover_onlyWifi）'),
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
        ListTile(dense: true, leading: const Icon(Icons.cleaning_services_outlined), title: const Text('清理WebView数据'),
          onTap: () async {
            try {
              await InAppWebViewController.clearAllCache();
              await CookieManager.instance().deleteAllCookies();
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('WebView数据已清理')));
            } catch (e) {
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('清理失败: $e')));
            }
          }),
        _sw('记录日志', 'recordLog', 'oc_recordLog'),
        SwitchListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          title: const Text('系统文本菜单入口', style: TextStyle(fontSize: 14)),
          subtitle: const Text('将本应用加入系统文本选择菜单（process_text）。Flutter 版暂不支持注册该入口，仅保存设置', style: TextStyle(fontSize: 11)),
          value: AppPrefs.processText,
          onChanged: (v) => setState(() => AppPrefs.processText = v),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          title: const Text('性能监测记录堆转储', style: TextStyle(fontSize: 14)),
          subtitle: const Text('开启性能监测时同时记录堆转储，便于分析内存占用（recordHeapDump）', style: TextStyle(fontSize: 11)),
          value: AppPrefs.recordHeapDump,
          onChanged: (v) => setState(() => AppPrefs.recordHeapDump = v),
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
}
