/// 阅读设置相关页面聚合（阅读设置/点击区域/工具栏配置）。


import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:legado_md3/data/model/read_config.dart';
import 'package:legado_md3/di/book_provider.dart';
import 'package:legado_md3/help/config/read_menu_config.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 全面阅读设置屏幕
class ReadingSettingsScreen extends StatefulWidget {
  const ReadingSettingsScreen({super.key});

  @override
  State<ReadingSettingsScreen> createState() => _ReadingSettingsScreenState();
}

class _ReadingSettingsScreenState extends State<ReadingSettingsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('阅读设置'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: '文字'),
            Tab(text: '排版'),
            Tab(text: '翻页'),
            Tab(text: '显示'),
            Tab(text: '其他'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTextTab(),
          _buildTypographyTab(),
          _buildPageTurnTab(),
          _buildDisplayTab(),
          _buildOtherTab(),
        ],
      ),
    );
  }

  Widget _buildTextTab() {
    final config = context.watch<ReadProvider>().config;
    return ListView(
      children: [
        ListTile(
          title: const Text('字号'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(icon: const Icon(Icons.remove), onPressed: () => context.read<ReadProvider>().updateConfig((c) => c.textSize = (c.textSize - 1).clamp(12, 40))),
            Text('${config.textSize}'),
            IconButton(icon: const Icon(Icons.add), onPressed: () => context.read<ReadProvider>().updateConfig((c) => c.textSize = (c.textSize + 1).clamp(12, 40))),
          ]),
        ),
        SwitchListTile(title: const Text('粗体'), value: config.boldText, onChanged: (v) => context.read<ReadProvider>().updateConfig((c) => c.boldText = v)),
        ListTile(
          title: const Text('字重'),
          trailing: DropdownButton<int>(
            value: config.fontWeight,
            items: const [100, 200, 300, 400, 500, 600, 700, 800, 900].map((w) => DropdownMenuItem(value: w, child: Text('$w'))).toList(),
            onChanged: (v) => context.read<ReadProvider>().updateConfig((c) => c.fontWeight = v ?? 400),
          ),
        ),
        ListTile(
          title: const Text('对齐方式'),
          trailing: DropdownButton<int>(
            value: config.textAlign,
            items: const [DropdownMenuItem(value: 0, child: Text('左对齐')), DropdownMenuItem(value: 1, child: Text('居中')), DropdownMenuItem(value: 2, child: Text('两端对齐'))],
            onChanged: (v) => context.read<ReadProvider>().updateConfig((c) => c.textAlign = v ?? 2),
          ),
        ),
        ListTile(
          title: const Text('文字颜色'),
          trailing: Icon(Icons.color_lens, color: Color(config.textColor)),
          onTap: () => _showColorPicker((color) => context.read<ReadProvider>().updateConfig((c) => c.textColor = color.value)),
        ),
        ListTile(
          title: const Text('字体'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showFontPicker(),
        ),
      ],
    );
  }

  Widget _buildTypographyTab() {
    final config = context.watch<ReadProvider>().config;
    return ListView(
      children: [
        ListTile(title: const Text('首行缩进'), trailing: DropdownButton<int>(value: config.textIndent, items: List.generate(5, (i) => DropdownMenuItem(value: i, child: Text('${i * 2}字符'))), onChanged: (v) => context.read<ReadProvider>().updateConfig((c) => c.textIndent = v ?? 2))),
        ListTile(title: const Text('行距'), trailing: DropdownButton<int>(value: config.lineSpacing, items: List.generate(6, (i) => DropdownMenuItem(value: i, child: Text('${i * 0.5 + 1}倍'))), onChanged: (v) => context.read<ReadProvider>().updateConfig((c) => c.lineSpacing = v ?? 2))),
        ListTile(title: const Text('段间距'), trailing: DropdownButton<int>(value: config.paragraphSpacing, items: List.generate(5, (i) => DropdownMenuItem(value: i, child: Text('${i}行'))), onChanged: (v) => context.read<ReadProvider>().updateConfig((c) => c.paragraphSpacing = v ?? 1))),
        ListTile(title: const Text('字间距'), trailing: Slider(value: config.letterSpacing, min: 0, max: 10, divisions: 20, label: config.letterSpacing.toStringAsFixed(1), onChanged: (v) => context.read<ReadProvider>().updateConfig((c) => c.letterSpacing = v))),
        ListTile(title: const Text('词间距'), trailing: Slider(value: config.wordSpacing, min: 0, max: 20, divisions: 20, label: config.wordSpacing.toStringAsFixed(1), onChanged: (v) => context.read<ReadProvider>().updateConfig((c) => c.wordSpacing = v))),
        ListTile(title: const Text('阴影等级'), trailing: DropdownButton<int>(value: config.shadowLevel, items: List.generate(4, (i) => DropdownMenuItem(value: i, child: Text('等级$i'))), onChanged: (v) => context.read<ReadProvider>().updateConfig((c) => c.shadowLevel = v ?? 0))),
        ListTile(title: const Text('下划线'), trailing: DropdownButton<int>(value: config.underlineType, items: const [DropdownMenuItem(value: 0, child: Text('无')), DropdownMenuItem(value: 1, child: Text('实线')), DropdownMenuItem(value: 2, child: Text('虚线')), DropdownMenuItem(value: 3, child: Text('波浪线')), DropdownMenuItem(value: 4, child: Text('双线'))], onChanged: (v) => context.read<ReadProvider>().updateConfig((c) => c.underlineType = v ?? 0))),
        const Divider(),
        ListTile(title: const Text('左边距'), trailing: Slider(value: config.paddingLeft.toDouble(), min: 0, max: 64, divisions: 16, label: '${config.paddingLeft}', onChanged: (v) => context.read<ReadProvider>().updateConfig((c) => c.paddingLeft = v.toInt()))),
        ListTile(title: const Text('右边距'), trailing: Slider(value: config.paddingRight.toDouble(), min: 0, max: 64, divisions: 16, label: '${config.paddingRight}', onChanged: (v) => context.read<ReadProvider>().updateConfig((c) => c.paddingRight = v.toInt()))),
        ListTile(title: const Text('上边距'), trailing: Slider(value: config.paddingTop.toDouble(), min: 0, max: 64, divisions: 16, label: '${config.paddingTop}', onChanged: (v) => context.read<ReadProvider>().updateConfig((c) => c.paddingTop = v.toInt()))),
        ListTile(title: const Text('下边距'), trailing: Slider(value: config.paddingBottom.toDouble(), min: 0, max: 64, divisions: 16, label: '${config.paddingBottom}', onChanged: (v) => context.read<ReadProvider>().updateConfig((c) => c.paddingBottom = v.toInt()))),
      ],
    );
  }

  Widget _buildPageTurnTab() {
    final config = context.watch<ReadProvider>().config;
    return ListView(
      children: [
        ListTile(title: const Text('翻页动画'), trailing: DropdownButton<int>(value: config.pageAnim, items: const [DropdownMenuItem(value: 0, child: Text('覆盖')), DropdownMenuItem(value: 1, child: Text('仿真')), DropdownMenuItem(value: 2, child: Text('滑动')), DropdownMenuItem(value: 3, child: Text('滚动')), DropdownMenuItem(value: 4, child: Text('无动画')), DropdownMenuItem(value: 5, child: Text('上下'))], onChanged: (v) => context.read<ReadProvider>().updateConfig((c) => c.pageAnim = v ?? 0))),
        ListTile(title: const Text('点击区域设置'), subtitle: const Text('配置屏幕 3×3 区域点击动作', style: TextStyle(fontSize: 11)), trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ClickActionConfigScreen()))),
        SwitchListTile(title: const Text('点击翻页'), value: config.clickTurnPage, onChanged: (v) => context.read<ReadProvider>().updateConfig((c) => c.clickTurnPage = v)),
        SwitchListTile(title: const Text('音量键翻页'), value: config.volumeKeyPage, onChanged: (v) => context.read<ReadProvider>().updateConfig((c) => c.volumeKeyPage = v)),
        SwitchListTile(title: const Text('音量键反向'), value: config.volumeKeyReverse, onChanged: (v) => context.read<ReadProvider>().updateConfig((c) => c.volumeKeyReverse = v)),
        SwitchListTile(title: const Text('自动翻页'), value: config.autoNextPage, onChanged: (v) => context.read<ReadProvider>().updateConfig((c) => c.autoNextPage = v)),
        if (config.autoNextPage) ListTile(title: const Text('自动翻页速度'), trailing: Slider(value: config.autoNextPageSpeed.toDouble(), min: 1, max: 20, divisions: 19, label: '${config.autoNextPageSpeed}秒', onChanged: (v) => context.read<ReadProvider>().updateConfig((c) => c.autoNextPageSpeed = v.toInt()))),
        SwitchListTile(title: const Text('模拟阅读'), value: config.simulatedReading, onChanged: (v) => context.read<ReadProvider>().updateConfig((c) => c.simulatedReading = v)),
        SwitchListTile(title: const Text('上下颠倒'), value: config.invertPage, onChanged: (v) => context.read<ReadProvider>().updateConfig((c) => c.invertPage = v)),
        SwitchListTile(title: const Text('竖排(横屏竖握)'), value: config.verticalLayout == 1, onChanged: (v) => context.read<ReadProvider>().updateConfig((c) => c.verticalLayout = v ? 1 : 0)),
      ],
    );
  }

  Widget _buildDisplayTab() {
    final config = context.watch<ReadProvider>().config;
    return ListView(
      children: [
        SwitchListTile(title: const Text('显示状态栏'), value: config.statusBarVisibility, onChanged: (v) => context.read<ReadProvider>().updateConfig((c) => c.statusBarVisibility = v)),
        SwitchListTile(title: const Text('显示标题'), value: config.titleVisibility, onChanged: (v) => context.read<ReadProvider>().updateConfig((c) => c.titleVisibility = v)),
        SwitchListTile(title: const Text('显示时间'), value: config.timeVisibility, onChanged: (v) => context.read<ReadProvider>().updateConfig((c) => c.timeVisibility = v)),
        SwitchListTile(title: const Text('显示电量'), value: config.batteryVisibility, onChanged: (v) => context.read<ReadProvider>().updateConfig((c) => c.batteryVisibility = v)),
        SwitchListTile(title: const Text('显示页码'), value: config.pageNumberVisibility, onChanged: (v) => context.read<ReadProvider>().updateConfig((c) => c.pageNumberVisibility = v)),
        SwitchListTile(title: const Text('显示进度'), value: config.showProgress, onChanged: (v) => context.read<ReadProvider>().updateConfig((c) => c.showProgress = v)),
        SwitchListTile(title: const Text('沉浸模式'), value: config.immersiveMode, onChanged: (v) => context.read<ReadProvider>().updateConfig((c) => c.immersiveMode = v)),
        SwitchListTile(title: const Text('全屏'), value: config.fullScreen, onChanged: (v) => context.read<ReadProvider>().updateConfig((c) => c.fullScreen = v)),
        ListTile(title: const Text('屏幕方向'), trailing: DropdownButton<int>(value: config.screenOrientation, items: const [DropdownMenuItem(value: 0, child: Text('自动')), DropdownMenuItem(value: 1, child: Text('竖屏')), DropdownMenuItem(value: 2, child: Text('横屏'))], onChanged: (v) => context.read<ReadProvider>().updateConfig((c) => c.screenOrientation = v ?? 0))),
        SwitchListTile(title: const Text('护眼模式'), value: config.eyeProtection, onChanged: (v) => context.read<ReadProvider>().updateConfig((c) => c.eyeProtection = v)),
        if (config.eyeProtection) ListTile(title: const Text('护眼强度'), trailing: Slider(value: config.eyeProtectionLevel.toDouble(), min: 0, max: 100, divisions: 20, label: '${config.eyeProtectionLevel}%', onChanged: (v) => context.read<ReadProvider>().updateConfig((c) => c.eyeProtectionLevel = v.toInt()))),
        ListTile(title: const Text('背景颜色'), trailing: Icon(Icons.color_lens, color: Color(config.bgColor)), onTap: () => _showColorPicker((color) => context.read<ReadProvider>().updateConfig((c) => c.bgColor = color.value))),
        ListTile(
          title: const Text('背景图片'),
          subtitle: Text(config.bgImage == null ? '未设置，使用背景颜色' : '已设置自定义背景图'),
          trailing: config.bgImage == null ? const Icon(Icons.add_photo_alternate) : IconButton(icon: const Icon(Icons.clear), onPressed: () => context.read<ReadProvider>().updateConfig((c) => c.bgImage = null)),
          onTap: () async {
            final res = await FilePicker.platform.pickFiles(type: FileType.image);
            final path = res?.files.single.path;
            if (path != null) context.read<ReadProvider>().updateConfig((c) => c.bgImage = path);
          },
        ),
      ],
    );
  }

  Widget _buildOtherTab() {
    final config = context.watch<ReadProvider>().config;
    return ListView(
      children: [
        ListTile(leading: const Icon(Icons.dashboard_customize), title: const Text('阅读菜单配置'), subtitle: const Text('底部工具栏 / 更多菜单 / 选择菜单的显示与排序'), trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReadToolConfigScreen()))),
        const Divider(),
        SwitchListTile(title: const Text('保持屏幕常亮'), value: config.keepScreenOn, onChanged: (v) => context.read<ReadProvider>().updateConfig((c) => c.keepScreenOn = v)),
        SwitchListTile(title: const Text('点击显示菜单'), value: config.showMenuOnTap, onChanged: (v) => context.read<ReadProvider>().updateConfig((c) => c.showMenuOnTap = v)),
        SwitchListTile(title: const Text('长按选择文字'), value: config.longPressSelect, onChanged: (v) => context.read<ReadProvider>().updateConfig((c) => c.longPressSelect = v)),
        ListTile(title: const Text('编码格式'), trailing: Text(config.charset ?? '自动'), onTap: () => _showCharsetPicker()),
        ListTile(title: const Text('预下载章节数'), trailing: DropdownButton<int>(value: config.preDownloadCount, items: List.generate(6, (i) => DropdownMenuItem(value: i, child: Text(i == 0 ? '不预下载' : '$i章'))), onChanged: (v) => context.read<ReadProvider>().updateConfig((c) => c.preDownloadCount = v ?? 0))),
        SwitchListTile(title: const Text('显示时间电量'), value: config.showTimeBattery, onChanged: (v) => context.read<ReadProvider>().updateConfig((c) => c.showTimeBattery = v)),
        const Divider(),
        SwitchListTile(title: const Text('自定义头部'), value: config.customHeaderEnabled, onChanged: (v) => context.read<ReadProvider>().updateConfig((c) => c.customHeaderEnabled = v)),
        if (config.customHeaderEnabled) ListTile(title: const Text('头部文字'), trailing: const Icon(Icons.edit), onTap: () => _showHeaderEditor()),
        SwitchListTile(title: const Text('自定义底部'), value: config.customFooterEnabled, onChanged: (v) => context.read<ReadProvider>().updateConfig((c) => c.customFooterEnabled = v)),
        if (config.customFooterEnabled) ListTile(title: const Text('底部文字'), trailing: const Icon(Icons.edit), onTap: () => _showFooterEditor()),
        // 页脚三槽位内容配置（自定义底部文字开启时以自定义文字优先）
        ListTile(
          leading: const Icon(Icons.view_column),
          title: const Text('页脚槽位'),
          subtitle: Text('左:${footerSlotLabels[_safeFooterSlots(config)[0]]}  中:${footerSlotLabels[_safeFooterSlots(config)[1]]}  右:${footerSlotLabels[_safeFooterSlots(config)[2]]}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showFooterSlotsPicker(),
        ),
        SwitchListTile(dense: true, title: const Text('头部加粗'), value: config.headerBold, onChanged: (v) => context.read<ReadProvider>().updateConfig((c) => c.headerBold = v)),
        SwitchListTile(dense: true, title: const Text('底部加粗'), value: config.footerBold, onChanged: (v) => context.read<ReadProvider>().updateConfig((c) => c.footerBold = v)),
      ],
    );
  }

  void _showColorPicker(void Function(Color) onColor) {
    showModalBottomSheet(context: context, builder: (context) => Wrap(children: [
      for (final color in [Colors.white, Colors.black, Colors.grey, Colors.blueGrey, Colors.brown, Colors.red, Colors.pink, Colors.purple, Colors.deepPurple, Colors.indigo, Colors.blue, Colors.lightBlue, Colors.cyan, Colors.teal, Colors.green, Colors.lightGreen, Colors.lime, Colors.yellow, Colors.amber, Colors.orange, Colors.deepOrange])
        GestureDetector(onTap: () { onColor(color); Navigator.pop(context); }, child: Container(margin: const EdgeInsets.all(8), width: 40, height: 40, decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: Colors.grey)))),
    ]));
  }

  void _showFontPicker() {
    final fonts = ['系统默认', '衬线体', '无衬线体', '等宽字体', '手写体'];
    showModalBottomSheet(context: context, builder: (context) => ListView.builder(shrinkWrap: true, itemCount: fonts.length, itemBuilder: (context, index) => ListTile(title: Text(fonts[index]), onTap: () { context.read<ReadProvider>().updateConfig((c) => c.fontFamily = fonts[index] == '系统默认' ? null : fonts[index]); Navigator.pop(context); })));
  }

  void _showCharsetPicker() {
    final charsets = ['自动', 'UTF-8', 'GBK', 'GB2312', 'BIG5', 'UTF-16', 'ISO-8859-1'];
    showModalBottomSheet(context: context, builder: (context) => ListView.builder(shrinkWrap: true, itemCount: charsets.length, itemBuilder: (context, index) => ListTile(title: Text(charsets[index]), onTap: () { context.read<ReadProvider>().updateConfig((c) => c.charset = charsets[index] == '自动' ? null : charsets[index]); Navigator.pop(context); })));
  }

  void _showHeaderEditor() {
    final controller = TextEditingController(text: context.read<ReadProvider>().config.headerString ?? '');
    showDialog(context: context, builder: (context) => AlertDialog(title: const Text('自定义头部'), content: TextField(controller: controller, maxLines: 2), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')), FilledButton(onPressed: () { context.read<ReadProvider>().updateConfig((c) => c.headerString = controller.text); Navigator.pop(context); }, child: const Text('保存'))]));
  }

  void _showFooterEditor() {
    final controller = TextEditingController(text: context.read<ReadProvider>().config.footerString ?? '');
    showDialog(context: context, builder: (context) => AlertDialog(title: const Text('自定义底部'), content: TextField(controller: controller, maxLines: 2), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')), FilledButton(onPressed: () { context.read<ReadProvider>().updateConfig((c) => c.footerString = controller.text); Navigator.pop(context); }, child: const Text('保存'))]));
  }

  /// 页脚三槽位选择弹窗：左 / 中 / 右各自从内容枚举中选择
  void _showFooterSlotsPicker() {
    showDialog(
      context: context,
      builder: (ctx) {
        // dialog 的 context 位于 MultiProvider 子树内，可直接 watch 最新配置
        final slots = _safeFooterSlots(ctx.watch<ReadProvider>().config);
        return AlertDialog(
          title: const Text('页脚槽位'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              final label = i == 0 ? '左槽' : i == 1 ? '中槽' : '右槽';
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: SizedBox(width: 48, child: Text(label)),
                trailing: DropdownButton<FooterSlot>(
                  value: slots[i],
                  items: footerSlotLabels.entries
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    ctx.read<ReadProvider>().updateConfig((c) {
                      final next = _safeFooterSlots(c);
                      next[i] = v;
                      c.footerSlots = next;
                    });
                  },
                ),
              );
            }),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('完成')),
          ],
        );
      },
    );
  }
}

