import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:legado_md3/ui/widgets/app_widgets.dart';
import 'package:legado_md3/ui/welcome/welcome_screen.dart';

/// 自定义欢迎页配置数据（对齐 legado-E `pref_config_welcome.xml` 全部 8 项，
/// 并补齐按钮文案 / 展示次数 / 隐私政策 / 夜间独立背景，共 12 项）。
///
/// 所有键均为 SharedPreferences 明文；[WelcomeScreen] 启动 / 预览时读取并真实渲染。
class WelcomeConfig {
  static const String keyCustomWelcome = 'customWelcome';
  static const String keyShowTime = 'welcomeShowTime';
  static const String keyShowCount = 'welcomeShowCount';
  static const String keyImagePath = 'welcomeImagePath';
  static const String keyImagePathDark = 'welcomeImagePathDark';
  static const String keyText = 'welcomeShowText';
  static const String keyTextDark = 'welcomeShowTextDark';
  static const String keyIcon = 'welcomeShowIcon';
  static const String keyIconDark = 'welcomeShowIconDark';
  static const String keyImageDark = 'welcomeImageDark';
  static const String keyButtonText = 'welcomeButtonText';
  static const String keyPrivacyPolicy = 'welcomePrivacyPolicy';
  static const String keyShownTimes = 'welcomeShownTimes';

  bool customWelcome;
  int showTime; // 秒
  int showCount; // 0 = 不限次数
  String imagePath;
  String imagePathDark;
  String text;
  String textDark;
  int iconCodePoint;
  int iconCodePointDark; // 0 = 跟随日间
  bool imageDark; // 夜间启用独立背景图
  String buttonText;
  String privacyPolicy;

  WelcomeConfig({
    this.customWelcome = false,
    this.showTime = 2,
    this.showCount = 0,
    this.imagePath = '',
    this.imagePathDark = '',
    this.text = '',
    this.textDark = '',
    this.iconCodePoint = 0, // 0 = 使用默认 Icons.menu_book_outlined
    this.iconCodePointDark = 0,
    this.imageDark = false,
    this.buttonText = '',
    this.privacyPolicy = '',
  });

  static Future<WelcomeConfig> load() async {
    final p = await SharedPreferences.getInstance();
    return WelcomeConfig(
      customWelcome: p.getBool(keyCustomWelcome) ?? false,
      showTime: (p.getInt(keyShowTime) ?? 2).clamp(1, 30),
      showCount: (p.getInt(keyShowCount) ?? 0).clamp(0, 99),
      imagePath: p.getString(keyImagePath) ?? '',
      imagePathDark: p.getString(keyImagePathDark) ?? '',
      text: p.getString(keyText) ?? '',
      textDark: p.getString(keyTextDark) ?? '',
      iconCodePoint: p.getInt(keyIcon) ?? 0,
      iconCodePointDark: p.getInt(keyIconDark) ?? 0,
      imageDark: p.getBool(keyImageDark) ?? false,
      buttonText: p.getString(keyButtonText) ?? '',
      privacyPolicy: p.getString(keyPrivacyPolicy) ?? '',
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(keyCustomWelcome, customWelcome);
    await p.setInt(keyShowTime, showTime);
    await p.setInt(keyShowCount, showCount);
    await p.setString(keyImagePath, imagePath);
    await p.setString(keyImagePathDark, imagePathDark);
    await p.setString(keyText, text);
    await p.setString(keyTextDark, textDark);
    await p.setInt(keyIcon, iconCodePoint);
    await p.setInt(keyIconDark, iconCodePointDark);
    await p.setBool(keyImageDark, imageDark);
    await p.setString(keyButtonText, buttonText);
    await p.setString(keyPrivacyPolicy, privacyPolicy);
  }

  /// 按明暗选择欢迎语（夜间文案为空则回退日间）。
  String textFor(bool dark) =>
      dark && textDark.isNotEmpty ? textDark : text;

  /// 按明暗选择图标 codePoint（夜间为 0 则回退日间，日间为 0 用默认书本图标）。
  int iconFor(bool dark) {
    final cp = dark && iconCodePointDark != 0
        ? iconCodePointDark
        : iconCodePoint;
    return cp != 0 ? cp : Icons.menu_book_outlined.codePoint;
  }

  /// 按明暗选择背景图路径（仅开启夜间独立背景时切换）。
  String imageFor(bool dark) =>
      dark && imageDark && imagePathDark.isNotEmpty ? imagePathDark : imagePath;

  static Future<int> shownTimes() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(keyShownTimes) ?? 0;
  }

  static Future<void> incrementShown() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(keyShownTimes, (p.getInt(keyShownTimes) ?? 0) + 1);
  }

  static Future<void> resetShown() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(keyShownTimes, 0);
  }
}

