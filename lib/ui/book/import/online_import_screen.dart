import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:legado_md3/common/deep_link_service.dart';

/// 在线导入 / 一键导入界面（对齐 legado-E ui/association/OnLineImportActivity.kt）。
///
/// E 的 OnLineImportActivity 接收 `legado://import/{path}?src={url}` 深链，
/// 按 bookSource / rssSource / replaceRule / textTocRule / httpTTS / dictRule /
/// readConfig 分派到各 ImportXxxDialog。本页提供等价的「输入 URL 一键导入」
/// 界面：用户可直接粘贴 URL / JSON / legado:// 链接，可选类型或自动识别，
/// 统一交给 [DeepLinkService] 的 7 类分派（含 addToBookshelf / theme）。
class OnlineImportScreen extends StatefulWidget {
  const OnlineImportScreen({super.key, this.initialUrl, this.initialType});

  /// 预填地址（从二维码 / 剪贴板 / 深链跳转进来时使用）
  final String? initialUrl;

  /// 预填导入类型（null 为自动识别）
  final String? initialType;

  @override
  State<OnlineImportScreen> createState() => _OnlineImportScreenState();
}

class _OnlineImportScreenState extends State<OnlineImportScreen> {
  /// 导入类型：对齐 E OnLineImportActivity 的全部路径名。
  static const Map<String, String> _typeLabels = {
    'auto': '自动识别（按内容判断）',
    'bookSource': '书源',
    'rss': '订阅源(RSS)',
    'replaceRule': '替换规则',
    'txtRule': 'TXT目录规则',
    'httpTts': '在线TTS',
    'dictRule': '字典规则',
    'theme': '主题',
    'readConfig': '阅读配置',
  };

  static const String _historyKey = 'online_import_history';

  final TextEditingController _urlController = TextEditingController();
  String _type = 'auto';
  bool _busy = false;
  String _status = '';
  List<String> _history = [];

  @override
  void initState() {
    super.initState();
    _urlController.text = widget.initialUrl ?? '';
    final t = widget.initialType;
    if (t != null && _typeLabels.containsKey(t)) _type = t;
    _loadHistory();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() => _history = prefs.getStringList(_historyKey) ?? []);
      }
    } catch (_) {}
  }

  Future<void> _saveHistory(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final next = [url, ..._history.where((e) => e != url)].take(8).toList();
      await prefs.setStringList(_historyKey, next);
      if (mounted) setState(() => _history = next);
    } catch (_) {}
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      _setStatus('剪贴板为空');
      return;
    }
    _urlController.text = text;
    _setStatus('已粘贴剪贴板内容');
  }

  void _setStatus(String s) {
    if (mounted) setState(() => _status = s);
  }

  /// 一键导入：legado:// / share:// 走深链分派，其余（URL/JSON）走 importRaw。
  /// 对齐 E OnLineImportActivity 的 determineType + 各 ImportXxxDialog。
  Future<void> _doImport() async {
    final text = _urlController.text.trim();
    if (text.isEmpty) {
      _setStatus('请输入导入地址、JSON 或 legado:// 链接');
      return;
    }
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = '正在导入…';
    });
    try {
      if (text.startsWith('legado://') || text.startsWith('share://')) {
        await DeepLinkService.instance.handleLink(text);
      } else {
        await DeepLinkService.instance.importRaw(
          text,
          type: _type == 'auto' ? null : _type,
        );
      }
      await _saveHistory(text);
      _setStatus('导入已提交：${_typeLabels[_type]}');
    } catch (e) {
      _setStatus('导入失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('在线导入'),
        actions: [
          IconButton(
            tooltip: '从剪贴板粘贴',
            icon: const Icon(Icons.content_paste),
            onPressed: _paste,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 说明：对齐 E OnLineImport 支持的 7 类导入
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withOpacity(0.35),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              '粘贴书源 / 订阅 / 替换规则 / TXT目录 / 在线TTS / 字典 / 主题 / '
              '阅读配置的 URL、JSON，或 legado:// 导入链接，一键导入。',
              style: TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _type,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: '导入类型',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.category_outlined),
            ),
            items: _typeLabels.entries
                .map((e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _type = v ?? 'auto'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _urlController,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: '导入地址 / JSON / legado:// 链接',
              hintText: 'https://…/bookSource.json 或 legado://import/bookSource?src=…',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
              prefixIcon: Icon(Icons.link),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _doImport,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded),
            label: Text(_busy ? '导入中…' : '一键导入'),
          ),
          if (_status.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: cs.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(_status,
                      style: TextStyle(fontSize: 12, color: cs.primary)),
                ),
              ],
            ),
          ],
          if (_history.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text('最近导入',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _history
                  .map((u) => ActionChip(
                        label: Text(
                          u.length > 32 ? '${u.substring(0, 32)}…' : u,
                          style: const TextStyle(fontSize: 11),
                        ),
                        onPressed: () =>
                            setState(() => _urlController.text = u),
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}
