import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 9 区点击动作配置，对齐原版 ClickActionConfigSheet
/// 屏幕划分为 3x3 九个区域，每个区域可绑定一个动作
class ClickActionConfigScreen extends StatefulWidget {
  const ClickActionConfigScreen({super.key});

  @override
  State<ClickActionConfigScreen> createState() => _ClickActionConfigScreenState();
}

class _ClickActionConfigScreenState extends State<ClickActionConfigScreen> {
  // 动作: 0无 1上一章 2下一章 3菜单 4上一页 5下一页
  static const actions = ['无动作', '上一章', '下一章', '显示菜单', '上一页', '下一页'];
  static const icons = [Icons.remove, Icons.skip_previous, Icons.skip_next, Icons.menu_book, Icons.chevron_left, Icons.chevron_right];
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('点击区域设置'),
        actions: [
          TextButton(onPressed: () { setState(() => _grid = [1, 3, 2, 1, 3, 2, 1, 3, 2]); _save(); }, child: const Text('恢复默认')),
        ],
      ),
      body: Column(children: [
        const Padding(padding: EdgeInsets.all(16), child: Text('点击下方格子，为屏幕对应区域设置点击动作（从上到下、从左到右对应屏幕 3×3 分区）', style: TextStyle(fontSize: 13, color: Colors.grey))),
        Expanded(child: Padding(padding: const EdgeInsets.all(16), child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 1),
          itemCount: 9,
          itemBuilder: (c, i) => InkWell(
            onTap: () => _editCell(i),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              decoration: BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.outlineVariant), borderRadius: BorderRadius.circular(12), color: Theme.of(context).colorScheme.surfaceContainerHighest),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icons[_grid[i]], size: 28),
                const SizedBox(height: 6),
                Text(actions[_grid[i]], style: const TextStyle(fontSize: 12)),
              ]),
            ),
          ),
        ))),
        const Padding(padding: EdgeInsets.all(16), child: Text('提示：中间区域通常设为「显示菜单」，左右两侧用于翻页', style: TextStyle(fontSize: 12, color: Colors.grey))),
      ]),
    );
  }
}
