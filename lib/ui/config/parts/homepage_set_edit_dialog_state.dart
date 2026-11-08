/// 由 homepage_module_screen.dart 按「一类一文件」拆出的 _HomepageSetEditDialogState。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../homepage_module_screen.dart';


class _HomepageSetEditDialogState extends State<_HomepageSetEditDialog> {
  late final TextEditingController _name;
  late final List<int> _selected;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.set?.name ?? '');
    final initial = HomepageSetStore.parseModuleIds(widget.set?.moduleIds);
    _selected = List<int>.from(initial);
    // 新建时默认纳入全部模块，便于立即看到效果
    if (widget.set == null) {
      for (final m in widget.modules) {
        if (m.id != null && !_selected.contains(m.id)) _selected.add(m.id!);
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.set == null ? '新建模块集' : '编辑模块集'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: '模块集名称'),
            ),
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('勾选纳入的模块（勾选顺序即首页展示顺序）',
                  style: TextStyle(fontSize: 11)),
            ),
            if (widget.modules.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('暂无可加入的模块', style: TextStyle(fontSize: 12)),
              )
            else
              ...widget.modules.map((m) {
                final id = m.id;
                return CheckboxListTile(
                  dense: true,
                  title: Text(m.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(homepageModuleTypeLabel(m.type),
                      style: const TextStyle(fontSize: 11)),
                  value: id != null && _selected.contains(id),
                  onChanged: id == null
                      ? null
                      : (v) => setState(() {
                            if (v == true) {
                              _selected.add(id);
                            } else {
                              _selected.remove(id);
                            }
                          }),
                );
              }),
          ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(context, _SetDraft(name, List<int>.from(_selected)));
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
