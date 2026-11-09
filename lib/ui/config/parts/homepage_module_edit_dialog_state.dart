/// 由 homepage_module_screen.dart 按「一类一文件」拆出的 _HomepageModuleEditDialogState。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../homepage_module_screen.dart';


class _HomepageModuleEditDialogState
    extends State<_HomepageModuleEditDialog> {
  late final TextEditingController _name;
  late final TextEditingController _sourceUrl;
  late final TextEditingController _exploreUrl;
  late final TextEditingController _config;
  late HomepageModuleType _type;
  late bool _enabled;

  static const String _sampleConfig = '{\n'
      '  "title": "示例模块",\n'
      '  "items": [\n'
      '    {"title": "搜索", "subtitle": "点击搜索书籍", "action": "search", "keyword": "斗破苍穹"},\n'
      '    {"title": "发现", "subtitle": "打开书源发现", "action": "explore", "sourceUrl": "", "exploreUrl": ""},\n'
      '    {"title": "书籍", "subtitle": "打开书籍详情", "action": "book", "bookName": "示例书名", "bookAuthor": "作者"}\n'
      '  ]\n'
      '}';

  @override
  void initState() {
    super.initState();
    final m = widget.module;
    _name = TextEditingController(text: m?.name ?? '');
    _sourceUrl = TextEditingController(text: m?.sourceUrl ?? '');
    _exploreUrl = TextEditingController(text: m?.exploreUrl ?? '');
    _config = TextEditingController(text: m?.config ?? '');
    _type = m?.type ?? HomepageModuleType.card;
    _enabled = m?.enabled ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _sourceUrl.dispose();
    _exploreUrl.dispose();
    _config.dispose();
    super.dispose();
  }

  Future<void> _pickType() async {
    final v = await showAppRadioDialog<HomepageModuleType>(
      context,
      title: '模块类型',
      groupValue: _type,
      options: [
        for (final t in HomepageModuleType.values)
          AppRadioOption<HomepageModuleType>(t, homepageModuleTypeLabel(t)),
      ],
    );
    if (v != null) setState(() => _type = v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.module == null ? '新增首页模块' : '编辑首页模块'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: '模块名称'),
            ),
            const SizedBox(height: AppSpacing.s),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('模块类型'),
              subtitle: Text(homepageModuleTypeLabel(_type)),
              trailing: const Icon(Icons.arrow_drop_down),
              onTap: _pickType,
            ),
            TextField(
              controller: _sourceUrl,
              decoration:
                  const InputDecoration(labelText: '关联书源 URL（可选）'),
            ),
            const SizedBox(height: AppSpacing.s),
            TextField(
              controller: _exploreUrl,
              decoration: const InputDecoration(labelText: '发现 URL（可选）'),
            ),
            const SizedBox(height: AppSpacing.s),
            TextField(
              controller: _config,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: '卡片配置 JSON（可选）',
                helperText: '留空则用关联书源 + 发现地址拉取真实书籍',
                helperMaxLines: 2,
                border: OutlineInputBorder(),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _config.text = _sampleConfig),
                icon: const Icon(Icons.data_object_outlined, size: 16),
                label: const Text('插入示例卡片配置'),
              ),
            ),
            AppSwitchTile(
              title: '启用模块',
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
            if (name.isEmpty) return;
            Navigator.pop(
              context,
              HomepageModule(
                id: widget.module?.id,
                name: name,
                type: _type,
                sourceUrl: _sourceUrl.text.trim().isEmpty
                    ? null
                    : _sourceUrl.text.trim(),
                exploreUrl: _exploreUrl.text.trim().isEmpty
                    ? null
                    : _exploreUrl.text.trim(),
                config: _config.text.trim().isEmpty
                    ? null
                    : _config.text.trim(),
                customOrder: widget.module?.customOrder ?? widget.defaultOrder,
                enabled: _enabled,
              ),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
