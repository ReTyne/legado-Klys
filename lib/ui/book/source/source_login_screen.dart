import 'dart:convert';
import 'package:flutter/material.dart';

import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/help/source/js/legado_js_runtime.dart';
import 'package:legado_md3/help/source/source_engine.dart';
import 'package:legado_md3/ui/browser/browser_screen.dart';

/// 书源登录页：对齐 legado 的 loginUi / loginUrl 机制。
///
/// * loginUrl 为 http(s)：直接打开网页登录，回收 Cookie。
/// * loginUrl 为 <js>/JS：按 loginUi 渲染 text/password/button/switch/select，
///   loginUrl 先求值（定义 login()/register() 等全局函数），按钮 action 再求值；
///   result 为「字段名 -> 值」的对象，登录信息经 putLoginInfo 持久化。
/// * 无 loginUi：回退为账号/密码表单，写入书源变量。
/// * 页面加载时执行书源 loginCheckJs，展示「已登录/未登录」状态。
class SourceLoginScreen extends StatefulWidget {
  const SourceLoginScreen({super.key, required this.source});
  final BookSource source;

  @override
  State<SourceLoginScreen> createState() => _SourceLoginScreenState();
}

class _SourceLoginScreenState extends State<SourceLoginScreen> {
  final DatabaseService _db = DatabaseService();
  final BookSourceEngine _engine = BookSourceEngine();
  final Map<String, TextEditingController> _controllers = {};
  // switch 开关控件的勾选值（字段名 -> bool）
  final Map<String, bool> _switchValues = {};
  // select 下拉控件的选中值（字段名 -> 选项 value）
  final Map<String, String> _selectValues = {};
  final List<Map<String, dynamic>> _buttons = [];
  final List<Widget> _fields = [];
  final List<String> _logs = [];
  bool _busy = false;
  // loginCheckJs 登录状态检测：null=未配置/未知，true=已登录，false=未登录
  bool _checkingLogin = false;
  bool? _loggedIn;

  late BookSource source;

  @override
  void initState() {
    super.initState();
    source = widget.source;
    _buildUi();
    // 页面加载时检测登录状态（loginCheckJs）
    _checkLoginStatus();
  }

  /// 调用书源 loginCheckJs 检测登录状态并刷新界面提示
  Future<void> _checkLoginStatus() async {
    // 未配置 loginCheckJs 时不显示状态
    if ((source.loginCheckJs ?? '').trim().isEmpty) return;
    if (mounted) setState(() => _checkingLogin = true);
    var ok = false;
    try {
      ok = await _engine.checkLogin(source);
    } catch (_) {
      ok = false;
    }
    if (mounted) setState(() { _loggedIn = ok; _checkingLogin = false; });
  }