/// 可选欢迎图标（存 MaterialIcons 的 codePoint，日/夜间各一份）。
const List<IconData> kWelcomeIconChoices = <IconData>[
  Icons.menu_book_outlined,
  Icons.auto_stories_outlined,
  Icons.local_library_outlined,
  Icons.favorite_outlined,
  Icons.star_outline,
  Icons.explore_outlined,
  Icons.book_outlined,
  Icons.nights_stay_outlined,
];

/// 自定义欢迎页配置页（设置 → 欢迎页配置入口）。
class WelcomeConfigScreen extends StatefulWidget {
  const WelcomeConfigScreen({super.key});

  @override
  State<WelcomeConfigScreen> createState() => _WelcomeConfigScreenState();
}

class _WelcomeConfigScreenState extends State<WelcomeConfigScreen> {
  WelcomeConfig _cfg = WelcomeConfig();
  bool _loading = true;
  int _shownTimes = 0;

  late final TextEditingController _textCtl;
  late final TextEditingController _textDarkCtl;
  late final TextEditingController _buttonCtl;
  late final TextEditingController _policyCtl;
  late final TextEditingController _imageCtl;
  late final TextEditingController _imageDarkCtl;

  @override
  void initState() {
    super.initState();
    _textCtl = TextEditingController();
    _textDarkCtl = TextEditingController();
    _buttonCtl = TextEditingController();
    _policyCtl = TextEditingController();
    _imageCtl = TextEditingController();
    _imageDarkCtl = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _textCtl.dispose();
    _textDarkCtl.dispose();
    _buttonCtl.dispose();
    _policyCtl.dispose();
    _imageCtl.dispose();
    _imageDarkCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final cfg = await WelcomeConfig.load();
    _shownTimes = await WelcomeConfig.shownTimes();
    _textCtl.text = cfg.text;
    _textDarkCtl.text = cfg.textDark;
    _buttonCtl.text = cfg.buttonText;
    _policyCtl.text = cfg.privacyPolicy;
    _imageCtl.text = cfg.imagePath;
    _imageDarkCtl.text = cfg.imagePathDark;
    if (!mounted) return;
    setState(() {
      _cfg = cfg;
      _loading = false;
    });
  }

  /// 开关 / 步进 / 图标即时落盘；文本项由底部「保存」统一写入。
  Future<void> _saveNow() async => _cfg.save();

  void _collectText() {
    _cfg.text = _textCtl.text.trim();
    _cfg.textDark = _textDarkCtl.text.trim();
    _cfg.buttonText = _buttonCtl.text.trim();
    _cfg.privacyPolicy = _policyCtl.text.trim();
    _cfg.imagePath = _imageCtl.text.trim();
    _cfg.imagePathDark = _imageDarkCtl.text.trim();
  }

