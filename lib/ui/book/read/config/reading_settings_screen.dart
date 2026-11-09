/// 阅读设置相关页面聚合（阅读设置/点击区域/工具栏配置/设置分区 sheet/排版预设）。
library;

import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/read_config.dart';
import 'package:legado_md3/data/model/v14_models.dart';
import 'package:legado_md3/di/book_provider.dart';
import 'package:legado_md3/ui/book/read/read_prefs.dart';
import 'package:legado_md3/ui/book/read/read_detail_utils.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
part 'click_action_config_screen.dart';


/// 全面阅读设置屏幕（Tab 分区；[initialTab] 供「设置分区 sheet」直达）。
class ReadingSettingsScreen extends StatefulWidget {
  final int initialTab;
  const ReadingSettingsScreen({super.key, this.initialTab = 0});

  @override
  State<ReadingSettingsScreen> createState() => _ReadingSettingsScreenState();
}

class _ReadingSettingsScreenState extends State<ReadingSettingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // 第十轮：不落在 ReadConfig 内的额外配置项（ReadPrefs / SharedPreferences）
  String _progressBarBehavior = 'page';
  bool _showBrightnessView = true;
  bool _expandTextMenu = false;
  bool _mouseWheelPage = true;
  bool _twoFingerReplacePreview = false;
  bool _followSystemBrightness = false;
  bool _pageEstimateAuto = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 5,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 4),
    );
    _loadExtra();
  }

  Future<void> _loadExtra() async {
    final behavior = await ReadPrefs.getString(ReadPrefs.kProgressBarBehavior,
        fallback: 'page');
    final results = await Future.wait<bool>([
      ReadPrefs.getBool(ReadPrefs.kShowBrightnessView, fallback: true),
      ReadPrefs.getBool(ReadPrefs.kExpandTextMenu, fallback: false),
      ReadPrefs.getBool(ReadPrefs.kMouseWheelPage, fallback: true),
      ReadPrefs.getBool(ReadPrefs.kTwoFingerReplacePreview, fallback: false),
      ReadPrefs.getBool(ReadPrefs.kFollowSystemBrightness, fallback: false),
      ReadPrefs.getBool(ReadPrefs.kPageEstimateAuto, fallback: true),
    ]);
    if (!mounted) return;
    setState(() {
      _progressBarBehavior = behavior == 'page' ? 'page' : 'chapter';
      _showBrightnessView = results[0];
      _expandTextMenu = results[1];
      _mouseWheelPage = results[2];
      _twoFingerReplacePreview = results[3];
      _followSystemBrightness = results[4];
      _pageEstimateAuto = results[5];
    });
  }

  Future<void> _flip(String key, bool value) async {
    await ReadPrefs.setBool(key, value);
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
        actions: [
          IconButton(
            tooltip: '排版预设',
            icon: const Icon(Icons.style_outlined),
            onPressed: () => unawaited(ReadPresetSheet.open(context)),
          ),
        ],
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
            IconButton(tooltip: '减小字号', icon: const Icon(Icons.remove), onPressed: () => context.read<ReadProvider>().updateConfig((c) => c.textSize = (c.textSize - 1).clamp(12, 40))),
            Text('${config.textSize}'),
            IconButton(tooltip: '增大字号', icon: const Icon(Icons.add), onPressed: () => context.read<ReadProvider>().updateConfig((c) => c.textSize = (c.textSize + 1).clamp(12, 40))),
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
          subtitle: Text('按当前模式（${['日间', '夜间', '墨水屏'][config.readThemeMode.clamp(0, 2)]}）独立保存', style: const TextStyle(fontSize: 11)),
          trailing: Icon(Icons.color_lens, color: Color(config.curTextColor)),
          // 对齐 E Config.setCurTextColor()：只写当前模式那份，不覆盖其它模式。
          onTap: () => _showColorPicker((color) => context.read<ReadProvider>().updateConfig((c) => c.setCurTextColor(color.value))),
        ),
        ListTile(
          title: const Text('字体'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showFontPicker(),
        ),
        ListTile(
          title: const Text('系统字体'),
          subtitle: const Text('未指定自定义字体时生效（对齐 E systemTypefaces）', style: TextStyle(fontSize: 11)),
          trailing: DropdownButton<int>(
            value: config.systemTypefaces.clamp(0, 2),
            items: const [
              DropdownMenuItem(value: 0, child: Text('无衬线')),
              DropdownMenuItem(value: 1, child: Text('衬线')),
              DropdownMenuItem(value: 2, child: Text('等宽')),
            ],
            onChanged: (v) => context.read<ReadProvider>().updateConfig((c) => c.systemTypefaces = v ?? 0),
          ),
        ),
      ],
    );
  }

  Widget _buildTypographyTab() {
    final config = context.watch<ReadProvider>().config;
    final rp = context.read<ReadProvider>();
    return ListView(
      children: [
        ListTile(title: const Text('首行缩进'), trailing: DropdownButton<int>(value: config.textIndent, items: List.generate(5, (i) => DropdownMenuItem(value: i, child: Text('${i * 2}字符'))), onChanged: (v) => rp.updateConfig((c) => c.textIndent = v ?? 2))),
        ListTile(title: const Text('行距'), trailing: DropdownButton<int>(value: config.lineSpacing, items: List.generate(6, (i) => DropdownMenuItem(value: i, child: Text('${i * 0.5 + 1}倍'))), onChanged: (v) => rp.updateConfig((c) => c.lineSpacing = v ?? 2))),
        ListTile(title: const Text('段间距'), trailing: DropdownButton<int>(value: config.paragraphSpacing, items: List.generate(5, (i) => DropdownMenuItem(value: i, child: Text('$i行'))), onChanged: (v) => rp.updateConfig((c) => c.paragraphSpacing = v ?? 1))),
        ListTile(title: const Text('字间距'), trailing: Slider(value: config.letterSpacing, min: 0, max: 10, divisions: 20, label: config.letterSpacing.toStringAsFixed(1), onChanged: (v) => rp.updateConfig((c) => c.letterSpacing = v))),
        ListTile(title: const Text('词间距'), trailing: Slider(value: config.wordSpacing, min: 0, max: 20, divisions: 20, label: config.wordSpacing.toStringAsFixed(1), onChanged: (v) => rp.updateConfig((c) => c.wordSpacing = v))),
        ListTile(title: const Text('阴影等级'), trailing: DropdownButton<int>(value: config.shadowLevel, items: List.generate(4, (i) => DropdownMenuItem(value: i, child: Text('等级$i'))), onChanged: (v) => rp.updateConfig((c) => c.shadowLevel = v ?? 0))),
        ListTile(title: const Text('下划线'), trailing: DropdownButton<int>(value: config.underlineType, items: const [DropdownMenuItem(value: 0, child: Text('无')), DropdownMenuItem(value: 1, child: Text('实线')), DropdownMenuItem(value: 2, child: Text('虚线')), DropdownMenuItem(value: 3, child: Text('波浪线')), DropdownMenuItem(value: 4, child: Text('双线'))], onChanged: (v) => rp.updateConfig((c) => c.underlineType = v ?? 0))),
        // 第十轮：以下 3 项已在阅读页真实消费（正文行高 / 字体特性 / 渲染隔离），恢复 UI
        const AppSectionHeader('渲染与排版（已接线）'),
        AppSwitchTile(
          title: '正文带到行高',
          subtitle: '段间空行计入分页高度，行距与正文一致',
          value: config.readBodyToLh,
          onChanged: (v) => rp.updateConfig((c) => c.readBodyToLh = v),
        ),
        AppSwitchTile(
          title: '特殊样式适配',
          subtitle: '启用 CJK 连字 / 字距 / 比例字形',
          value: config.adaptSpecialStyle,
          onChanged: (v) => rp.updateConfig((c) => c.adaptSpecialStyle = v),
        ),
        AppSwitchTile(
          title: '渲染优化',
          subtitle: '逐页 RepaintBoundary 隔离，切换后重新分页生效',
          value: config.optimizeRender,
          onChanged: (v) => rp.updateConfig((c) => c.optimizeRender = v),
        ),
        const Divider(),
        ListTile(title: const Text('左边距'), trailing: Slider(value: config.paddingLeft.toDouble(), min: 0, max: 64, divisions: 16, label: '${config.paddingLeft}', onChanged: (v) => rp.updateConfig((c) => c.paddingLeft = v.toInt()))),
        ListTile(title: const Text('右边距'), trailing: Slider(value: config.paddingRight.toDouble(), min: 0, max: 64, divisions: 16, label: '${config.paddingRight}', onChanged: (v) => rp.updateConfig((c) => c.paddingRight = v.toInt()))),
        ListTile(title: const Text('上边距'), trailing: Slider(value: config.paddingTop.toDouble(), min: 0, max: 64, divisions: 16, label: '${config.paddingTop}', onChanged: (v) => rp.updateConfig((c) => c.paddingTop = v.toInt()))),
        ListTile(title: const Text('下边距'), trailing: Slider(value: config.paddingBottom.toDouble(), min: 0, max: 64, divisions: 16, label: '${config.paddingBottom}', onChanged: (v) => rp.updateConfig((c) => c.paddingBottom = v.toInt()))),
      ],
    );
  }

  Widget _buildPageTurnTab() {
    final config = context.watch<ReadProvider>().config;
    final rp = context.read<ReadProvider>();
    return ListView(
      children: [
        ListTile(title: const Text('翻页动画'), trailing: DropdownButton<int>(value: config.pageAnim, items: const [DropdownMenuItem(value: 0, child: Text('覆盖')), DropdownMenuItem(value: 1, child: Text('仿真')), DropdownMenuItem(value: 2, child: Text('滑动')), DropdownMenuItem(value: 3, child: Text('滚动')), DropdownMenuItem(value: 4, child: Text('无动画')), DropdownMenuItem(value: 5, child: Text('上下'))], onChanged: (v) => rp.updateConfig((c) => c.pageAnim = v ?? 0))),
        ListTile(title: const Text('点击区域设置'), subtitle: const Text('配置屏幕 3×3 区域点击动作', style: TextStyle(fontSize: 11)), trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ClickActionConfigScreen()))),
        SwitchListTile(title: const Text('点击翻页'), value: config.clickTurnPage, onChanged: (v) => rp.updateConfig((c) => c.clickTurnPage = v)),
        SwitchListTile(title: const Text('音量键翻页'), value: config.volumeKeyPage, onChanged: (v) => rp.updateConfig((c) => c.volumeKeyPage = v)),
        SwitchListTile(title: const Text('音量键反向'), value: config.volumeKeyReverse, onChanged: (v) => rp.updateConfig((c) => c.volumeKeyReverse = v)),
        SwitchListTile(title: const Text('自动翻页'), value: config.autoNextPage, onChanged: (v) => rp.updateConfig((c) => c.autoNextPage = v)),
        if (config.autoNextPage) ListTile(title: const Text('自动翻页速度'), trailing: Slider(value: config.autoNextPageSpeed.toDouble(), min: 1, max: 20, divisions: 19, label: '${config.autoNextPageSpeed}秒', onChanged: (v) => rp.updateConfig((c) => c.autoNextPageSpeed = v.toInt()))),
        SwitchListTile(title: const Text('模拟阅读'), value: config.simulatedReading, onChanged: (v) => rp.updateConfig((c) => c.simulatedReading = v)),
        SwitchListTile(title: const Text('上下颠倒'), value: config.invertPage, onChanged: (v) => rp.updateConfig((c) => c.invertPage = v)),
        SwitchListTile(title: const Text('竖排(横屏竖握)'), value: config.verticalLayout == 1, onChanged: (v) => rp.updateConfig((c) => c.verticalLayout = v ? 1 : 0)),
        SwitchListTile(title: const Text('禁用返回键'), subtitle: const Text('已接线：阅读界面由 PopScope 拦截系统返回键', style: TextStyle(fontSize: 11)), value: config.disableReturnKey, onChanged: (v) => rp.updateConfig((c) => c.disableReturnKey = v)),
        // 第十轮：以下 6 项均在阅读页有真实消费分支（双页视口 / 滚动无动画 /
        // 音量键长按 / 朗读时音量键 / 触摸灵敏度 / 自定义按键），恢复 UI
        const AppSectionHeader('翻页进阶（已接线）'),
        ListTile(
          title: const Text('双水平页'),
          trailing: DropdownButton<int>(
            value: config.doubleHorizontalPage,
            items: const [
              DropdownMenuItem(value: 0, child: Text('单页')),
              DropdownMenuItem(value: 1, child: Text('双水平页')),
              DropdownMenuItem(value: 2, child: Text('横屏双页')),
            ],
            onChanged: (v) => rp.updateConfig((c) => c.doubleHorizontalPage = v ?? 0),
          ),
        ),
        AppSwitchTile(
          title: '滚动模式无动画',
          subtitle: '滚动翻页下代码跳页不做动画',
          value: config.noAnimScrollPage,
          onChanged: (v) => rp.updateConfig((c) => c.noAnimScrollPage = v),
        ),
        AppSwitchTile(
          title: '朗读时音量键翻页',
          value: config.volumeKeyPageOnPlay,
          onChanged: (v) => rp.updateConfig((c) => c.volumeKeyPageOnPlay = v),
        ),
        AppSwitchTile(
          title: '长按音量键连续翻页',
          subtitle: '开启后短按不翻页，长按重复事件连续翻页',
          value: config.keyPageOnLongPress,
          onChanged: (v) => rp.updateConfig((c) => c.keyPageOnLongPress = v),
        ),
        ListTile(
          title: const Text('滑动灵敏度（pageTouchSlop）'),
          subtitle: Text('数值越大越迟钝；当前 ${config.pageTouchSlop}（0 为关闭滚动拖动翻页）'),
          trailing: SizedBox(
            width: 160,
            child: Slider(
              value: config.pageTouchSlop.toDouble().clamp(0, 10),
              min: 0,
              max: 10,
              divisions: 10,
              label: '${config.pageTouchSlop}',
              onChanged: (v) => rp.updateConfig((c) => c.pageTouchSlop = v.toInt()),
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.keyboard_outlined),
          title: const Text('自定义翻页按键'),
          subtitle: Text(config.customPageKey == null
              ? '未设置（可在方向键 / 空格 / PageUp 等中挑选）'
              : '已配置 ${_customKeyCount(config.customPageKey)} 个按键'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _showCustomPageKeyEditor,
        ),
      ],
    );
  }

  int _customKeyCount(String? raw) {
    if (raw == null) return 0;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return ((m['prev'] as List?)?.length ?? 0) +
          ((m['next'] as List?)?.length ?? 0);
    } catch (_) {
      return 0;
    }
  }

  /// 自定义翻页按键编辑器：选择上/下一页键，写入 ReadConfig.customPageKey JSON，
  /// 阅读页 `_applyCustomPageKeys` 解析后在 Focus.onKeyEvent 中真实分发。
  void _showCustomPageKeyEditor() {
    final rp = context.read<ReadProvider>();
    Map<String, dynamic> decoded = {};
    try {
      final raw = rp.config.customPageKey;
      if (raw != null && raw.isNotEmpty) {
        decoded = jsonDecode(raw) as Map<String, dynamic>;
      }
    } catch (_) {}
    final prev = <String>{
      ...((decoded['prev'] as List?)?.map((e) => '$e') ?? const [])
    };
    final next = <String>{
      ...((decoded['next'] as List?)?.map((e) => '$e') ?? const [])
    };
    const options = <Map<String, String>>[
      {'key': 'arrow left', 'label': '方向键 ←'},
      {'key': 'arrow right', 'label': '方向键 →'},
      {'key': 'arrow up', 'label': '方向键 ↑'},
      {'key': 'arrow down', 'label': '方向键 ↓'},
      {'key': 'space', 'label': '空格'},
      {'key': 'page up', 'label': 'Page Up'},
      {'key': 'page down', 'label': 'Page Down'},
      {'key': 'a', 'label': 'A 键'},
      {'key': 'd', 'label': 'D 键'},
      {'key': 'w', 'label': 'W 键'},
      {'key': 's', 'label': 'S 键'},
      {'key': 'enter', 'label': '回车'},
    ];
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('自定义翻页按键'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('上一页（可多选）',
                      style: TextStyle(fontSize: 12)),
                  for (final o in options)
                    CheckboxListTile(
                      dense: true,
                      title: Text(o['label']!, style: const TextStyle(fontSize: 13)),
                      value: prev.contains(o['key']),
                      onChanged: (v) => setS(() =>
                          v == true ? prev.add(o['key']!) : prev.remove(o['key'])),
                    ),
                  const Divider(height: 8),
                  const Text('下一页（可多选）',
                      style: TextStyle(fontSize: 12)),
                  for (final o in options)
                    CheckboxListTile(
                      dense: true,
                      title: Text(o['label']!, style: const TextStyle(fontSize: 13)),
                      value: next.contains(o['key']),
                      onChanged: (v) => setS(() =>
                          v == true ? next.add(o['key']!) : next.remove(o['key'])),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                rp.updateConfig((c) => c.customPageKey = jsonEncode({
                      'prev': prev.toList(),
                      'next': next.toList(),
                    }));
                Navigator.pop(ctx);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDisplayTab() {
    final config = context.watch<ReadProvider>().config;
    final rp = context.read<ReadProvider>();
    final cs = Theme.of(context).colorScheme;
    return ListView(
      children: [
        SwitchListTile(title: const Text('显示状态栏'), value: config.statusBarVisibility, onChanged: (v) => rp.updateConfig((c) => c.statusBarVisibility = v)),
        SwitchListTile(title: const Text('显示标题'), value: config.titleVisibility, onChanged: (v) => rp.updateConfig((c) => c.titleVisibility = v)),
        SwitchListTile(title: const Text('显示时间'), value: config.timeVisibility, onChanged: (v) => rp.updateConfig((c) => c.timeVisibility = v)),
        SwitchListTile(title: const Text('显示电量'), value: config.batteryVisibility, onChanged: (v) => rp.updateConfig((c) => c.batteryVisibility = v)),
        SwitchListTile(title: const Text('显示页码'), value: config.pageNumberVisibility, onChanged: (v) => rp.updateConfig((c) => c.pageNumberVisibility = v)),
        SwitchListTile(title: const Text('显示进度'), value: config.showProgress, onChanged: (v) => rp.updateConfig((c) => c.showProgress = v)),
        SwitchListTile(title: const Text('沉浸模式'), value: config.immersiveMode, onChanged: (v) => rp.updateConfig((c) => c.immersiveMode = v)),
        SwitchListTile(title: const Text('全屏'), value: config.fullScreen, onChanged: (v) => rp.updateConfig((c) => c.fullScreen = v)),
        ListTile(title: const Text('屏幕方向'), trailing: DropdownButton<int>(value: config.screenOrientation, items: const [DropdownMenuItem(value: 0, child: Text('自动')), DropdownMenuItem(value: 1, child: Text('竖屏')), DropdownMenuItem(value: 2, child: Text('横屏'))], onChanged: (v) => rp.updateConfig((c) => c.screenOrientation = v ?? 0))),
        SwitchListTile(title: const Text('护眼模式'), value: config.eyeProtection, onChanged: (v) => rp.updateConfig((c) => c.eyeProtection = v)),
        if (config.eyeProtection) ListTile(title: const Text('护眼强度'), trailing: Slider(value: config.eyeProtectionLevel.toDouble(), min: 0, max: 100, divisions: 20, label: '${config.eyeProtectionLevel}%', onChanged: (v) => rp.updateConfig((c) => c.eyeProtectionLevel = v.toInt()))),
        ListTile(title: const Text('背景颜色'), subtitle: Text('按当前模式（${['日间', '夜间', '墨水屏'][config.readThemeMode.clamp(0, 2)]}）独立保存', style: const TextStyle(fontSize: 11)), trailing: Icon(Icons.color_lens, color: Color(config.curBgColor)), onTap: () => _showColorPicker((color) => rp.updateConfig((c) => c.setCurBgColor(color.value)))),
        ListTile(
          title: const Text('背景图片'),
          subtitle: Text(config.bgImage == null ? '未设置，使用背景颜色' : '已设置自定义背景图'),
          trailing: config.bgImage == null ? const Icon(Icons.add_photo_alternate) : IconButton(tooltip: '清除背景图片', icon: const Icon(Icons.clear), onPressed: () => rp.updateConfig((c) => c.bgImage = null)),
          onTap: () async {
            final res = await FilePicker.platform.pickFiles(type: FileType.image);
            final path = res?.files.single.path;
            if (path != null) rp.updateConfig((c) => c.bgImage = path);
          },
        ),
        // ===== 批次 3 · 日/夜/墨水屏三套独立配置（对齐 E ReadBookConfig.Config）=====
        // 切换模式后，上方的「文字颜色 / 背景颜色」写入的是当前模式那份，互不覆盖。
        const AppSectionHeader('日 / 夜 / 墨水屏 独立配置（已接线）'),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.l, AppSpacing.s, AppSpacing.l, AppSpacing.s),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('日间'), icon: Icon(Icons.wb_sunny_outlined)),
              ButtonSegment(value: 1, label: Text('夜间'), icon: Icon(Icons.nightlight_outlined)),
              ButtonSegment(value: 2, label: Text('墨水屏'), icon: Icon(Icons.menu_book_outlined)),
            ],
            selected: {config.readThemeMode.clamp(0, 2)},
            onSelectionChanged: (s) => rp.updateConfig((c) => c.readThemeMode = s.first),
          ),
        ),
        ListTile(
          title: const Text('强调色'),
          subtitle: const Text('朗读高亮 / 进度强调色，按当前模式独立保存', style: TextStyle(fontSize: 11)),
          trailing: Icon(Icons.color_lens, color: Color(config.curTextAccentColor)),
          onTap: () => _showColorPicker((color) => rp.updateConfig((c) => c.setCurTextAccentColor(color.value))),
        ),
        SwitchListTile(
          title: const Text('状态栏暗色图标'),
          subtitle: const Text('按当前模式独立保存（对齐 E darkStatusIcon*）', style: TextStyle(fontSize: 11)),
          value: config.curStatusIconDark,
          onChanged: (v) => rp.updateConfig((c) => c.setCurStatusIconDark(v)),
        ),
        // 墨水屏专用翻页动画：仅墨水屏模式生效（默认 4 无动画）。
        ListTile(
          title: const Text('墨水屏翻页动画'),
          subtitle: const Text('仅墨水屏模式生效；切换后由阅读页取用', style: TextStyle(fontSize: 11)),
          trailing: DropdownButton<int>(
            value: config.pageAnimEInk.clamp(0, 5),
            items: const [
              DropdownMenuItem(value: 0, child: Text('覆盖')),
              DropdownMenuItem(value: 1, child: Text('仿真')),
              DropdownMenuItem(value: 2, child: Text('滑动')),
              DropdownMenuItem(value: 3, child: Text('滚动')),
              DropdownMenuItem(value: 4, child: Text('无动画')),
              DropdownMenuItem(value: 5, child: Text('上下')),
            ],
            onChanged: (v) => rp.updateConfig((c) => c.pageAnimEInk = v ?? 4),
          ),
        ),
        SwitchListTile(title: const Text('标题附加信息'), subtitle: const Text('阅读标题栏显示章节附加信息', style: TextStyle(fontSize: 11)), value: config.showReadTitleAddition, onChanged: (v) => rp.updateConfig((c) => c.showReadTitleAddition = v)),
        ListTile(title: const Text('图片点击方式'), trailing: DropdownButton<int>(value: config.clickImgWay.clamp(0, 4), items: [for (var i = 0; i < clickImgWayLabels.length; i++) DropdownMenuItem(value: i, child: Text(clickImgWayLabels[i]))], onChanged: (v) => rp.updateConfig((c) => c.clickImgWay = v ?? 0))),
        // 第十轮：刘海屏 padding（阅读页 SafeArea 之外再扣安全区）恢复 UI
        const AppSectionHeader('显示进阶（已接线）'),
        AppSwitchTile(
          title: '刘海屏安全区 padding',
          subtitle: '分页时额外扣减屏幕上下左右安全区',
          value: config.paddingDisplayCutouts,
          onChanged: (v) => rp.updateConfig((c) => c.paddingDisplayCutouts = v),
        ),
        // 4 个额外配置项 + 双指预览 / 跟随系统亮度 / 自动页数估算
        ListTile(
          leading: const Icon(Icons.linear_scale_outlined),
          title: const Text('进度条行为（progressBarBehavior）'),
          subtitle: Text(_progressBarBehavior == 'page'
              ? '当前：章内按页拖动'
              : '当前：按章拖动'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _showProgressBarBehaviorPicker,
        ),
        AppSwitchTile(
          title: '显示亮度视图（showBrightnessView）',
          subtitle: '阅读设置面板显示真实亮度滑杆与电量',
          value: _showBrightnessView,
          onChanged: (v) {
            setState(() => _showBrightnessView = v);
            _flip(ReadPrefs.kShowBrightnessView, v);
          },
        ),
        AppSwitchTile(
          title: '展开文字选择菜单（expandTextMenu）',
          subtitle: '关闭时仅保留复制 / 划线 / 查词 / 翻译',
          value: _expandTextMenu,
          onChanged: (v) {
            setState(() => _expandTextMenu = v);
            _flip(ReadPrefs.kExpandTextMenu, v);
          },
        ),
        AppSwitchTile(
          title: '鼠标滚轮翻页（mouseWheelPage）',
          subtitle: '触控板 / 鼠标滚轮上下滚动切换页',
          value: _mouseWheelPage,
          onChanged: (v) {
            setState(() => _mouseWheelPage = v);
            _flip(ReadPrefs.kMouseWheelPage, v);
          },
        ),
        AppSwitchTile(
          title: '双指预览替换',
          subtitle: '双指点击弹出当前页替换净化前后对照',
          value: _twoFingerReplacePreview,
          onChanged: (v) {
            setState(() => _twoFingerReplacePreview = v);
            _flip(ReadPrefs.kTwoFingerReplacePreview, v);
          },
        ),
        AppSwitchTile(
          title: '跟随系统亮度',
          subtitle: '经原生通道写真实背光（setSystemBrightness / setWindowBrightness）',
          value: _followSystemBrightness,
          onChanged: (v) {
            setState(() => _followSystemBrightness = v);
            _flip(ReadPrefs.kFollowSystemBrightness, v);
          },
        ),
        AppSwitchTile(
          title: '自动估算章节 / 全书页数',
          subtitle: '复用真实分页结果写入 page_estimates 表',
          value: _pageEstimateAuto,
          onChanged: (v) {
            setState(() => _pageEstimateAuto = v);
            _flip(ReadPrefs.kPageEstimateAuto, v);
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.l, AppSpacing.s, AppSpacing.l, AppSpacing.s),
          child: Text('电量与亮度读数来自原生通道；颜色与背景按当前 MD3 主题呈现。',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ),
      ],
    );
  }

  void _showProgressBarBehaviorPicker() {
    showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('进度条行为'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<String>(
              title: const Text('按章拖动'),
              value: 'chapter',
              groupValue: _progressBarBehavior,
              onChanged: (v) => Navigator.pop(ctx, v),
            ),
            RadioListTile<String>(
              title: const Text('章内按页拖动'),
              value: 'page',
              groupValue: _progressBarBehavior,
              onChanged: (v) => Navigator.pop(ctx, v),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        ],
      ),
    ).then((v) async {
      if (v == null) return;
      setState(() => _progressBarBehavior = v);
      await ReadPrefs.setString(ReadPrefs.kProgressBarBehavior, v);
    });
  }

  Widget _buildOtherTab() {
    final config = context.watch<ReadProvider>().config;
    final rp = context.read<ReadProvider>();
    return ListView(
      children: [
        ListTile(
          title: const Text('屏幕超时（keep_light）'),
          subtitle: const Text('对齐 legado-E：跟随系统 / 1分 / 5分 / 10分 / 常亮', style: TextStyle(fontSize: 11)),
          trailing: DropdownButton<int>(
            value: const [0, 60, 300, 600, -1].contains(config.keepLight) ? config.keepLight : 0,
            items: const [
              DropdownMenuItem(value: 0, child: Text('跟随系统')),
              DropdownMenuItem(value: 60, child: Text('1 分钟')),
              DropdownMenuItem(value: 300, child: Text('5 分钟')),
              DropdownMenuItem(value: 600, child: Text('10 分钟')),
              DropdownMenuItem(value: -1, child: Text('常亮')),
            ],
            onChanged: (v) => rp.updateConfig((c) {
              c.keepLight = v ?? 0;
              // 兼容历史 keepScreenOn 布尔：-1 常亮 / >0 定时亮屏都要先开启
              c.keepScreenOn = v == -1 || (v != null && v > 0);
            }),
          ),
        ),
        SwitchListTile(title: const Text('点击显示菜单'), value: config.showMenuOnTap, onChanged: (v) => rp.updateConfig((c) => c.showMenuOnTap = v)),
        SwitchListTile(title: const Text('长按选择文字'), value: config.longPressSelect, onChanged: (v) => rp.updateConfig((c) => c.longPressSelect = v)),
        SwitchListTile(title: const Text('退出未入架书时提示加入书架'), subtitle: const Text('已接线：阅读页返回时按在架状态弹「加入书架」确认', style: TextStyle(fontSize: 11)), value: config.showAddToShelfAlert, onChanged: (v) => rp.updateConfig((c) => c.showAddToShelfAlert = v)),
        ListTile(title: const Text('编码格式'), trailing: Text(config.charset ?? '自动'), onTap: () => _showCharsetPicker()),
        ListTile(title: const Text('预下载章节数'), trailing: DropdownButton<int>(value: config.preDownloadCount, items: List.generate(6, (i) => DropdownMenuItem(value: i, child: Text(i == 0 ? '不预下载' : '$i章'))), onChanged: (v) => rp.updateConfig((c) => c.preDownloadCount = v ?? 0))),
        SwitchListTile(title: const Text('显示时间电量'), value: config.showTimeBattery, onChanged: (v) => rp.updateConfig((c) => c.showTimeBattery = v)),
        SwitchListTile(title: const Text('阅读栏样式跟随页面'), subtitle: const Text('已接线：菜单栏背景/文字跟随正文背景', style: TextStyle(fontSize: 11)), value: config.readBarStyleFollowPage, onChanged: (v) => rp.updateConfig((c) => c.readBarStyleFollowPage = v)),
        const Divider(),
        SwitchListTile(title: const Text('自定义头部'), value: config.customHeaderEnabled, onChanged: (v) => rp.updateConfig((c) => c.customHeaderEnabled = v)),
        if (config.customHeaderEnabled) ListTile(title: const Text('头部文字'), trailing: const Icon(Icons.edit), onTap: () => _showHeaderEditor()),
        SwitchListTile(title: const Text('自定义底部'), value: config.customFooterEnabled, onChanged: (v) => rp.updateConfig((c) => c.customFooterEnabled = v)),
        if (config.customFooterEnabled) ListTile(title: const Text('底部文字'), trailing: const Icon(Icons.edit), onTap: () => _showFooterEditor()),
        ListTile(
          leading: const Icon(Icons.view_column),
          title: const Text('页脚槽位'),
          subtitle: Text('左:${footerSlotLabels[_safeFooterSlots(config)[0]]}  中:${footerSlotLabels[_safeFooterSlots(config)[1]]}  右:${footerSlotLabels[_safeFooterSlots(config)[2]]}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showFooterSlotsPicker(),
        ),
        SwitchListTile(dense: true, title: const Text('头部加粗'), value: config.headerBold, onChanged: (v) => rp.updateConfig((c) => c.headerBold = v)),
        SwitchListTile(dense: true, title: const Text('底部加粗'), value: config.footerBold, onChanged: (v) => rp.updateConfig((c) => c.footerBold = v)),
        // 第十轮：自动换源 + 6 个朗读进阶项恢复 UI，全部在阅读页有真实消费分支
        const AppSectionHeader('换源与朗读（已接线）'),
        AppSwitchTile(
          title: '正文失效自动换源',
          subtitle: '正文为空 / 加载失败时按章节标题跨源检索并重载',
          value: config.autoChangeSource,
          onChanged: (v) => rp.updateConfig((c) => c.autoChangeSource = v),
        ),
        AppSwitchTile(
          title: '按页朗读',
          subtitle: '朗读时以真实分页结果逐页播放',
          value: config.readAloudByPage,
          onChanged: (v) => rp.updateConfig((c) => c.readAloudByPage = v),
        ),
        AppSwitchTile(
          title: '来电 / 切后台暂停朗读',
          value: config.pauseReadAloudWhilePhoneCalls,
          onChanged: (v) =>
              rp.updateConfig((c) => c.pauseReadAloudWhilePhoneCalls = v),
        ),
        AppSwitchTile(
          title: '媒体键切下一章',
          subtitle: '媒体键 next/prev 由 NativeBridge 媒体会话转发',
          value: config.mediaButtonPerNext,
          onChanged: (v) => rp.updateConfig((c) => c.mediaButtonPerNext = v),
        ),
        AppSwitchTile(
          title: '流式朗读（按句切分）',
          value: config.streamReadAloudAudio,
          onChanged: (v) => rp.updateConfig((c) => c.streamReadAloudAudio = v),
        ),
        AppSwitchTile(
          title: '系统 TTS 跟随系统偏好',
          value: config.sysTtsConfig,
          onChanged: (v) => rp.updateConfig((c) => c.sysTtsConfig = v),
        ),
        AppSwitchTile(
          title: '朗读语速跟随系统',
          value: config.ttsFlowSys,
          onChanged: (v) => rp.updateConfig((c) => c.ttsFlowSys = v),
        ),
      ],
    );
  }

  void _showColorPicker(void Function(Color) onColor) {
    const palette = <Color>[
      Colors.white, Colors.black, Colors.grey, Colors.blueGrey, Colors.brown,
      Colors.red, Colors.pink, Colors.purple, Colors.deepPurple, Colors.indigo,
      Colors.blue, Colors.lightBlue, Colors.cyan, Colors.teal, Colors.green,
      Colors.lightGreen, Colors.lime, Colors.yellow, Colors.amber, Colors.orange,
      Colors.deepOrange,
    ];
    showAppColorPicker(context, colors: palette).then((color) {
      if (color != null) onColor(color);
    });
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

/* ===== 第十轮：阅读设置按 sheet 分层 + 多套排版预设 ===== */

/// 阅读页「设置分区」底部 sheet：把 5 个设置分区分层组织，点击直达对应 Tab，
/// 并提供「排版预设」入口。不改动既有整页设置入口（_showReadingSettings）。
void showReaderSettingsSectionsSheet(BuildContext context, {Book? book}) {
  const sections = <(String, IconData, int)>[
    ('文字', Icons.text_fields_outlined, 0),
    ('排版', Icons.format_align_left_outlined, 1),
    ('翻页', Icons.auto_stories_outlined, 2),
    ('显示', Icons.brightness_6_outlined, 3),
    ('其他', Icons.tune_outlined, 4),
  ];
  final cs = Theme.of(context).colorScheme;
  showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.l),
            child: Row(
              children: [
                const Icon(Icons.layers_outlined, size: 20),
                const SizedBox(width: AppSpacing.s),
                Expanded(
                  child: Text(
                    book != null ? '阅读设置分区 · ${book.name}' : '阅读设置分区',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          for (final s in sections)
            ListTile(
              dense: true,
              leading: Icon(s.$2, size: 20),
              title: Text(s.$1),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ReadingSettingsScreen(initialTab: s.$3),
                  ),
                );
              },
            ),
          const Divider(height: 1),
          ListTile(
            dense: true,
            leading: const Icon(Icons.style_outlined, size: 20),
            title: const Text('排版预设（多套配置）'),
            subtitle: Text('保存当前排版 / 切换已存配置 / 删除',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.pop(ctx);
              unawaited(ReadPresetSheet.open(context));
            },
          ),
          const SizedBox(height: AppSpacing.s),
        ],
      ),
    ),
  );
}

