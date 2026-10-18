import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
        const Center(child: Text('实验性功能可能随时变更或移除', style: TextStyle(fontSize: 11, color: Colors.grey))),
      ]),
    );
  }
}
