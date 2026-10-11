import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:legado_md3/ui/book/read/config/click_action_config_screen.dart';
import 'package:legado_md3/ui/book/read/config/read_tool_config_screen.dart';
import 'package:provider/provider.dart';
import 'package:legado_md3/di/book_provider.dart';

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
}