/// 多套排版预设（对齐 Sigma `ReadBookConfig.configList` / `shareLayout`）。
/// 数据走 v14 `read_presets` 表：getReadPresets / insertReadPreset / deleteReadPreset；
/// 切换时把 ReadConfig 注入 ReadProvider.setConfig 并持久化。
class ReadPresetSheet extends StatefulWidget {
  const ReadPresetSheet({super.key});

  static Future<void> open(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const ReadPresetSheet(),
      );

  @override
  State<ReadPresetSheet> createState() => _ReadPresetSheetState();
}

class _ReadPresetSheetState extends State<ReadPresetSheet> {
  final DatabaseService _db = DatabaseService();
  List<ReadPreset> _presets = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _db.getReadPresets();
    if (!mounted) return;
    setState(() {
      _presets = list;
      _loading = false;
    });
  }

  Future<void> _saveCurrent() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('保存当前排版'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '预设名称，如「夜间大字」'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    final cfg = context.read<ReadProvider>().config;
    await _db.insertReadPreset(ReadPreset(
      name: name,
      config: cfg.toJsonString(),
    ));
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已保存排版预设「$name」')));
    }
  }

  Future<void> _apply(ReadPreset p) async {
    // 先缓存 messenger / navigator：pop 之后本 State 的 context 已失效
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final cfg = ReadConfig.fromJsonString(p.config);
      if (!mounted) return;
      context.read<ReadProvider>().setConfig(cfg);
      navigator.pop();
      messenger.showSnackBar(
          SnackBar(content: Text('已切换排版预设「${p.name}」')));
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
            SnackBar(content: Text('预设解析失败：$e')));
      }
    }
  }

  Future<void> _delete(ReadPreset p) async {
    final id = p.id;
    if (id == null) return;
    await _db.deleteReadPreset(id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.l, AppSpacing.l, AppSpacing.l, AppSpacing.l),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.55,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.style_outlined, size: 20),
                  const SizedBox(width: AppSpacing.s),
                  const Text('排版预设',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _saveCurrent,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('保存当前'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s),
              Text('每套预设保存完整 ReadConfig（字号 / 配色 / 边距 / 翻页动画等）。',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              const SizedBox(height: AppSpacing.s),
              const Divider(height: 1),
              Expanded(
                child: _loading
                    ? const AppLoadingIndicator()
                    : _presets.isEmpty
                        ? const AppEmptyState(
                            icon: Icons.style_outlined,
                            title: '暂无排版预设',
                            message: '点击「保存当前」新建一套',
                          )
                        : ListView.separated(
                            itemCount: _presets.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (ctx, i) {
                              final p = _presets[i];
                              return ListTile(
                                dense: true,
                                leading: Icon(Icons.palette_outlined,
                                    size: 20, color: cs.primary),
                                title: Text(p.name),
                                subtitle: Text(
                                  p.isDefault == 1 ? '默认预设' : '自定义排版',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                trailing: IconButton(
                                  tooltip: '删除这套预设',
                                  icon: const Icon(Icons.delete_outline,
                                      size: 18),
                                  onPressed: () => _delete(p),
                                ),
                                onTap: () => _apply(p),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

