import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 翻译设置 - 对齐原版翻译配置
class TranslateConfigScreen extends StatefulWidget {
  const TranslateConfigScreen({super.key});

  @override
  State<TranslateConfigScreen> createState() => _TranslateConfigScreenState();
}

class _TranslateConfigScreenState extends State<TranslateConfigScreen> {
  static const _engines = ['谷歌翻译', '百度翻译', '有道翻译', '腾讯翻译君', 'DeepL', '微软翻译'];
  int _engine = 0;
  String _targetLang = '简体中文';
  bool _enable = false;
  bool _translateAll = false;
  double _interval = 100;
  final _appId = TextEditingController();
  final _appKey = TextEditingController();

  static const _langs = ['简体中文', '繁體中文', 'English', '日本語', '한국어', 'Français', 'Deutsch', 'Español'];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _enable = p.getBool('tr_enable') ?? false;
      _engine = p.getInt('tr_engine') ?? 0;
      _targetLang = p.getString('tr_target') ?? '简体中文';
      _translateAll = p.getBool('tr_all') ?? false;
      _interval = (p.getDouble('tr_interval') ?? 100);
      _appId.text = p.getString('tr_appId') ?? '';
      _appKey.text = p.getString('tr_appKey') ?? '';
    });
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('tr_enable', _enable);
    await p.setInt('tr_engine', _engine);
    await p.setString('tr_target', _targetLang);
    await p.setBool('tr_all', _translateAll);
    await p.setDouble('tr_interval', _interval);
    await p.setString('tr_appId', _appId.text);
    await p.setString('tr_appKey', _appKey.text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('翻译设置'), actions: [
        TextButton(onPressed: () { _save(); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('翻译配置已保存'))); }, child: const Text('保存')),
      ]),
      body: ListView(children: [
        SwitchListTile(title: const Text('启用翻译'), value: _enable, onChanged: (v) => setState(() => _enable = v)),
        SwitchListTile(title: const Text('翻译整章'), subtitle: const Text('关闭则仅翻译选中段落', style: TextStyle(fontSize: 11)), value: _translateAll, onChanged: (v) => setState(() => _translateAll = v)),
        const Divider(),
        const Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text('翻译引擎', style: TextStyle(fontWeight: FontWeight.bold))),
        ...List.generate(_engines.length, (i) => RadioListTile<int>(
          dense: true, value: i, groupValue: _engine,
          title: Text(_engines[i]),
          onChanged: (v) => setState(() => _engine = v ?? 0),
        )),
        const Divider(),
        ListTile(dense: true, title: const Text('目标语言'), trailing: DropdownButton<String>(
          value: _targetLang, underline: const SizedBox(),
          items: _langs.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
          onChanged: (v) => setState(() => _targetLang = v ?? '简体中文'),
        )),
        ListTile(dense: true, title: Text('翻译请求间隔: ${_interval.toInt()} ms'),
          subtitle: Slider(value: _interval, min: 0, max: 1000, divisions: 20, label: '${_interval.toInt()}',
            onChanged: (v) => setState(() => _interval = v))),
        const Divider(),
        const Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text('引擎密钥（百度/有道等需要）', style: TextStyle(fontWeight: FontWeight.bold))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: TextField(controller: _appId, decoration: const InputDecoration(labelText: 'App ID / 密钥ID', border: OutlineInputBorder(), isDense: true))),
        const SizedBox(height: 12),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: TextField(controller: _appKey, obscureText: true, decoration: const InputDecoration(labelText: 'App Key / 密钥', border: OutlineInputBorder(), isDense: true))),
        const SizedBox(height: 24),
      ]),
    );
  }
}
