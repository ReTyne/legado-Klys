import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 漫画阅读配置 - 对齐原版ReadMangaConfig
class MangaConfigScreen extends StatefulWidget {
  const MangaConfigScreen({super.key});

  @override
  State<MangaConfigScreen> createState() => _MangaConfigScreenState();
}

class _MangaConfigScreenState extends State<MangaConfigScreen> {
  bool _showMangaUi = true;
  bool _disableScale = false;
  bool _disableScrollAnim = false;
  bool _disableCrossFade = false;
  int _scrollMode = 0; // 0 上下滚动(条漫) 1 左右翻页 2 双页
  int _preDownload = 3;
  int _autoPageSpeed = 5;
  bool _disableClickScroll = false;
  bool _hideTitle = false;
  bool _enableGray = false;
  bool _enableEInk = false;
  double _sidePadding = 0;
  bool _volumeKeyPage = false;
  bool _reverseVolumeKey = false;

  static const _scrollModes = ['条漫(上下滚动)', '左右翻页', '双页模式'];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _showMangaUi = p.getBool('manga_ui') ?? true;
      _disableScale = p.getBool('manga_noScale') ?? false;
      _disableScrollAnim = p.getBool('manga_noScrollAnim') ?? false;
      _disableCrossFade = p.getBool('manga_noCrossFade') ?? false;
      _scrollMode = p.getInt('manga_scrollMode') ?? 0;
      _preDownload = p.getInt('manga_preDownload') ?? 3;
      _autoPageSpeed = p.getInt('manga_autoSpeed') ?? 5;
      _disableClickScroll = p.getBool('manga_noClickScroll') ?? false;
      _hideTitle = p.getBool('manga_hideTitle') ?? false;
      _enableGray = p.getBool('manga_gray') ?? false;
      _enableEInk = p.getBool('manga_eink') ?? false;
      _sidePadding = p.getDouble('manga_sidePadding') ?? 0;
      _volumeKeyPage = p.getBool('manga_volumeKey') ?? false;
      _reverseVolumeKey = p.getBool('manga_reverseVolumeKey') ?? false;
    });
  }

  Future<void> _set(String k, dynamic v) async {
    final p = await SharedPreferences.getInstance();
    if (v is bool) await p.setBool(k, v);
    if (v is int) await p.setInt(k, v);
    if (v is double) await p.setDouble(k, v);
  }

  Widget _section(String t) => Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
    child: Text(t, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('漫画设置')),
      body: ListView(children: [
        _section('显示'),
        SwitchListTile(dense: true, title: const Text('显示漫画界面'), value: _showMangaUi, onChanged: (v) { setState(() => _showMangaUi = v); _set('manga_ui', v); }),
        SwitchListTile(dense: true, title: const Text('隐藏标题'), value: _hideTitle, onChanged: (v) { setState(() => _hideTitle = v); _set('manga_hideTitle', v); }),
        _section('阅读模式'),
        ListTile(dense: true, title: const Text('滚动模式'), trailing: DropdownButton<int>(
          value: _scrollMode, underline: const SizedBox(),
          items: List.generate(_scrollModes.length, (i) => DropdownMenuItem(value: i, child: Text(_scrollModes[i]))),
          onChanged: (v) { setState(() => _scrollMode = v ?? 0); _set('manga_scrollMode', v ?? 0); })),
        ListTile(dense: true, title: Text('预下载图片数: $_preDownload'),
          subtitle: Slider(value: _preDownload.toDouble(), min: 0, max: 10, divisions: 10, label: '$_preDownload',
            onChanged: (v) => setState(() => _preDownload = v.toInt()), onChangeEnd: (v) => _set('manga_preDownload', v.toInt()))),
        ListTile(dense: true, title: Text('自动翻页速度: $_autoPageSpeed 秒'),
          subtitle: Slider(value: _autoPageSpeed.toDouble(), min: 1, max: 30, divisions: 29, label: '$_autoPageSpeed',
            onChanged: (v) => setState(() => _autoPageSpeed = v.toInt()), onChangeEnd: (v) => _set('manga_autoSpeed', v.toInt()))),
        ListTile(dense: true, title: Text('条漫两侧边距: ${_sidePadding.toInt()}'),
          subtitle: Slider(value: _sidePadding, min: 0, max: 100, divisions: 20, label: '${_sidePadding.toInt()}',
            onChanged: (v) => setState(() => _sidePadding = v), onChangeEnd: (v) => _set('manga_sidePadding', v))),
        _section('手势与按键'),
        SwitchListTile(dense: true, title: const Text('禁用双指缩放'), value: _disableScale, onChanged: (v) { setState(() => _disableScale = v); _set('manga_noScale', v); }),
        SwitchListTile(dense: true, title: const Text('禁用点击滚动'), value: _disableClickScroll, onChanged: (v) { setState(() => _disableClickScroll = v); _set('manga_noClickScroll', v); }),
        SwitchListTile(dense: true, title: const Text('音量键翻页'), value: _volumeKeyPage, onChanged: (v) { setState(() => _volumeKeyPage = v); _set('manga_volumeKey', v); }),
        SwitchListTile(dense: true, title: const Text('音量键反向'), value: _reverseVolumeKey, onChanged: _volumeKeyPage ? (v) { setState(() => _reverseVolumeKey = v); _set("manga_reverseVolumeKey", v); } : null),
        _section('动画与画面'),
        SwitchListTile(dense: true, title: const Text('禁用滚动动画'), value: _disableScrollAnim, onChanged: (v) { setState(() => _disableScrollAnim = v); _set('manga_noScrollAnim', v); }),
        SwitchListTile(dense: true, title: const Text('禁用淡入淡出'), value: _disableCrossFade, onChanged: (v) { setState(() => _disableCrossFade = v); _set('manga_noCrossFade', v); }),
        SwitchListTile(dense: true, title: const Text('灰度模式'), subtitle: const Text('黑白显示，类似纸质漫画', style: TextStyle(fontSize: 11)), value: _enableGray, onChanged: (v) { setState(() => _enableGray = v); _set('manga_gray', v); }),
        SwitchListTile(dense: true, title: const Text('墨水屏优化'), value: _enableEInk, onChanged: (v) { setState(() => _enableEInk = v); _set('manga_eink', v); }),
        const SizedBox(height: 24),
      ]),
    );
  }
}
