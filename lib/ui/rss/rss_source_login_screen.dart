import 'dart:convert';
import 'package:flutter/material.dart';

import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/rss_source.dart';
import 'package:legado_md3/help/source/js/legado_js_runtime.dart';
import 'package:legado_md3/ui/browser/browser_screen.dart';

/// 订阅源登录页：对齐 legado 的 loginUi / loginUrl 机制（与书源登录页一致）。
class RssSourceLoginScreen extends StatefulWidget {
  const RssSourceLoginScreen({super.key, required this.source});
  final RssSource source;

  @override
  State<RssSourceLoginScreen> createState() => _RssSourceLoginScreenState();
}

class _RssSourceLoginScreenState extends State<RssSourceLoginScreen> {
  final DatabaseService _db = DatabaseService();
  final Map<String, TextEditingController> _controllers = {};
  final List<Map<String, dynamic>> _buttons = [];
  final List<Widget> _fields = [];
  final List<String> _logs = [];
  bool _busy = false;
  late RssSource source;

  @override
  void initState() {
    super.initState();
    source = widget.source;
    _buildUi();
  }

  void _buildUi() {
    final loginUrl = (source.loginUrl ?? '').trim();
    if (loginUrl.startsWith('http://') || loginUrl.startsWith('https://')) {
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _openWebLogin(loginUrl));
      return;
    }
    final uiText = (source.loginUi ?? '').trim();
    List<dynamic> items = [];
    if (uiText.isNotEmpty) {
      try {
        final decoded = jsonDecode(uiText);
        if (decoded is List) items = decoded;
      } catch (_) {
        items = [];
      }
    }
    if (items.isEmpty) {
      items = [
        {'name': '用户名', 'type': 'text'},
        {'name': '密码', 'type': 'password'},
        {'name': '登录', 'type': 'button', 'action': 'login(true)'},
      ];
    }

    for (final raw in items) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      final name = item['name']?.toString() ?? '';
      final type = item['type']?.toString() ?? 'text';
      if (type == 'button') {
        _buttons.add(item);
      } else if (type == 'text' || type == 'password' || type.isEmpty) {
        final c = TextEditingController();
        _controllers[name] = c;
        _fields.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: TextField(
            controller: c,
            obscureText: type == 'password',
            decoration: InputDecoration(
              labelText: name,
              border: const OutlineInputBorder(),
              prefixIcon: Icon(type == 'password'
                  ? Icons.lock_outline
                  : Icons.person_outline),
            ),
          ),
        ));
      }
    }
  }

  Map<String, dynamic> get _form {
    final m = <String, dynamic>{};
    _controllers.forEach((k, c) => m[k] = c.text);
    return m;
  }

  Future<void> _openWebLogin(String url) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BrowserScreen(url: url, title: '登录 - ${source.sourceName}'),
    ));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('网页登录结束，已尝试回收 Cookie')),
      );
    }
  }

  Future<void> _runAction(String action) async {
    final act = action.trim();
    if (act.isEmpty) return;
    setState(() => _busy = true);
    _appendLog('执行: $act');
    try {
      final rt = await JsRuntimeManager.instance.forSource(source);
      final res = await rt.eval(JsEvalRequest(
        source: source,
        script: act,
        result: _form,
        baseUrl: source.jsHttpUrl,
      ));
      for (final t in res.toasts) {
        _appendLog(t);
      }
      for (final l in res.logs) {
        _appendLog(l);
      }
      if (res.error != null && res.error!.isNotEmpty) {
        _appendLog('异常: ${res.error!.split('\n').first}');
      }
      await _db.updateRssSource(source);
      if (mounted) {
        final lastToast = res.toasts.isNotEmpty ? res.toasts.last : null;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(lastToast ?? '操作已完成'),
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (e) {
      _appendLog('运行失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _appendLog(String s) {
    final line = s.trim();
    if (line.isEmpty) return;
    setState(() {
      _logs.add(line);
      if (_logs.length > 200) _logs.removeRange(0, _logs.length - 200);
    });
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loginUrl = (source.loginUrl ?? '').trim();
    final isWeb = loginUrl.startsWith('http');
    return Scaffold(
      appBar: AppBar(
        title: Text('登录 - ${source.sourceName}',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: '重新载入',
            icon: const Icon(Icons.refresh),
            onPressed: _busy
                ? null
                : () async {
                    await JsRuntimeManager.instance
                        .invalidate(source.sourceUrl);
                    if (mounted) setState(() => _logs.clear());
                  },
          ),
        ],
      ),
      body: isWeb
          ? Center(
              child: FilledButton.icon(
                icon: const Icon(Icons.open_in_browser),
                label: const Text('打开网页登录'),
                onPressed: () => _openWebLogin(loginUrl),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if ((source.sourceComment ?? '').trim().isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(source.sourceComment!,
                        style: const TextStyle(fontSize: 12)),
                  ),
                ..._fields,
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final b in _buttons)
                      _RssLoginButton(
                        label: b['name']?.toString() ?? '按钮',
                        busy: _busy,
                        onPressed: () =>
                            _runAction(b['action']?.toString() ?? ''),
                      ),
                  ],
                ),
                const Divider(height: 32),
                if (_logs.isNotEmpty) ...[
                  const Text('运行日志',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      _logs.join('\n'),
                      style: const TextStyle(
                          fontSize: 11, fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _RssLoginButton extends StatelessWidget {
  const _RssLoginButton(
      {required this.label, required this.onPressed, this.busy = false});
  final String label;
  final VoidCallback onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final isPrimary = label.contains('登录') &&
        !label.contains('退出') &&
        !label.contains('注册');
    return isPrimary
        ? FilledButton(
            onPressed: busy ? null : onPressed, child: Text(label))
        : OutlinedButton(
            onPressed: busy ? null : onPressed, child: Text(label));
  }
}
