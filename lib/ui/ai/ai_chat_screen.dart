import 'package:flutter/material.dart';

import 'package:legado_md3/help/ai/agent_tool_runtime.dart';
import 'package:legado_md3/help/ai/ai_chat_service.dart';
import 'package:legado_md3/ui/ai/agent_tool_screen.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';

/// AI 聊天页：消息气泡 + 快捷提问 + 接口设置 + Agent 工具调用（多轮回填）。
///
/// 对话走 [AgentToolRuntime]：与 [AiChatService] 共用同一套 OpenAI 兼容配置键，
/// 额外注册 `ai_agent_tools` 表中的工具并在模型返回 `tool_calls` 时执行回填。
class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final AiChatService _service = AiChatService();
  final AgentToolRegistry _registry = AgentToolRegistry();
  late final AgentToolRuntime _runtime;
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<AiMessage> _messages = [];
  bool _sending = false;
  bool _loading = true;

  static const _quickPrompts = ['帮我总结这一章', '梳理人物关系', '解释这段话的含义', '这本书讲了什么'];

  @override
  void initState() {
    super.initState();
    _runtime = AgentToolRuntime(_registry);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _service.load();
    await _registry.ensureDefaults();
    if (!mounted) return;
    final tools = await _registry.tools(onlyEnabled: true);
    if (!mounted) return;
    setState(() {
      _messages.add(AiMessage(
        'assistant',
        _service.isConfigured
            ? '你好，我是读书助手，已启用 ${tools.length} 个 Agent 工具，可自动查书架/目录/章节/书源。输入内容开始对话吧。'
            : '你好，当前为离线工具模式（已启用 ${tools.length} 个工具）。可直接说「搜索 xx」「《书名》的目录」「列出书源」；点右上角设置填入接口即可由模型自动调用工具。',
      ));
      _loading = false;
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _sending) return;
    // 历史不含本次用户消息（运行时会自行追加），也不含 tool 过程气泡
    final history = _messages
        .where((m) => m.role == 'user' || m.role == 'assistant')
        .map((m) => (role: m.role, content: m.content))
        .toList();
    setState(() {
      _messages.add(AiMessage('user', text));
      _sending = true;
      _input.clear();
    });
    _scrollToBottom();
    final reply = await _runtime.chat(text, history);
    if (!mounted) return;
    setState(() {
      for (final l in reply.toolLog) {
        _messages.add(AiMessage('tool', '【工具调用】$l'));
      }
      _messages.add(AiMessage('assistant', reply.text));
      _sending = false;
    });
    _scrollToBottom();
  }

  Future<void> _openSettings() async {
    final baseUrlCtrl = TextEditingController(text: _service.baseUrl ?? '');
    final keyCtrl = TextEditingController(text: _service.apiKey ?? '');
    final modelCtrl = TextEditingController(text: _service.model);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('AI 设置'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: baseUrlCtrl,
                decoration: const InputDecoration(labelText: 'BaseUrl', hintText: '如 https://api.openai.com'),
              ),
              TextField(
                controller: keyCtrl,
                decoration: const InputDecoration(labelText: 'API Key'),
                obscureText: false,
              ),
              TextField(
                controller: modelCtrl,
                decoration: const InputDecoration(labelText: '模型', hintText: 'gpt-4o-mini'),
              ),
              const SizedBox(height: AppSpacing.s),
              const Text('留空 BaseUrl 则使用内置离线助手；接口需兼容 /v1/chat/completions。', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              await _service.saveConfig(
                baseUrl: baseUrlCtrl.text,
                apiKey: keyCtrl.text,
                model: modelCtrl.text,
              );
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) setState(() {});
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 聊天'),
        actions: [
          IconButton(
            icon: const Icon(Icons.build_outlined),
            tooltip: 'Agent 工具管理',
            onPressed: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const AgentToolScreen()));
              if (mounted) setState(() {});
            },
          ),
          IconButton(icon: const Icon(Icons.settings_outlined), tooltip: 'AI 设置', onPressed: _openSettings),
          if (_messages.length > 1)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '清空对话',
              onPressed: () => setState(() => _messages.removeWhere((m) => m.role != 'system')),
            ),
        ],
      ),
      body: _loading
          ? const AppLoadingIndicator()
          : Column(
              children: [
                if (!_service.isConfigured)
                  Container(
                    width: double.infinity,
                    color: theme.colorScheme.secondaryContainer,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l, vertical: 6),
                    child: Text('离线工具模式：工具可直接使用；配置接口后模型可自动调用工具', style: theme.textTheme.bodySmall),
                  ),
                Expanded(
                  child: _messages.isEmpty && !_sending
                      ? const AppEmptyState(
                          icon: Icons.chat_bubble_outline,
                          title: '开始对话',
                          message: '输入内容，或点击上方快捷提问',
                        )
                      : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(AppSpacing.m),
                    itemCount: _messages.length + (_sending ? 1 : 0),
                    itemBuilder: (ctx, i) {
                      if (i == _messages.length) {
                        return const Padding(
                          padding: EdgeInsets.all(AppSpacing.s),
                          child: Align(alignment: Alignment.centerLeft, child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
                        );
                      }
                      return _bubble(_messages[i], theme);
                    },
                  ),
                ),
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
                    children: [
                      for (final p in _quickPrompts)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                          child: ActionChip(label: Text(p), onPressed: _sending ? null : () => _send(p)),
                        ),
                    ],
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.m, 6, AppSpacing.m, AppSpacing.s),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _input,
                            minLines: 1,
                            maxLines: 4,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _send(),
                            decoration: const InputDecoration(hintText: '输入消息…', border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.m, vertical: 10)),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.s),
                        IconButton.filled(
                          icon: const Icon(Icons.send),
                          onPressed: _sending ? null : () => _send(),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _bubble(AiMessage m, ThemeData theme) {
    final isUser = m.role == 'user';
    final isTool = m.role == 'tool';
    final cs = theme.colorScheme;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m, vertical: 9),
        decoration: BoxDecoration(
          color: isUser
              ? cs.primaryContainer
              : isTool
                  ? cs.secondaryContainer
                  : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: SelectableText(
          m.content,
          style: TextStyle(
            height: 1.4,
            fontSize: isTool ? 12 : null,
            color: isTool ? cs.onSecondaryContainer : null,
          ),
        ),
      ),
    );
  }
}
