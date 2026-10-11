import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 封面配置页面 - 对齐原版CoverConfigScreen
class CoverConfigScreen extends StatefulWidget {
  const CoverConfigScreen({super.key});

  @override
  State<CoverConfigScreen> createState() => _CoverConfigScreenState();
}

class _CoverConfigScreenState extends State<CoverConfigScreen> {
  bool _onlyWifi = false;
  bool _useDefaultCover = false;
  bool _coverShadow = true;
  bool _coverStroke = false;
  bool _showName = true;
  bool _showAuthor = true;
  bool _nightShowName = true;
  bool _nightShowAuthor = true;
  int _orientation = 0; // 0 竖 1 横
  int _defaultColor = 0xFF607D8B;
  int _dayTextColor = 0xFFFFFFFF;
  int _nightTextColor = 0xFFB0BEC5;
  int _badgeType = 0;

  static const _orientationNames = ['竖向', '横向'];
  static const _badgeNames = ['不显示', '显示来源', '显示作者'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _onlyWifi = p.getBool('cover_onlyWifi') ?? false;
      _useDefaultCover = p.getBool('cover_useDefault') ?? false;
      _coverShadow = p.getBool('cover_shadow') ?? true;
      _coverStroke = p.getBool('cover_stroke') ?? false;
      _showName = p.getBool('cover_showName') ?? true;
      _showAuthor = p.getBool('cover_showAuthor') ?? true;
      _nightShowName = p.getBool('cover_nightShowName') ?? true;
      _nightShowAuthor = p.getBool('cover_nightShowAuthor') ?? true;
      _orientation = p.getInt('cover_orientation') ?? 0;
      _defaultColor = p.getInt('cover_defaultColor') ?? 0xFF607D8B;
      _dayTextColor = p.getInt('cover_dayTextColor') ?? 0xFFFFFFFF;
      _nightTextColor = p.getInt('cover_nightTextColor') ?? 0xFFB0BEC5;
      _badgeType = p.getInt('cover_badge') ?? 0;
    });
  }

  Future<void> _set(String key, dynamic v) async {
    final p = await SharedPreferences.getInstance();
    if (v is bool) await p.setBool(key, v);
    if (v is int) await p.setInt(key, v);
  }

  Widget _section(String t) => Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
    child: Text(t, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)));

  Widget _sw(String t, bool v, ValueChanged<bool> on, {String? sub}) =>
    SwitchListTile(dense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Text(t, style: const TextStyle(fontSize: 14)),
      subtitle: sub != null ? Text(sub, style: const TextStyle(fontSize: 11)) : null,
      value: v, onChanged: on);

  Future<void> _pickColor(int current, ValueChanged<int> onSave) async {
    const colors = [0xFF607D8B, 0xFFE57373, 0xFFFFB74D, 0xFFFFF176, 0xFF81C784, 0xFF64B5F6, 0xFFBA68C8, 0xFFFFFFFF, 0xFF424242];
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('选择颜色'),
      content: Wrap(spacing: 12, runSpacing: 12, children: colors.map((colorVal) => GestureDetector(
        onTap: () { Navigator.pop(ctx); onSave(colorVal); },
        child: Container(width: 40, height: 40, decoration: BoxDecoration(color: Color(colorVal), shape: BoxShape.circle, border: Border.all(color: colorVal == current ? Colors.black : Colors.grey, width: colorVal == current ? 3 : 1))),
      )).toList()),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('封面配置')),
      body: ListView(children: [
        _section('加载'),
        _sw('仅WiFi下加载封面', _onlyWifi, (v) { setState(() => _onlyWifi = v); _set('cover_onlyWifi', v); }),
        ListTile(dense: true, title: const Text('封面规则'), subtitle: const Text('自定义封面获取规则', style: TextStyle(fontSize: 11)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showDialog(context: context, builder: (c) => const AlertDialog(title: Text('封面规则'), content: Text('封面规则用于在书籍无封面时，根据书名/作者从网络搜索匹配封面。')))),
        _sw('使用默认封面', _useDefaultCover, (v) { setState(() => _useDefaultCover = v); _set('cover_useDefault', v); }, sub: '无封面时显示生成的默认封面'),
        _sw('封面显示阴影', _coverShadow, (v) { setState(() => _coverShadow = v); _set('cover_shadow', v); }),
        _sw('封面显示描边', _coverStroke, (v) { setState(() => _coverStroke = v); _set('cover_stroke', v); }),
        ListTile(dense: true, title: const Text('默认封面颜色'), trailing: CircleAvatar(backgroundColor: Color(_defaultColor), radius: 14),
          onTap: () => _pickColor(_defaultColor, (c) { setState(() => _defaultColor = c); _set('cover_defaultColor', c); })),
        ListTile(dense: true, title: const Text('封面信息方向'),
          trailing: DropdownButton<int>(value: _orientation, underline: const SizedBox(),
            items: List.generate(_orientationNames.length, (i) => DropdownMenuItem(value: i, child: Text(_orientationNames[i]))),
            onChanged: (v) { setState(() => _orientation = v ?? 0); _set('cover_orientation', v ?? 0); })),
        _section('网络书籍角标'),
        ListTile(dense: true, title: const Text('角标显示内容'),
          trailing: DropdownButton<int>(value: _badgeType, underline: const SizedBox(),
            items: List.generate(_badgeNames.length, (i) => DropdownMenuItem(value: i, child: Text(_badgeNames[i]))),
            onChanged: (v) { setState(() => _badgeType = v ?? 0); _set('cover_badge', v ?? 0); })),
        _section('日间'),
        ListTile(dense: true, title: const Text('文字颜色'), trailing: CircleAvatar(backgroundColor: Color(_dayTextColor), radius: 14),
          onTap: () => _pickColor(_dayTextColor, (c) { setState(() => _dayTextColor = c); _set('cover_dayTextColor', c); })),
        _sw('显示书名', _showName, (v) { setState(() => _showName = v); _set('cover_showName', v); }),
        _sw('显示作者', _showAuthor, (v) { setState(() => _showAuthor = v); _set('cover_showAuthor', v); }),
        _section('夜间'),
        ListTile(dense: true, title: const Text('文字颜色'), trailing: CircleAvatar(backgroundColor: Color(_nightTextColor), radius: 14),
          onTap: () => _pickColor(_nightTextColor, (c) { setState(() => _nightTextColor = c); _set('cover_nightTextColor', c); })),
        _sw('显示书名', _nightShowName, (v) { setState(() => _nightShowName = v); _set('cover_nightShowName', v); }),
        _sw('显示作者', _nightShowAuthor, (v) { setState(() => _nightShowAuthor = v); _set('cover_nightShowAuthor', v); }),
        const SizedBox(height: 24),
      ]),
    );
  }
}
