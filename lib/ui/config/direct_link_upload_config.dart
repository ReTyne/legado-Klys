import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:legado_md3/help/storage/direct_link_upload.dart';

/// 直链上传规则配置对话框（E: ui/config/DirectLinkUploadConfig.kt）。
///
/// 编辑当前生效的上传规则；支持从内置默认规则导入、复制/粘贴规则 JSON、
/// 以 `test.json` 测试上传。保存后写入 SharedPreferences。
class DirectLinkUploadConfigDialog extends StatefulWidget {
  const DirectLinkUploadConfigDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (_) => const DirectLinkUploadConfigDialog(),
    );
  }

  @override
  State<DirectLinkUploadConfigDialog> createState() =>
      _DirectLinkUploadConfigDialogState();
}

class _DirectLinkUploadConfigDialogState
    extends State<DirectLinkUploadConfigDialog> {
  final _uploadUrlCtl = TextEditingController();
  final _downloadRuleCtl = TextEditingController();
  final _summaryCtl = TextEditingController();
  bool _compress = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _uploadUrlCtl.dispose();
    _downloadRuleCtl.dispose();
    _summaryCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final rule = await DirectLinkUploadService.getRule();
    if (!mounted) return;
    setState(() {
      _uploadUrlCtl.text = rule.uploadUrl;
      _downloadRuleCtl.text = rule.downloadUrlRule;
      _summaryCtl.text = rule.summary;
      _compress = rule.compress;
    });
  }

  DirectLinkRule? _currentRule() {
    final uploadUrl = _uploadUrlCtl.text.trim();
    final downloadUrlRule = _downloadRuleCtl.text.trim();
    final summary = _summaryCtl.text.trim();
    if (uploadUrl.isEmpty) {
      _toast('上传Url不能为空');
      return null;
    }
    if (downloadUrlRule.isEmpty) {
      _toast('下载Url规则不能为空');
      return null;
    }
    if (summary.isEmpty) {
      _toast('注释不能为空');
      return null;
    }
    return DirectLinkRule(
      uploadUrl: uploadUrl,
      downloadUrlRule: downloadUrlRule,
      summary: summary,
      compress: _compress,
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _fillRule(DirectLinkRule rule) {
    setState(() {
      _uploadUrlCtl.text = rule.uploadUrl;
      _downloadRuleCtl.text = rule.downloadUrlRule;
      _summaryCtl.text = rule.summary;
      _compress = rule.compress;
    });
  }

  /// 导入默认规则（E: menu_import_default → selector(defaultRules)）
  Future<void> _importDefault() async {
    final picked = await showModalBottomSheet<DirectLinkRule>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('选择默认规则',
                  style: Theme.of(c).textTheme.titleMedium),
            ),
            for (final rule in DirectLinkUploadService.defaultRules)
              ListTile(
                dense: true,
                leading: const Icon(Icons.cloud_upload_outlined),
                title: Text(rule.summary),
                subtitle: Text(
                  '有效期：${rule.expiryDate == 0 ? '永久' : '${rule.expiryDate} 天'}',
                  style: const TextStyle(fontSize: 11),
                ),
                onTap: () => Navigator.pop(c, rule),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null) _fillRule(picked);
  }

  /// 复制规则 JSON（E: menu_copy_rule）
  void _copyRule() {
    final rule = _currentRule();
    if (rule == null) return;
    Clipboard.setData(ClipboardData(text: jsonEncode(rule.toJson())));
    _toast('已复制规则 JSON');
  }

  /// 粘贴规则 JSON（E: menu_paste_rule）
  Future<void> _pasteRule() async {
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clip?.text?.trim();
    if (text == null || text.isEmpty) {
      _toast('剪贴板为空或格式不对');
      return;
    }
    try {
      final rule = DirectLinkRule.fromJson(jsonDecode(text));
      if (rule == null) {
        _toast('剪贴板为空或格式不对');
        return;
      }
      _fillRule(rule);
    } catch (_) {
      _toast('剪贴板为空或格式不对');
    }
  }

  /// 测试上传 test.json（E: test()）
  Future<void> _test() async {
    final rule = _currentRule();
    if (rule == null) return;
    setState(() => _busy = true);
    try {
      final url = await DirectLinkUploadService.upLoad(
        'test.json',
        '{}',
        'application/json',
        rule: rule,
      );
      _showResult(url, error: false);
    } catch (e) {
      _showResult('$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showResult(String result, {required bool error}) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('result'),
        content: SelectableText(result),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: result)),
            child: const Text('复制'),
          ),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('确定')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('上传规则')),
          IconButton(
            tooltip: '导入默认规则',
            icon: const Icon(Icons.playlist_add),
            onPressed: _busy ? null : _importDefault,
          ),
          IconButton(
            tooltip: '复制规则',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: _busy ? null : _copyRule,
          ),
          IconButton(
            tooltip: '粘贴规则',
            icon: const Icon(Icons.content_paste),
            onPressed: _busy ? null : _pasteRule,
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _uploadUrlCtl,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: '上传Url',
                hintText: 'https://example.com/upload,{...}',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              minLines: 1,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _downloadRuleCtl,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: '下载Url规则',
                hintText: r'$.data@js:...',
                border: OutlineInputBorder(),
              ),
              maxLines: 4,
              minLines: 1,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _summaryCtl,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: '注释',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('上传前压缩为 zip'),
              value: _compress,
              onChanged: _busy ? null : (v) => setState(() => _compress = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: _busy ? null : _test,
          child: _busy
              ? const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('测试'),
        ),
        TextButton(
          onPressed: _busy
              ? null
              : () async {
                  final rule = _currentRule();
                  if (rule == null) return;
                  await DirectLinkUploadService.putConfig(rule);
                  if (!mounted) return;
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('上传规则已保存')),
                  );
                },
          child: const Text('确定'),
        ),
      ],
    );
  }
}
