import 'package:flutter/material.dart';
import 'package:legado_md3/help/ai/ai_chat_service.dart';

/// AI 聊天页：消息气泡 + 快捷提问 + 接口设置
class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final AiChatService _service = AiChatService();
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<AiMessage> _messages = [];
  bool _sending = false;
  bool _loading = true;

  static const _quickPrompts = ['帮我总结这一章', '梳理人物关系', '解释这段话的含义', '这本书讲了什么'];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _service.load();
    if (!mounted) return;
    setState(() {
      _messages.add(AiMessage(
        'assistant',
        _service.isConfigured
            ? '你好，我是读书助手，可以帮你总结章节、梳理人物、解释词义。输入内容开始对话吧。'
            : '你好，当前为离线模式。点右上角设置填入 OpenAI 兼容接口即可联网，也可以直接问我基础问题。',
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
    setState(() {
      _messages.add(AiMessage('user', text));
      _sending = true;
      _input.clear();
    });
    _scrollToBottom();
    final history = List<AiMessage>.from(_messages.where((m) => m.role != 'system'));
    final reply = await _service.send(text, history);
    if (!mounted) return;
    setState(() {
      _messages.add(AiMessage('assistant', reply));
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
              const SizedBox(height: 8),
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
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (!_service.isConfigured)
                  Container(
                    width: double.infinity,
                    color: theme.colorScheme.secondaryContainer,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Text('离线模式：点右上角设置配置接口以获得完整能力', style: theme.textTheme.bodySmall),
                  ),
                Expanded(
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length + (_sending ? 1 : 0),
                    itemBuilder: (ctx, i) {
                      if (i == _messages.length) {
                        return const Padding(
                          padding: EdgeInsets.all(8),
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
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    children: [
                      for (final p in _quickPrompts)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ActionChip(label: Text(p), onPressed: _sending ? null : () => _send(p)),
                        ),
                    ],
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _input,
                            minLines: 1,
                            maxLines: 4,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _send(),
                            decoration: const InputDecoration(hintText: '输入消息…', border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                          ),
                        ),
                        const SizedBox(width: 8),
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
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: isUser ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: SelectableText(m.content, style: const TextStyle(height: 1.4)),
      ),
    );
  }
}
