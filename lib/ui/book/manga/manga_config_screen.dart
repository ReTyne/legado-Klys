import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:legado_md3/help/translate/manga_translate_overlay.dart';
import 'package:legado_md3/ui/book/reader_router.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';

/// 漫画阅读配置 - 对齐原版 ReadMangaConfig / Sigma MangaColorFilterConfig。
///
/// Sigma 漫画专属 10 键（全部由 manga_reader_screen 真实消费）：
/// 1 manga_gray 灰阶  2 manga_threshold 二值化阈值  3 manga_colorFilter 色彩滤镜
/// 4 manga_noScale 禁用缩放  5 manga_scaleMax 最大缩放  6 manga_pageAnim 翻页动画
/// 7 manga_noCrossFade 禁用淡入淡出  8 manga_preDownload 预下载
/// 9 manga_scrollMode 双页并排  10 manga_autoSpeed 自动翻页速度
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

  // Sigma 漫画专属补充键
  int _threshold = 128;   // manga_threshold 二值化阈值 0~255
  int _colorFilter = 0;   // manga_colorFilter 0 无 / 1 护眼 / 2 复古 / 3 冷色
  int _scaleMax = 4;      // manga_scaleMax 最大缩放倍数 2~8
  int _pageAnim = 0;      // manga_pageAnim 0 滑动 / 1 淡入 / 2 瞬切
  bool _aiTranslate = false;

  static const _scrollModes = ['条漫(上下滚动)', '左右翻页', '双页模式'];
  static const _colorFilters = ['无', '护眼', '复古', '冷色'];
  static const _pageAnims = ['滑动翻页', '淡入淡出', '瞬切(无动画)'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      // 与 other_config / reader_router 共用同一键，兼容历史 manga_ui。
      _showMangaUi = p.getBool('oc_showMangaUi') ?? p.getBool('manga_ui') ?? true;
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
      _threshold = p.getInt('manga_threshold') ?? 128;
      _colorFilter = p.getInt('manga_colorFilter') ?? 0;
      _scaleMax = p.getInt('manga_scaleMax') ?? 4;
      _pageAnim = p.getInt('manga_pageAnim') ?? 0;
      _aiTranslate = p.getBool(MangaTranslateStore.kEnabled) ?? false;
    });
  }

  Future<void> _set(String k, dynamic v) async {
    final p = await SharedPreferences.getInstance();
    if (v is bool) await p.setBool(k, v);
    if (v is int) await p.setInt(k, v);
    if (v is double) await p.setDouble(k, v);
    if (v is String) await p.setString(k, v);
  }

  Widget _section(String t) => AppSectionHeader(t);

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 编辑「按书源翻译规则替换图内文字」的 OCR 框 / 原文配置（JSON 数组）。
  Future<void> _editTranslateRules() async {
    final ctl = TextEditingController();
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    ctl.text = p.getString(MangaTranslateStore.rulesKey('')) ??
        MangaTranslateStore.sampleRules;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('图内文字替换规则'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text(
              'JSON 数组：每项为一个文字框（归一化坐标 0~1）与框内原文；'
              '阅读时经翻译服务译成中文后覆盖原图。也可直接粘贴 OCR 结果。',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: AppSpacing.s),
            TextField(
              controller: ctl,
              maxLines: 12,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
                hintText: '[{"x":0.05,"y":0.05,"w":0.4,"h":0.1,"text":"..."}]',
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true), child: const Text('保存')),
        ],
      ),
    );
    if (ok == true) {
      try {
        await MangaTranslateStore.instance.saveRules('', ctl.text.trim());
        final rules = await MangaTranslateStore.instance.loadRules('');
        _toast('已保存 ${rules.length} 个文字框');
      } catch (e) {
        _toast('规则格式错误：$e');
      }
    }
    ctl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('漫画设置')),
      body: ListView(children: [
        _section('显示'),
        SwitchListTile(dense: true, title: const Text('显示漫画界面'), value: _showMangaUi, onChanged: (v) { setState(() => _showMangaUi = v); _set('oc_showMangaUi', v); showMangaUi = v; }),
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
        _section('画面滤镜（灰阶 / 阈值 / 色彩）'),
        SwitchListTile(dense: true, title: const Text('灰度模式'), subtitle: const Text('黑白显示，类似纸质漫画', style: TextStyle(fontSize: 11)), value: _enableGray, onChanged: (v) { setState(() => _enableGray = v); _set('manga_gray', v); }),
        SwitchListTile(dense: true, title: const Text('墨水屏优化'), value: _enableEInk, onChanged: (v) { setState(() => _enableEInk = v); _set('manga_eink', v); }),
        ListTile(dense: true, title: Text('二值化阈值: $_threshold'),
          subtitle: Slider(value: _threshold.toDouble(), min: 0, max: 255, divisions: 51, label: '$_threshold',
            onChanged: (v) => setState(() => _threshold = v.toInt()), onChangeEnd: (v) => _set('manga_threshold', v.toInt()))),
        ListTile(dense: true, title: const Text('色彩滤镜'), trailing: DropdownButton<int>(
          value: _colorFilter, underline: const SizedBox(),
          items: List.generate(_colorFilters.length, (i) => DropdownMenuItem(value: i, child: Text(_colorFilters[i]))),
          onChanged: (v) { setState(() => _colorFilter = v ?? 0); _set('manga_colorFilter', v ?? 0); })),
        _section('缩放与翻页动画'),
        SwitchListTile(dense: true, title: const Text('禁用双指缩放'), value: _disableScale, onChanged: (v) { setState(() => _disableScale = v); _set('manga_noScale', v); }),
        ListTile(dense: true, title: Text('最大缩放倍数: ${_scaleMax}x'),
          subtitle: Slider(value: _scaleMax.toDouble(), min: 2, max: 8, divisions: 6, label: '${_scaleMax}x',
            onChanged: (v) => setState(() => _scaleMax = v.toInt()), onChangeEnd: (v) => _set('manga_scaleMax', v.toInt()))),
        ListTile(dense: true, title: const Text('翻页动画'), trailing: DropdownButton<int>(
          value: _pageAnim, underline: const SizedBox(),
          items: List.generate(_pageAnims.length, (i) => DropdownMenuItem(value: i, child: Text(_pageAnims[i]))),
          onChanged: (v) { setState(() => _pageAnim = v ?? 0); _set('manga_pageAnim', v ?? 0); })),
        SwitchListTile(dense: true, title: const Text('禁用淡入淡出'), value: _disableCrossFade, onChanged: (v) { setState(() => _disableCrossFade = v); _set('manga_noCrossFade', v); }),
        SwitchListTile(dense: true, title: const Text('禁用滚动动画'), value: _disableScrollAnim, onChanged: (v) { setState(() => _disableScrollAnim = v); _set('manga_noScrollAnim', v); }),
        _section('手势与按键'),
        SwitchListTile(dense: true, title: const Text('禁用点击滚动'), value: _disableClickScroll, onChanged: (v) { setState(() => _disableClickScroll = v); _set('manga_noClickScroll', v); }),
        SwitchListTile(dense: true, title: const Text('音量键翻页'), value: _volumeKeyPage, onChanged: (v) { setState(() => _volumeKeyPage = v); _set('manga_volumeKey', v); }),
        SwitchListTile(dense: true, title: const Text('音量键反向'), value: _reverseVolumeKey, onChanged: _volumeKeyPage ? (v) { setState(() => _reverseVolumeKey = v); _set("manga_reverseVolumeKey", v); } : null),
        _section('AI 翻译（图内文字替换）'),
        SwitchListTile(
          dense: true,
          title: const Text('启用漫画 AI 翻译'),
          subtitle: const Text('按翻译规则把图内文字框替换为译文（接翻译服务）', style: TextStyle(fontSize: 11)),
          value: _aiTranslate,
          onChanged: (v) {
            setState(() => _aiTranslate = v);
            MangaTranslateStore.instance.setEnabled(v);
          },
        ),
        ListTile(
          dense: true,
          title: const Text('编辑图内文字替换规则'),
          subtitle: const Text('OCR 结果框 / 原文配置（JSON 数组）', style: TextStyle(fontSize: 11)),
          trailing: const Icon(Icons.chevron_right),
          onTap: _editTranslateRules,
        ),
        const SizedBox(height: AppSpacing.xl),
      ]),
    );
  }
}
