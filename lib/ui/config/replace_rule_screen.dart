import 'package:flutter/material.dart';
import 'package:legado_md3/data/model/replace_rule.dart';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';

class ReplaceRuleScreen extends StatefulWidget {
  const ReplaceRuleScreen({super.key});

  @override
  State<ReplaceRuleScreen> createState() => _ReplaceRuleScreenState();
}

class _ReplaceRuleScreenState extends State<ReplaceRuleScreen> {
  final DatabaseService _db = DatabaseService();
  List<ReplaceRule> _rules = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  Future<void> _onMenu(String v) async {
    if (v == 'net') {
      _importNetwork();
    } else if (v == 'local') {
      _importLocal();
    } else if (v == 'export') {
      _export();
    }
  }

  Future<void> _importNetwork() async {
    final ctl = TextEditingController();
    final url = await showDialog<String>(context: context, builder: (c) => AlertDialog(
      title: const Text('网络导入替换规则'),
      content: TextField(controller: ctl, decoration: const InputDecoration(hintText: '规则URL')),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(c, ctl.text), child: const Text('导入'))],
    ));
    if (url == null || url.isEmpty) return;
    try {
      final res = await Dio(BaseOptions(responseType: ResponseType.plain)).get<String>(url);
      final n = await _parseSave(res.data ?? '');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入 $n 条')));
      _loadRules();
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('失败: $e'))); }
  }

  Future<void> _importLocal() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json', 'txt']);
    if (r == null) return;
    final n = await _parseSave(await File(r.files.first.path!).readAsString());
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入 $n 条')));
    _loadRules();
  }

  Future<int> _parseSave(String raw) async {
    final data = jsonDecode(raw);
    final list = data is List ? data : [data];
    int n = 0;
    for (final m in list) {
      if (m is Map) {
        try { await _db.insertReplaceRule(ReplaceRule.fromMap(Map<String, dynamic>.from(m))); n++; } catch (_) {}
      }
    }
    return n;
  }

  Future<void> _export() async {
    final file = File('${Directory.systemTemp.path}/replace_rules.json');
    // 导出用  兼容字段（name/pattern/scopeTitle/excludeScope/...），
    // 保证跨端备份与 Web 端导入不丢字段；fromMap 同时兼容本项目历史字段。
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(_rules.map((e) => e.toLegadoJson()).toList()));
    await Share.shareXFiles([XFile(file.path)], text: '替换规则导出');
  }

  Future<void> _loadRules() async {
    setState(() => _isLoading = true);
    _rules = await _db.getReplaceRules();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _toggleRule(ReplaceRule rule, bool enabled) async {
    rule.enable = enabled;
    await _db.updateReplaceRule(rule);
    setState(() {});
  }

  Future<void> _deleteRule(ReplaceRule rule) async {
    if (rule.id != null) {
      await _db.deleteReplaceRule(rule.id!);
      _loadRules();
    }
  }

  void _showEditDialog({ReplaceRule? rule}) {
    final summaryController = TextEditingController(text: rule?.replaceSummary ?? '');
    final regexController = TextEditingController(text: rule?.replaceRule ?? '');
    final replacementController = TextEditingController(text: rule?.replacement ?? '');
    final scopeController = TextEditingController(text: rule?.scope ?? '');
    final excludeController = TextEditingController(text: rule?.excludeScope ?? '');
    final groupController = TextEditingController(text: rule?.group ?? '');
    final timeoutController =
        TextEditingController(text: (rule?.timeoutMillisecond ?? 3000).toString());

    bool isTitle = rule?.isTitle ?? false;
    bool isContent = rule?.isContent ?? true;
    bool isRegex = rule?.isRegex ?? true;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
        title: Text(rule == null ? '新建替换规则' : '编辑替换规则'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: summaryController,
                decoration: const InputDecoration(labelText: '规则说明'),
              ),
              const SizedBox(height: AppSpacing.m),
              TextField(
                controller: regexController,
                decoration: const InputDecoration(labelText: '匹配规则(正则或关键词)'),
              ),
              const SizedBox(height: AppSpacing.m),
              TextField(
                controller: replacementController,
                decoration: const InputDecoration(labelText: '替换为(留空表示删除)'),
              ),
              const SizedBox(height: AppSpacing.s),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero, dense: true,
                title: const Text('作用于标题'), value: isTitle,
                onChanged: (v) => setDialogState(() => isTitle = v ?? false),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero, dense: true,
                title: const Text('作用于正文'), value: isContent,
                onChanged: (v) => setDialogState(() => isContent = v ?? true),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero, dense: true,
                title: const Text('使用正则表达式'), value: isRegex,
                onChanged: (v) => setDialogState(() => isRegex = v ?? true),
              ),
              const SizedBox(height: AppSpacing.s),
              TextField(
                controller: scopeController,
                decoration: const InputDecoration(labelText: '作用范围(书名或书源，留空为全部)'),
              ),
              const SizedBox(height: AppSpacing.s),
              TextField(
                controller: excludeController,
                decoration: const InputDecoration(labelText: '排除范围(书名或书源，命中则跳过本规则)'),
              ),
              const SizedBox(height: AppSpacing.s),
              TextField(
                controller: groupController,
                decoration: const InputDecoration(labelText: '分组(便于归类管理)'),
              ),
              const SizedBox(height: AppSpacing.s),
              TextField(
                controller: timeoutController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '正则超时(毫秒，默认 3000)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final newRule = ReplaceRule(
                id: rule?.id,
                replaceSummary: summaryController.text,
                replaceRule: regexController.text,
                replacement: replacementController.text,
                scope: scopeController.text.trim().isEmpty ? null : scopeController.text.trim(),
                excludeScope: excludeController.text.trim().isEmpty ? null : excludeController.text.trim(),
                group: groupController.text.trim().isEmpty ? null : groupController.text.trim(),
                timeoutMillisecond: int.tryParse(timeoutController.text.trim()) ?? 3000,
                order: rule?.order,
                enable: rule?.enable ?? true,
                isTitle: isTitle,
                isContent: isContent,
                isRegex: isRegex,
              );
              if (rule == null) {
                await _db.insertReplaceRule(newRule);
              } else {
                await _db.updateReplaceRule(newRule);
              }
              if (mounted && context.mounted) Navigator.pop(context);
              _loadRules();
            },
            child: const Text('保存'),
          ),
        ],
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('替换净化 (${_rules.length})'),
        actions: [
          IconButton(
            tooltip: '帮助',
            icon: const Icon(Icons.help_outline),
            onPressed: () => _showHelp(),
          ),
          PopupMenuButton<String>(tooltip: '更多', onSelected: _onMenu, itemBuilder: (_) => const [
            PopupMenuItem(value: 'net', child: Text('网络导入')),
            PopupMenuItem(value: 'local', child: Text('本地导入')),
            PopupMenuItem(value: 'export', child: Text('导出')),
          ]),
        ],
      ),
      // 三态统一收敛到 AppAsyncState；空态动作直接声明，不再单独维护方法。
      body: AppAsyncState(
        loading: _isLoading,
        isEmpty: _rules.isEmpty,
        emptyIcon: Icons.find_replace_outlined,
        emptyTitle: '暂无替换规则',
        emptyMessage: '点击右下角添加规则',
        emptyAction: FilledButton.icon(
          onPressed: () => _showEditDialog(),
          icon: const Icon(Icons.add),
          label: const Text('添加规则'),
        ),
        child: ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.l),
                  itemCount: _rules.length,
                  separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.s),
                  itemBuilder: (context, index) {
                    final rule = _rules[index];
                    return Card(
                      child: ListTile(
                        title: Text(rule.displayNameWithGroup, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(rule.replaceRule, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                            if (rule.scope != null) Text('范围: ${rule.scope}', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.primary)),
                            if (rule.excludeScope != null) Text('排除: ${rule.excludeScope}', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.error)),
                          ],
                        ),
                        trailing: Switch(
                          value: rule.enable == true,
                          onChanged: (v) => _toggleRule(rule, v),
                        ),
                        onTap: () => _showEditDialog(rule: rule),
                        onLongPress: () => _showDeleteConfirm(rule),
                      ),
                    );
                  },
                ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showEditDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _showDeleteConfirm(ReplaceRule rule) async {
    final ok = await showAppConfirmDialog(
      context,
      title: '删除规则',
      content: '确定要删除"${rule.replaceSummary}"吗？',
      confirmText: '删除',
      danger: true,
    );
    if (ok) _deleteRule(rule);
  }

  void _showHelp() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('替换净化说明'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('替换净化可以去除书籍内容里的广告、错别字、屏蔽词等。'),
              SizedBox(height: AppSpacing.s),
              Text('规则说明：', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('• 替换规则：支持正则表达式'),
              Text('• 替换为：替换后的内容，留空表示删除'),
              Text('• 作用范围：指定书源URL，留空表示对所有书源生效'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('知道了')),
        ],
      ),
    );
  }
}