  Future<void> _saveAll() async {
    _collectText();
    await _cfg.save();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('欢迎页配置已保存')));
  }

  Future<void> _pickImage(bool dark) async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = res?.files.single.path;
    if (path == null) return;
    setState(() {
      if (dark) {
        _imageDarkCtl.text = path;
        _cfg.imagePathDark = path;
      } else {
        _imageCtl.text = path;
        _cfg.imagePath = path;
      }
    });
    await _saveNow();
  }

  Future<void> _pickIcon(bool dark) async {
    final current = _cfg.iconFor(dark);
    final picked = await showAppRadioDialog<int>(
      context,
      title: dark ? '夜间欢迎图标' : '日间欢迎图标',
      groupValue: current,
      options: [
        for (final ic in kWelcomeIconChoices)
          AppRadioOption<int>(ic.codePoint, _iconLabel(ic)),
        if (dark) const AppRadioOption<int>(0, '跟随日间图标'),
      ],
    );
    if (picked == null) return;
    setState(() {
      if (dark) {
        _cfg.iconCodePointDark = picked;
      } else {
        _cfg.iconCodePoint = picked;
      }
    });
    await _saveNow();
  }

  String _iconLabel(IconData ic) {
    final map = <IconData, String>{
      Icons.menu_book_outlined: '书本',
      Icons.auto_stories_outlined: '故事',
      Icons.local_library_outlined: '图书馆',
      Icons.favorite_outlined: '爱心',
      Icons.star_outline: '星标',
      Icons.explore_outlined: '探索',
      Icons.book_outlined: '书籍',
      Icons.nights_stay_outlined: '夜间',
    };
    return map[ic] ?? '图标';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('自定义欢迎页'),
        actions: [
          IconButton(
            icon: const Icon(Icons.visibility_outlined),
            tooltip: '预览欢迎页',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const WelcomeScreen(preview: true))),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                AppSettingsGroup(
                  title: '启用与展示',
                  children: [
                    AppSwitchTile(
                      title: '启用自定义欢迎页',
                      subtitle: '启动时先展示自定义欢迎闪屏（customWelcome）',
                      value: _cfg.customWelcome,
                      onChanged: (v) {
                        setState(() => _cfg.customWelcome = v);
                        _saveNow();
                      },
                    ),
                    AppStepTile(
                      title: '展示时长（秒）',
                      subtitle: 'welcomeShowTime：到时自动进入',
                      value: _cfg.showTime,
                      min: 1,
                      max: 15,
                      onChanged: (v) {
                        setState(() => _cfg.showTime = v);
                        _saveNow();
                      },
                    ),
                    AppStepTile(
                      title: '展示次数上限',
                      subtitle: _cfg.showCount == 0
                          ? 'welcomeShowCount = 0：每次启动都展示'
                          : 'welcomeShowCount：累计展示 $_shownTimes / ${_cfg.showCount} 次',
                      value: _cfg.showCount,
                      min: 0,
                      max: 20,
                      onChanged: (v) {
                        setState(() => _cfg.showCount = v);
                        _saveNow();
                      },
                    ),
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.replay_outlined),
                      title: const Text('重置展示次数'),
                      subtitle: Text('当前已展示 $_shownTimes 次',
                          style: const TextStyle(fontSize: 11)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await WelcomeConfig.resetShown();
                        _shownTimes = await WelcomeConfig.shownTimes();
                        if (mounted) setState(() {});
                      },
                    ),
                  ],
                ),
                const Divider(),
                AppSettingsGroup(
                  title: '欢迎文案',
                  children: [
                    _textTile('日间欢迎语', 'welcomeShowText', _textCtl,
                        '留空则显示默认欢迎语'),
                    _textTile('夜间欢迎语', 'welcomeShowTextDark', _textDarkCtl,
                        '留空则沿用日间欢迎语'),
                    _textTile('按钮文案', 'welcomeButtonText', _buttonCtl,
                        '留空则为「进入阅读」/「同意并开始使用」'),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: TextField(
                        controller: _policyCtl,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          labelText: '自定义隐私政策（welcomePrivacyPolicy）',
                          hintText: '留空使用内置隐私政策正文',
                          alignLabelWithHint: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(),
                AppSettingsGroup(
                  title: '图标与背景',
                  children: [
                    ListTile(
                      dense: true,
                      leading: Icon(IconData(_cfg.iconFor(false),
                          fontFamily: 'MaterialIcons')),
                      title: const Text('日间欢迎图标'),
                      subtitle: const Text('welcomeShowIcon',
                          style: TextStyle(fontSize: 11)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _pickIcon(false),
                    ),
                    ListTile(
                      dense: true,
                      leading: Icon(IconData(_cfg.iconFor(true),
                          fontFamily: 'MaterialIcons')),
                      title: const Text('夜间欢迎图标'),
                      subtitle: const Text('welcomeShowIconDark',
                          style: TextStyle(fontSize: 11)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _pickIcon(true),
                    ),
                    AppSwitchTile(
                      title: '夜间启用独立背景',
                      subtitle: 'welcomeImageDark：夜间改用下方夜间背景图',
                      value: _cfg.imageDark,
                      onChanged: (v) {
                        setState(() => _cfg.imageDark = v);
                        _saveNow();
                      },
                    ),
                    _imageTile('日间背景图', 'welcomeImagePath', _imageCtl, false),
                    _imageTile(
                        '夜间背景图', 'welcomeImagePathDark', _imageDarkCtl, true),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Text(
                    '背景图使用本机文件路径（留空则用主题色背景）。日/夜间图标与背景'
                    '按系统亮度自动切换。配置即时保存开关，文本修改后请点击底部「保存」。',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: FilledButton.icon(
                    onPressed: _saveAll,
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: const Text('保存文案与背景'),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _textTile(String title, String keyName, TextEditingController ctl,
      String hint) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: TextField(
        controller: ctl,
        decoration: InputDecoration(
          labelText: title,
          hintText: hint,
          helperText: keyName,
          helperStyle: const TextStyle(fontSize: 10),
        ),
      ),
    );
  }

  Widget _imageTile(String title, String keyName, TextEditingController ctl,
      bool dark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: ctl,
              decoration: InputDecoration(
                labelText: title,
                helperText: keyName,
                helperStyle: const TextStyle(fontSize: 10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.image_outlined),
            tooltip: '选择图片',
            onPressed: () => _pickImage(dark),
          ),
        ],
      ),
    );
  }
}