  void _buildUi() {
    final loginUrl = (source.loginUrl ?? '').trim();
    // URL 型登录：交给网页
    if (loginUrl.startsWith('http://') || loginUrl.startsWith('https://')) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openWebLogin(loginUrl));
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
      // 回退：账号/密码
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
      } else if (type == 'switch') {
        // switch 开关控件：值以 bool 形式参与表单提交
        final name0 = name.isEmpty ? '开关' : name;
        final value = _switchValues[name0] ?? false;
        _switchValues[name0] = value;
        _fields.add(SwitchListTile(
          title: Text(name0),
          value: value,
          contentPadding: EdgeInsets.zero,
          onChanged: (v) => setState(() => _switchValues[name0] = v),
        ));
      } else if (type == 'select') {
        // select 下拉控件：options 支持字符串数组或 [{name, value}] 对象数组
        final name0 = name.isEmpty ? '请选择' : name;
        final options = _parseSelectOptions(item['options']);
        if (options.isNotEmpty) {
          final current = _selectValues[name0] ?? options.first['value']!;
          _selectValues[name0] = current;
          _fields.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: DropdownButtonFormField<String>(
              value: current,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: name0,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.arrow_drop_down_circle_outlined),
              ),
              items: options
                  .map((o) => DropdownMenuItem(
                        value: o['value'],
                        child: Text(o['name'] ?? o['value'] ?? ''),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _selectValues[name0] = v);
              },
            ),
          ));
        }
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

  /// 表单值：文本框 + switch + select 的当前值，作为 JS action 的 result
  Map<String, dynamic> get _form {
    final m = <String, dynamic>{};
    _controllers.forEach((k, c) => m[k] = c.text);
    m.addAll(_switchValues);
    m.addAll(_selectValues);
    return m;
  }

  /// 解析 select 控件的 options：支持字符串数组或 [{name, value}] 对象数组
  List<Map<String, String>> _parseSelectOptions(dynamic raw) {
    final out = <Map<String, String>>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is String) {
          if (e.isNotEmpty) out.add({'name': e, 'value': e});
        } else if (e is Map) {
          final name = (e['name'] ?? e['value'] ?? '').toString();
          final value = (e['value'] ?? e['name'] ?? '').toString();
          if (name.isNotEmpty || value.isNotEmpty) {
            out.add({'name': name, 'value': value});
          }
        }
      }
    }
    return out;
  }

  Future<void> _openWebLogin(String url) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BrowserScreen(url: url, title: '登录 - ${source.bookSourceName}'),
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
      // 登录按钮以表单对象作为 result
      final res = await rt.eval(JsEvalRequest(
        source: source,
        script: act,
        result: _form,
        baseUrl: source.bookSourceUrl.startsWith('http')
            ? source.bookSourceUrl
            : '',
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
      // variable 在求值过程中可能被 setVariable 更新，落库
      await _db.updateSource(source);
      // 登录动作可能改变登录状态，重新检测 loginCheckJs
      await _checkLoginStatus();
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

  /// 登录状态横幅：展示 loginCheckJs 检测结果（已登录/未登录），支持手动刷新
  Widget _loginStatusBanner() {
    // 未配置 loginCheckJs 时不展示
    if ((source.loginCheckJs ?? '').trim().isEmpty) return const SizedBox.shrink();
    final ok = _loggedIn == true;
    final color = _checkingLogin
        ? Colors.grey
        : (ok ? const Color(0xFF2E7D32) : const Color(0xFFEF6C00));
    final text = _checkingLogin ? '正在检测登录状态…' : (ok ? '已登录' : '未登录');
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          _checkingLogin
              ? Icons.hourglass_empty
              : (ok ? Icons.verified_user : Icons.error_outline),
          color: color,
        ),
        title: Text(
          '登录状态：$text',
          style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13),
        ),
        subtitle: const Text('由 loginCheckJs 检测', style: TextStyle(fontSize: 11)),
        trailing: IconButton(
          tooltip: '重新检测',
          icon: const Icon(Icons.refresh, size: 20),
          onPressed: _checkingLogin ? null : _checkLoginStatus,
        ),
      ),
    );
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
        title: Text('登录 - ${source.bookSourceName}', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: '重新载入',
            icon: const Icon(Icons.refresh),
            onPressed: _busy ? null : () async {
              await JsRuntimeManager.instance.invalidate(source.bookSourceUrl);
              if (mounted) setState(() => _logs.clear());
            },
          ),
        ],
      ),
      body: isWeb
          ? Column(
              children: [
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _loginStatusBanner(),
                ),
                Expanded(
                  child: Center(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.open_in_browser),
                      label: const Text('打开网页登录'),
                      onPressed: () => _openWebLogin(loginUrl),
                    ),
                  ),
                ),
              ],
            )
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // 登录状态检测横幅（loginCheckJs）
                      _loginStatusBanner(),
                      if ((source.bookSourceComment ?? '').trim().isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            source.bookSourceComment!,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ..._fields,
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final b in _buttons)
                            _LoginButton(
                              label: b['name']?.toString() ?? '按钮',
                              busy: _busy,
                              onPressed: () =>
                                  _runAction(b['action']?.toString() ?? ''),
                            ),
                        ],
                      ),
                      const Divider(height: 32),
                      if (_logs.isNotEmpty) ...[
                        const Text('运行日志', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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
                ),
              ],
            ),
    );
  }
}

class _LoginButton extends StatelessWidget {
  const _LoginButton({required this.label, required this.onPressed, this.busy = false});
  final String label;
  final VoidCallback onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final isPrimary = label.contains('登录') && !label.contains('退出') && !label.contains('注册');
    final child = Text(label);
    return isPrimary
        ? FilledButton(onPressed: busy ? null : onPressed, child: child)
        : OutlinedButton(onPressed: busy ? null : onPressed, child: child);
  }
}
