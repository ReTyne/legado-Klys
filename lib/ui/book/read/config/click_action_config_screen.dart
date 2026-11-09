/// 由 reading_settings_screen.dart 拆分还原（历史合并点）。
/// 以 part 形式归属同一库，私有成员互通，外部 import 路径不变。
part of 'reading_settings_screen.dart';


/// 9 区点击动作配置，对齐原版 ClickActionConfigSheet
/// 屏幕划分为 3x3 九个区域，每个区域可绑定一个动作
class ClickActionConfigScreen extends StatefulWidget {
  const ClickActionConfigScreen({super.key});

  @override
  State<ClickActionConfigScreen> createState() => _ClickActionConfigScreenState();
}

class _ClickActionConfigScreenState extends State<ClickActionConfigScreen> {
  // 动作（向后兼容 0-5，新增 6-14 对齐 legado 九宫格）
  // 0无 1上一章 2下一章 3菜单 4上一页 5下一页 6目录 7全文搜索 8朗读 9加书签 10编辑正文 11书签列表 12同步进度 13朗读暂停恢复 14切换净化
  static const actions = ['无动作', '上一章', '下一章', '显示菜单', '上一页', '下一页', '目录', '全文搜索', '朗读', '添加书签', '编辑正文', '书签列表', '同步进度', '朗读暂停/恢复', '切换净化'];
  static const icons = [
    Icons.remove_circle_outline,
    Icons.skip_previous,
    Icons.skip_next,
    Icons.menu_book,
    Icons.chevron_left,
    Icons.chevron_right,
    Icons.list_alt,
    Icons.search,
    Icons.headphones,
    Icons.bookmark_border,
    Icons.edit_note,
    Icons.bookmarks,
    Icons.sync,
    Icons.pause_circle_outline,
    Icons.cleaning_services_outlined,
  ];
  List<int> _grid = List.filled(9, 2);

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('click_actions');
    setState(() {
      if (raw != null) {
        final parts = raw.split(',').map((e) => int.tryParse(e) ?? 2).toList();
        if (parts.length == 9) _grid = parts;
      } else {
        // 默认: 左列上一章, 右列下一章, 中列菜单
        _grid = [1, 3, 2, 1, 3, 2, 1, 3, 2];
      }
    });
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('click_actions', _grid.join(','));
  }

  void _editCell(int i) {
    showDialog(context: context, builder: (c) => SimpleDialog(
      title: Text('区域 ${i + 1} 动作'),
      children: List.generate(actions.length, (a) => RadioListTile<int>(
        value: a, groupValue: _grid[i],
        title: Text(actions[a]),
        onChanged: (v) { setState(() => _grid[i] = v ?? 0); _save(); Navigator.pop(c); },
      )),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('点击区域设置'),
        actions: [
          TextButton(onPressed: () { setState(() => _grid = [1, 3, 2, 1, 3, 2, 1, 3, 2]); _save(); }, child: const Text('恢复默认')),
        ],
      ),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(AppSpacing.l), child: Text('点击下方格子，为屏幕对应区域设置点击动作（从上到下、从左到右对应屏幕 3×3 分区）', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant))),
        Expanded(child: Padding(padding: const EdgeInsets.all(AppSpacing.l), child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 1),
          itemCount: 9,
          itemBuilder: (c, i) => InkWell(
            onTap: () => _editCell(i),
            borderRadius: AppRadius.mAll,
            child: Container(
              decoration: BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.outlineVariant), borderRadius: AppRadius.mAll, color: Theme.of(context).colorScheme.surfaceContainerHighest),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icons[_grid[i]], size: 28),
                const SizedBox(height: 6),
                Text(actions[_grid[i]], style: const TextStyle(fontSize: 12)),
              ]),
            ),
          ),
        ))),
        Padding(padding: const EdgeInsets.all(AppSpacing.l), child: Text('提示：中间区域通常设为「显示菜单」，左右两侧用于翻页', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))),
      ]),
    );
  }
}

// 对齐 E：E 的阅读菜单项与顺序由 XML 固定，没有「阅读菜单配置」界面，
// 原 ReadToolConfigScreen / _Group 已删除；文本选择菜单顺序仍由 ReadMenuConfig 持久化。
