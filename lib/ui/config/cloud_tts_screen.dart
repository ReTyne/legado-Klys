import 'package:flutter/material.dart';
import 'package:legado_md3/data/model/cloud_tts_engine.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/help/readaloud/cloud_tts_providers.dart';

class CloudTtsScreen extends StatefulWidget {
  const CloudTtsScreen({super.key});
  @override
  State<CloudTtsScreen> createState() => _CloudTtsScreenState();
}

class _CloudTtsScreenState extends State<CloudTtsScreen> {
  final DatabaseService _db = DatabaseService();
  List<CloudTtsEngine> _engines = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadEngines();
  }

  Future<void> _loadEngines() async {
    setState(() => _isLoading = true);
    final engines = await _db.getCloudTtsEngines();
    if (engines.isEmpty) {
      // 初始化默认引擎
      final defaults = [
        CloudTtsEngine(name: '系统TTS', type: 'system', enabled: 1),
        CloudTtsEngine(name: '阿里云TTS', type: 'aliyun', region: 'cn-shanghai', enabled: 0),
        CloudTtsEngine(name: '腾讯云TTS', type: 'tencent', enabled: 0),
        CloudTtsEngine(name: 'Azure语音', type: 'azure', region: 'eastasia', enabled: 0),
        CloudTtsEngine(name: 'OpenAI TTS', type: 'openai', url: 'https://api.openai.com/v1/audio/speech', enabled: 0),
        CloudTtsEngine(name: '火山引擎TTS', type: 'volcengine', enabled: 0),
        CloudTtsEngine(name: 'AWS Polly', type: 'aws', region: 'us-east-1', enabled: 0),
        CloudTtsEngine(name: 'Gemini TTS', type: 'gemini', enabled: 0),
        CloudTtsEngine(name: 'Mimo TTS', type: 'mimo', enabled: 0),
        CloudTtsEngine(name: '免费谷歌朗读(免Key)', type: 'free_google', voice: 'zh-CN', enabled: 0),
      ];
      for (final e in defaults) {
        await _db.insertCloudTtsEngine(e);
      }
      _engines = await _db.getCloudTtsEngines();
    } else {
      _engines = engines;
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('TTS引擎管理')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _engines.length,
              itemBuilder: (context, index) {
                final engine = _engines[index];
                final isSystem = engine.type == 'system';
                return Card(
                  child: ListTile(
                    leading: Icon(isSystem ? Icons.phone_android : Icons.cloud_outlined),
                    title: Text(engine.name),
                    subtitle: Text(isSystem ? '系统内置' : '${CloudTtsProviderFactory.getProviderName(engine.type)}${engine.region != null ? " (${engine.region})" : ""}'),
                    trailing: Switch(
                      value: engine.enabled == 1,
                      onChanged: (v) {
                        setState(() => engine.enabled = v ? 1 : 0);
                        _db.updateCloudTtsEngine(engine);
                      },
                    ),
                    onTap: () => _showEngineConfig(engine, index),
                  ),
                );
              },
            ),
    );
  }

  void _showEngineConfig(CloudTtsEngine engine, int index) {
    final apiKeyController = TextEditingController(text: engine.apiKey ?? '');
    final urlController = TextEditingController(text: engine.url ?? '');
    final regionController = TextEditingController(text: engine.region ?? '');
    final voiceController = TextEditingController(text: engine.voice ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(engine.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            if (engine.type != 'system') ...[
              TextField(controller: apiKeyController, decoration: const InputDecoration(labelText: 'API Key', border: OutlineInputBorder()), obscureText: true),
              const SizedBox(height: 12),
              TextField(controller: urlController, decoration: const InputDecoration(labelText: 'API URL', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: regionController, decoration: const InputDecoration(labelText: '区域', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: voiceController, decoration: const InputDecoration(labelText: '默认语音', border: OutlineInputBorder())),
              const SizedBox(height: 16),
            ],
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  engine.apiKey = apiKeyController.text;
                  engine.url = urlController.text;
                  engine.region = regionController.text;
                  engine.voice = voiceController.text;
                  _db.updateCloudTtsEngine(engine);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('配置已保存')));
                },
                child: const Text('保存'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
