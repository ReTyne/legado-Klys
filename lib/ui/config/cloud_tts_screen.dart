import 'package:flutter/material.dart';

import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/db_models.dart';
import 'package:legado_md3/help/readaloud/cloud_tts_providers.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';

/// TTS 引擎管理：内置 / 云端引擎 + 自定义 HTTP TTS（§4-1 / §4-2）。
///
/// 此前 http_tts 表「能导入、能备份，但既不展示也不参与朗读」，getVoices()
/// 也零调用。本页把两者接到 UI：
/// - 自定义 HTTP TTS：列出 getHttpTTS() 并支持新增 / 编辑 / 删除 / 启用；
/// - 语音列表：引擎配置里调用 CloudTtsProvider.getVoices() 下拉选择，
///   选择结果写入 voiceController 并持久化到引擎。
/// 自定义 HTTP TTS 的增删改统一走 DatabaseService 的
/// getHttpTTS / insertHttpTTS / updateHttpTTS / deleteHttpTTS DAO；
/// 引擎经 HttpTtsProvider 适配器接入 TtsService 的朗读链路。
class CloudTtsScreen extends StatefulWidget {
  const CloudTtsScreen({super.key});

  @override
  State<CloudTtsScreen> createState() => _CloudTtsScreenState();
}

class _CloudTtsScreenState extends State<CloudTtsScreen> {
  final DatabaseService _db = DatabaseService();
  List<CloudTtsEngine> _engines = [];
  List<HttpTTS> _httpTts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final engines = await _db.getCloudTtsEngines();
    if (engines.isEmpty) {
      final defaults = [
        CloudTtsEngine(name: '系统TTS', type: 'system', enabled: 1),
        CloudTtsEngine(
            name: '阿里云TTS', type: 'aliyun', region: 'cn-shanghai', enabled: 0),
        CloudTtsEngine(name: '腾讯云TTS', type: 'tencent', enabled: 0),
        CloudTtsEngine(name: 'Azure语音', type: 'azure', region: 'eastasia', enabled: 0),
        CloudTtsEngine(
            name: 'OpenAI TTS',
            type: 'openai',
            url: 'https://api.openai.com/v1/audio/speech',
            enabled: 0),
        CloudTtsEngine(name: '火山引擎TTS', type: 'volcengine', enabled: 0),
        CloudTtsEngine(name: 'AWS Polly', type: 'aws', region: 'us-east-1', enabled: 0),
        CloudTtsEngine(name: 'Gemini TTS', type: 'gemini', enabled: 0),
        CloudTtsEngine(name: 'Mimo TTS', type: 'mimo', enabled: 0),
        CloudTtsEngine(
            name: '免费谷歌朗读(免Key)',
            type: 'free_google',
            voice: 'zh-CN',
            enabled: 0),
      ];
      for (final e in defaults) {
        await _db.insertCloudTtsEngine(e);
      }
    }
    final allEngines = await _db.getCloudTtsEngines();
    final httpTts = await _db.getHttpTTS();
    if (!mounted) return;
    setState(() {
      _engines = allEngines;
      _httpTts = httpTts;
      _isLoading = false;
    });
  }

  void _tip(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /* ---------------- 内置 / 云端引擎 ---------------- */

  Future<void> _toggleEngine(CloudTtsEngine engine, bool v) async {
    engine.enabled = v ? 1 : 0;
    await _db.updateCloudTtsEngine(engine);
    setState(() {});
  }

  void _showEngineConfig(CloudTtsEngine engine) {
    final apiKeyController = TextEditingController(text: engine.apiKey ?? '');
    final urlController = TextEditingController(text: engine.url ?? '');
    final regionController = TextEditingController(text: engine.region ?? '');
    final voiceController = TextEditingController(text: engine.voice ?? '');

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(engine.name,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              if (engine.type != 'system') ...[
                TextField(
                  controller: apiKeyController,
                  decoration: const InputDecoration(labelText: 'API Key'),
                  obscureText: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: urlController,
                  decoration: const InputDecoration(labelText: 'API URL'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: regionController,
                  decoration: const InputDecoration(labelText: '区域'),
                ),
                const SizedBox(height: 12),
                // 语音改为「下拉选择」：点击右侧按钮调 getVoices() 后填入 voiceController。
                TextField(
                  controller: voiceController,
                  decoration: InputDecoration(
                    labelText: '默认语音（可手填，或点右侧从引擎列表选择）',
                    suffixIcon: IconButton(
                      tooltip: '从引擎语音列表选择',
                      icon: const Icon(Icons.arrow_drop_down),
                      onPressed: () =>
                          _pickVoice(engine, voiceController),
                    ),
                  ),
                ),
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
                    Navigator.pop(sheetCtx);
                    _tip('配置已保存');
                  },
                  child: const Text('保存'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 调 CloudTtsProvider.getVoices() 得到可用语音，单选后填入 voiceController。
  Future<void> _pickVoice(
      CloudTtsEngine engine, TextEditingController voiceController) async {
    final provider = CloudTtsProviderFactory.create(engine);
    if (provider == null) {
      _tip('该引擎不支持语音列表');
      return;
    }
    List<String> voices;
    try {
      voices = await provider.getVoices();
    } catch (e) {
      _tip('获取语音列表失败: $e');
      return;
    }
    if (voices.isEmpty) {
      _tip('该引擎未返回可用语音');
      return;
    }
    if (!mounted) return;
    final current = voiceController.text.trim();
    final options = <String>['', ...voices];
    if (current.isNotEmpty && !options.contains(current)) {
      options.insert(1, current);
    }
    final picked = await showAppRadioDialog<String>(
      context,
      title: '选择默认语音',
      groupValue: current,
      options: [
        for (final v in options)
          AppRadioOption<String>(v, v.isEmpty ? '不设置（使用引擎默认）' : v),
      ],
    );
    if (picked != null) voiceController.text = picked;
  }

  /* ---------------- 自定义 HTTP TTS ---------------- */

  Future<void> _editHttpTts([HttpTTS? tts]) async {
    final result = await showDialog<HttpTTS>(
      context: context,
      builder: (_) => _HttpTtsEditDialog(tts: tts),
    );
    if (result == null) return;
    if (result.id == null) {
      await _db.insertHttpTTS(result);
    } else {
      await _updateHttpTts(result);
    }
    await _load();
  }

  /// 统一走数据层 DAO（updateHttpTTS / deleteHttpTTS），不再直连 SQL。
  Future<void> _updateHttpTts(HttpTTS tts) async {
    await _db.updateHttpTTS(tts);
  }

  Future<void> _deleteHttpTts(HttpTTS tts) async {
    if (tts.id == null) return;
    await _db.deleteHttpTTS(tts.id!);
  }

  Future<void> _toggleHttpTts(HttpTTS tts, bool v) async {
    tts.enabled = v ? 1 : 0;
    await _updateHttpTts(tts);
    await _load();
  }

  Future<void> _confirmDeleteHttpTts(HttpTTS tts) async {
    final ok = await showAppConfirmDialog(
      context,
      title: '删除自定义 HTTP TTS',
      content: '确定删除「${tts.name}」吗？',
      confirmText: '删除',
      danger: true,
    );
    if (!ok) return;
    await _deleteHttpTts(tts);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('TTS 引擎管理'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                const AppSectionHeader('内置 / 云端引擎'),
                for (final engine in _engines)
                  _buildEngineTile(engine, cs),
                const AppSectionHeader('自定义 HTTP TTS'),
                if (_httpTts.isEmpty)
                  const SizedBox(
                    height: 170,
                    child: AppEmptyState(
                      icon: Icons.cloud_outlined,
                      title: '暂无自定义 HTTP TTS',
                      message: '可新增自定义端点；朗读注册由主代理在 tts_service 接线',
                    ),
                  )
                else
                  for (final tts in _httpTts) _buildHttpTtsTile(tts, cs),
                AppMenuItem(
                  icon: Icons.add,
                  title: '新增自定义 HTTP TTS',
                  subtitle: '名称 / URL / 请求方法 / 请求头 / 请求体',
                  trailing: const Icon(Icons.add),
                  onTap: () => _editHttpTts(),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  child: Text(
                    '说明：自定义 HTTP TTS 已可增删改与启用；其参与朗读需主代理在 tts_service 启动时读取 getHttpTTS() 注册引擎。',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildEngineTile(CloudTtsEngine engine, ColorScheme cs) {
    final isSystem = engine.type == 'system';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: Icon(isSystem ? Icons.phone_android : Icons.cloud_outlined),
        title: Text(engine.name),
        subtitle: Text(isSystem
            ? '系统内置'
            : '${CloudTtsProviderFactory.getProviderName(engine.type)}'
                '${engine.region != null ? " (${engine.region})" : ""}'),
        trailing: Switch(
          value: engine.enabled == 1,
          onChanged: (v) => _toggleEngine(engine, v),
        ),
        onTap: () => _showEngineConfig(engine),
      ),
    );
  }

  Widget _buildHttpTtsTile(HttpTTS tts, ColorScheme cs) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: Icon(Icons.http_outlined,
            color: tts.enabled == 1 ? cs.primary : cs.onSurfaceVariant),
        title: Text(tts.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('${tts.method ?? 'GET'} · ${tts.url}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: tts.enabled == 1,
              onChanged: (v) => _toggleHttpTts(tts, v),
            ),
            IconButton(
              tooltip: '编辑',
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: () => _editHttpTts(tts),
            ),
            IconButton(
              tooltip: '删除',
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () => _confirmDeleteHttpTts(tts),
            ),
          ],
        ),
        onTap: () => _editHttpTts(tts),
      ),
    );
  }
}

/// 自定义 HTTP TTS 新增 / 编辑。
class _HttpTtsEditDialog extends StatefulWidget {
  final HttpTTS? tts;
  const _HttpTtsEditDialog({this.tts});

  @override
  State<_HttpTtsEditDialog> createState() => _HttpTtsEditDialogState();
}

class _HttpTtsEditDialogState extends State<_HttpTtsEditDialog> {
  late final TextEditingController _name;
  late final TextEditingController _url;
  late final TextEditingController _headers;
  late final TextEditingController _body;
  late String _method;
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    final t = widget.tts;
    _name = TextEditingController(text: t?.name ?? '');
    _url = TextEditingController(text: t?.url ?? '');
    _headers = TextEditingController(text: t?.headers ?? '');
    _body = TextEditingController(text: t?.body ?? '');
    _method = (t?.method ?? 'GET').toUpperCase() == 'POST' ? 'POST' : 'GET';
    _enabled = (t?.enabled ?? 1) == 1;
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _headers.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _pickMethod() async {
    final v = await showAppRadioDialog<String>(
      context,
      title: '请求方法',
      groupValue: _method,
      options: const [
        AppRadioOption<String>('GET', 'GET'),
        AppRadioOption<String>('POST', 'POST'),
      ],
    );
    if (v != null) setState(() => _method = v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.tts == null ? '新增自定义 HTTP TTS' : '编辑自定义 HTTP TTS'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: '名称'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _url,
              decoration: const InputDecoration(
                  labelText: 'URL', hintText: 'https://example.com/tts'),
            ),
            const SizedBox(height: 8),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('请求方法'),
              subtitle: Text(_method),
              trailing: const Icon(Icons.arrow_drop_down),
              onTap: _pickMethod,
            ),
            TextField(
              controller: _headers,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: '请求头（JSON，可选）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _body,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '请求体模板（可选）',
                border: OutlineInputBorder(),
              ),
            ),
            AppSwitchTile(
              title: '启用',
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            final url = _url.text.trim();
            if (name.isEmpty || url.isEmpty) return;
            Navigator.pop(
              context,
              HttpTTS(
                id: widget.tts?.id,
                name: name,
                url: url,
                method: _method,
                headers: _headers.text.trim().isEmpty
                    ? null
                    : _headers.text.trim(),
                body: _body.text.trim().isEmpty ? null : _body.text.trim(),
                enabled: _enabled ? 1 : 0,
                concurrentRate: widget.tts?.concurrentRate,
              ),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
