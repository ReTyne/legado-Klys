import 'package:flutter/material.dart';

import 'package:legado_md3/data/model/v14_models.dart';
import 'package:legado_md3/help/ai/agent_tool_runtime.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';

/// AI Agent 工具启停管理页：工具注册表来自 `ai_agent_tools`（v14），
/// 启停状态直接决定聊天页 LLM 可用的 `tools` 集合与离线意图分发。
class AgentToolScreen extends StatefulWidget {
  const AgentToolScreen({super.key});

  @override
  State<AgentToolScreen> createState() => _AgentToolScreenState();
}

class _AgentToolScreenState extends State<AgentToolScreen> {
  final AgentToolRegistry _registry = AgentToolRegistry();
  List<AiAgentTool> _tools = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _registry.ensureDefaults();
    final list = await _registry.tools();
    if (!mounted) return;
    setState(() {
      _tools = list;
      _loading = false;
    });
  }

  Future<void> _toggle(AiAgentTool t, bool enabled) async {
    await _registry.setEnabled(t, enabled);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${t.name} 已${enabled ? '启用' : '停用'}'),
    ));
  }

  Future<void> _delete(AiAgentTool t) async {
    final ok = await showAppConfirmDialog(
      context,
      title: '删除工具「${t.name}」',
      content: '删除后该工具不再注册给模型；内置工具可通过右上角「恢复内置」重新写入。',
      confirmText: '删除',
      danger: true,
    );
    if (!ok) return;
    final id = t.id;
    if (id != null) await _registry.remove(id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabledCount = _tools.where((t) => t.enabled == 1).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Agent 工具'),
        actions: [
          IconButton(
            icon: const Icon(Icons.restore_outlined),
            tooltip: '恢复内置工具',
            onPressed: () async {
              await _registry.ensureDefaults();
              await _load();
            },
          ),
        ],
      ),
      body: _loading
          ? const AppLoadingIndicator()
          : ListView(
              padding: const EdgeInsets.only(bottom: AppSpacing.xl),
              children: [
                AppSectionHeader('已启用 $enabledCount / ${_tools.length}'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
                  child: Text(
                    '聊天时模型可自动调用已启用的工具（OpenAI tool_calls 多轮回填）；'
                    '未配置 AI 接口时，工具也会按对话意图在离线模式下直接执行。',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                  ),
                ),
                if (_tools.isEmpty)
                  const AppEmptyState(
                    icon: Icons.build_outlined,
                    title: '暂无工具',
                    message: '点右上角恢复内置工具',
                  )
                else
                  for (final t in _tools)
                    Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.l, vertical: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SwitchListTile(
                            title: Text(t.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              t.description,
                              style: TextStyle(
                                  color: cs.onSurfaceVariant, fontSize: 12),
                            ),
                            value: t.enabled == 1,
                            onChanged: (v) => _toggle(t, v),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(AppSpacing.l, 0, AppSpacing.s, AppSpacing.s),
                            child: Row(
                              children: [
                                Icon(Icons.code_outlined,
                                    size: 14, color: cs.onSurfaceVariant),
                                const SizedBox(width: AppSpacing.xs),
                                Expanded(
                                  child: Text('handler: ${t.handler}',
                                      style: TextStyle(
                                          color: cs.onSurfaceVariant,
                                          fontSize: 11)),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  tooltip: '删除该工具',
                                  onPressed: () => _delete(t),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
    );
  }
}