/// 读取页脚三槽位配置；长度不足时补空白槽，保证一定返回 3 个元素
List<FooterSlot> _safeFooterSlots(ReadConfig config) {
  final list = List<FooterSlot>.of(config.footerSlots ?? defaultFooterSlots);
  while (list.length < 3) {
    list.add(FooterSlot.none);
  }
  return list.sublist(0, 3);
}

/* ===== 由 click_action_config_screen.dart 合并 ===== */

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

/* ===== 由 read_tool_config_screen.dart 合并 ===== */

/// 阅读界面菜单/按钮配置：控制显示与排序（对齐原版三个 ConfigSheet）
class ReadToolConfigScreen extends StatefulWidget {
  const ReadToolConfigScreen({super.key});

  @override
  State<ReadToolConfigScreen> createState() => _ReadToolConfigScreenState();
}

class _Group {
  final String title;
  final String prefsKey;
  final Map<String, String> all;
  final List<String> defaults;
  List<String> order; // 可见且有序
  _Group(this.title, this.prefsKey, this.all, this.defaults, this.order);
}

class _ReadToolConfigScreenState extends State<ReadToolConfigScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final List<_Group> _groups = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _load();
  }

  Future<void> _load() async {
    final tb = await ReadMenuConfig.load(ReadMenuConfig.kToolBar, ReadMenuConfig.defaultToolBar);
    final mm = await ReadMenuConfig.load(ReadMenuConfig.kMoreMenu, ReadMenuConfig.defaultMoreMenu);
    final sm = await ReadMenuConfig.load(ReadMenuConfig.kSelectMenu, ReadMenuConfig.defaultSelectMenu);
    final fb = await ReadMenuConfig.load(ReadMenuConfig.kFloatingBar, ReadMenuConfig.defaultFloatingBar);
    _groups
      ..add(_Group('底部工具栏', ReadMenuConfig.kToolBar, ReadMenuConfig.toolBarItems, ReadMenuConfig.defaultToolBar, tb))
      ..add(_Group('更多菜单', ReadMenuConfig.kMoreMenu, ReadMenuConfig.moreMenuItems, ReadMenuConfig.defaultMoreMenu, mm))
      ..add(_Group('文本选择菜单', ReadMenuConfig.kSelectMenu, ReadMenuConfig.selectMenuItems, ReadMenuConfig.defaultSelectMenu, sm))
      ..add(_Group('悬浮快捷栏', ReadMenuConfig.kFloatingBar, ReadMenuConfig.floatingBarItems, ReadMenuConfig.defaultFloatingBar, fb));
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save(_Group g) => ReadMenuConfig.save(g.prefsKey, g.order);

  void _toggle(_Group g, String key, bool on) {
    setState(() {
      if (on) {
        if (!g.order.contains(key)) g.order.add(key);
      } else {
        g.order.remove(key);
      }
    });
    _save(g);
  }

  void _move(_Group g, int i, int dir) {
    final j = i + dir;
    if (j < 0 || j >= g.order.length) return;
    setState(() {
      final t = g.order[i]; g.order[i] = g.order[j]; g.order[j] = t;
    });
    _save(g);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(
        title: const Text('阅读菜单配置'),
        bottom: TabBar(controller: _tab, isScrollable: true, tabs: const [Tab(text: '底部工具栏'), Tab(text: '更多菜单'), Tab(text: '选择菜单'), Tab(text: '悬浮栏')]),
        actions: [
          IconButton(tooltip: '恢复默认', icon: const Icon(Icons.restart_alt), onPressed: _resetAll),
        ],
      ),
      body: TabBarView(
        controller: _tab,
        children: _groups.map(_buildGroup).toList(),
      ),
    );
  }

  Future<void> _resetAll() async {
    for (final g in _groups) {
      g.order = List.of(g.defaults);
      await _save(g);
    }
    if (mounted) setState(() {});
  }

  Widget _buildGroup(_Group g) {
    // 已显示项按 order 排在前，其余隐藏项排在后
    final hidden = g.all.keys.where((k) => !g.order.contains(k)).toList();
    return ListView(
      children: [
        Padding(padding: const EdgeInsets.all(12), child: Text('勾选显示，拖动箭头调整顺序（已显示 ${g.order.length}/${g.all.length}）', style: Theme.of(context).textTheme.bodySmall)),
        for (var i = 0; i < g.order.length; i++)
          _tile(g, g.order[i], true, i),
        if (hidden.isNotEmpty) const Divider(),
        for (final k in hidden) _tile(g, k, false, -1),
      ],
    );
  }

  Widget _tile(_Group g, String key, bool shown, int index) {
    return ListTile(
      dense: true,
      leading: Checkbox(value: shown, onChanged: (v) => _toggle(g, key, v ?? false)),
      title: Text(g.all[key] ?? key),
      trailing: shown
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: const Icon(Icons.arrow_upward, size: 20), onPressed: index > 0 ? () => _move(g, index, -1) : null),
              IconButton(icon: const Icon(Icons.arrow_downward, size: 20), onPressed: index < g.order.length - 1 ? () => _move(g, index, 1) : null),
            ])
          : null,
    );
  }
}

