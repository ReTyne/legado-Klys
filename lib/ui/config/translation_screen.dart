import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/help/translate/translation_service.dart';

/// 翻译设置：引擎/源语言/目标语言/自定义端点，全部持久化，可发送测试请求
class TranslationScreen extends StatefulWidget {
  const TranslationScreen({super.key});

  @override
  State<TranslationScreen> createState() => _TranslationScreenState();
}

class _TranslationScreenState extends State<TranslationScreen> {
  bool _enabled = false;
  String _sourceLang = 'auto';
  String _targetLang = 'zh-CN';
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _apiUrlController = TextEditingController();
  bool _testing = false;

  final List<String> _langs = ['auto', 'zh-CN', 'zh-TW', 'en', 'ja', 'ko', 'fr', 'de', 'es', 'ru'];
  String _langName(String l) => {
        'auto': '自动检测', 'zh-CN': '简体中文', 'zh-TW': '繁体中文', 'en': '英语',
        'ja': '日语', 'ko': '韩语', 'fr': '法语', 'de': '德语', 'es': '西班牙语', 'ru': '俄语',
      }[l] ?? l;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _enabled = p.getBool('translate_enabled') ?? false;
      _sourceLang = p.getString('tr_source') ?? 'auto';
      _targetLang = p.getString('tr_target') ?? 'zh-CN';
      _apiKeyController.text = p.getString('tr_api_key') ?? '';
      _apiUrlController.text = p.getString('tr_api_url') ?? '';
    });
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('translate_enabled', _enabled);
    await p.setString('tr_source', _sourceLang);
    await p.setString('tr_target', _targetLang);
    await p.setString('tr_api_key', _apiKeyController.text.trim());
    await p.setString('tr_api_url', _apiUrlController.text.trim());
    await TranslationService.instance.loadPrefs();
  }

  Future<void> _test() async {
    await _save();
    setState(() => _testing = true);
    final r = await TranslationService.instance.translate('Hello world', source: 'en', target: _targetLang);
    if (mounted) {
      setState(() => _testing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('测试结果: $r')));
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _apiUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('翻译设置')),
      body: ListView(children: [
        SwitchListTile(
          title: const Text('启用翻译'),
          subtitle: const Text('阅读正文时可自动翻译'),
          value: _enabled,
          onChanged: (v) { setState(() => _enabled = v); _save(); },
        ),
        const Divider(),
        ListTile(
          title: const Text('源语言'),
          trailing: DropdownButton<String>(
            value: _sourceLang,
            items: _langs.map((l) => DropdownMenuItem(value: l, child: Text(_langName(l)))).toList(),
            onChanged: (v) { setState(() => _sourceLang = v ?? 'auto'); _save(); },
          ),
        ),
        ListTile(
          title: const Text('目标语言'),
          trailing: DropdownButton<String>(
            value: _targetLang,
            items: _langs.where((l) => l != 'auto').map((l) => DropdownMenuItem(value: l, child: Text(_langName(l)))).toList(),
            onChanged: (v) { setState(() => _targetLang = v ?? 'zh-CN'); _save(); },
          ),
        ),
        const Divider(),
        const Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text('自定义端点（留空使用免费谷歌翻译）', style: TextStyle(fontSize: 12, color: Colors.grey))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: TextField(controller: _apiUrlController, decoration: const InputDecoration(labelText: 'API URL，可用 {text}/{from}/{to}/{key}', border: OutlineInputBorder()))),
        const SizedBox(height: 12),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: TextField(controller: _apiKeyController, decoration: const InputDecoration(labelText: 'API Key（可选）', border: OutlineInputBorder()))),
        const SizedBox(height: 16),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: FilledButton.icon(
          onPressed: _testing ? null : _test,
          icon: _testing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.network_check),
          label: const Text('测试翻译'),
        )),
        const SizedBox(height: 24),
      ]),
    );
  }
}
