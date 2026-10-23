import 'package:flutter/material.dart';
import 'package:legado_md3/help/config/app_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 封面配置页面 - 对齐原版CoverConfigScreen
///
/// useDefaultCover / coverShowName / coverShowAuthor 三个开关统一经
/// [AppPrefs] 读写（键名 cover_useDefault / cover_showName / cover_showAuthor 不变），
/// 消费点：bookshelf_screen.dart 的 _ViewCfg（无封面占位、封面叠加书名/作者）。
class CoverConfigScreen extends StatefulWidget {
  const CoverConfigScreen({super.key});

  @override
  State<CoverConfigScreen> createState() => _CoverConfigScreenState();
}

class _CoverConfigScreenState extends State<CoverConfigScreen> {
  bool _onlyWifi = false;
  bool _useDefaultCover = false;
  bool _coverShadow = true;
  bool _showName = true;
  bool _showAuthor = true;
  bool _nightShowName = true;
  bool _nightShowAuthor = true;
  int _defaultColor = 0xFF607D8B;
  int _dayTextColor = 0xFFFFFFFF;
  int _nightTextColor = 0xFFB0BEC5;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    // 三项封面开关统一走 AppPrefs 访问层（键名与 bookshelf_screen 消费方一致）
    AppPrefs.loadFrom(p);
    setState(() {
      _onlyWifi = p.getBool('cover_onlyWifi') ?? false;
      _useDefaultCover = AppPrefs.useDefaultCover;
      // 书架封面阴影读取的键是 bs_coverShadow（bookshelf_screen._ViewCfg.coverShadow）
      _coverShadow = p.getBool('bs_coverShadow') ?? true;
      _showName = AppPrefs.coverShowName;
      _showAuthor = AppPrefs.coverShowAuthor;
      _nightShowName = p.getBool('cover_nightShowName') ?? true;
      _nightShowAuthor = p.getBool('cover_nightShowAuthor') ?? true;
      _defaultColor = p.getInt('cover_defaultColor') ?? 0xFF607D8B;
      _dayTextColor = p.getInt('cover_dayTextColor') ?? 0xFFFFFFFF;
      _nightTextColor = p.getInt('cover_nightTextColor') ?? 0xFFB0BEC5;
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
        _sw('使用默认封面', _useDefaultCover, (v) { setState(() => _useDefaultCover = v); AppPrefs.useDefaultCover = v; }, sub: '无封面时显示生成的默认封面（cover_useDefault）'),
        _sw('封面显示阴影', _coverShadow, (v) { setState(() => _coverShadow = v); _set('bs_coverShadow', v); }, sub: '书架封面阴影（bs_coverShadow）'),
        ListTile(dense: true, title: const Text('默认封面颜色'), trailing: CircleAvatar(backgroundColor: Color(_defaultColor), radius: 14),
          onTap: () => _pickColor(_defaultColor, (c) { setState(() => _defaultColor = c); _set('cover_defaultColor', c); })),
        _section('日间'),
        ListTile(dense: true, title: const Text('文字颜色'), trailing: CircleAvatar(backgroundColor: Color(_dayTextColor), radius: 14),
          onTap: () => _pickColor(_dayTextColor, (c) { setState(() => _dayTextColor = c); _set('cover_dayTextColor', c); })),
        _sw('显示书名', _showName, (v) { setState(() => _showName = v); AppPrefs.coverShowName = v; }),
        _sw('显示作者', _showAuthor, (v) { setState(() => _showAuthor = v); AppPrefs.coverShowAuthor = v; }),
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
