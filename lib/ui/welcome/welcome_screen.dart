import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:legado_md3/common/app_name.dart';
import 'package:legado_md3/ui/main/main_screen.dart';
import 'package:legado_md3/ui/welcome/welcome_config_screen.dart';

/// 启动欢迎页：先展示可配置的「自定义欢迎闪屏」，随后按首次启动状态展示
/// 隐私引导（三页 Intro + Policy）。
///
/// 自定义欢迎页 12 项配置（customWelcome / welcomeShowTime / welcomeShowCount /
/// welcomeImagePath(+Dark) / welcomeShowText(+Dark) / welcomeShowIcon(+Dark) /
/// welcomeImageDark / welcomeButtonText / welcomePrivacyPolicy）全部在此真实消费：
/// 图片做背景、图标/文案/按钮文案替换、展示时长自动进入、展示次数计数、
/// 自定义隐私政策替换正文；日/夜间按系统亮度切换。
///
/// [preview] 为配置页预览模式：不写任何持久化状态、递增次数或跳转主界面，
/// 结束仅 pop 返回。
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key, this.preview = false});

  final bool preview;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final PageController _controller = PageController();
  int _page = 0;
  bool _agreed = false;

  WelcomeConfig? _cfg;
  bool _loadingConfig = true;
  bool _showSplash = false;
  Timer? _splashTimer;

  // 首页标题带应用显示名（随系统语言切换），故用 getter 而非 const
  List<_Intro> get _pages => [
        _Intro(
            icon: Icons.menu_book,
            title: '欢迎使用$appDisplayName',
            desc:
                '开源网络文学阅读器，Material Design 3 风格，支持自定义书源、发现、订阅与本地导入。'),
        const _Intro(
            icon: Icons.travel_explore,
            title: '书源与发现',
            desc:
                '导入书源后即可聚合搜索、发现书目；多书源并发搜索、换源、目录解析、正文清洗一应俱全。'),
        const _Intro(
            icon: Icons.security,
            title: '隐私说明',
            desc:
                '书架、书源、阅读记录等数据仅保存在本机；网络请求仅发生在你主动使用书源/翻译/TTS 等功能时，应用不收集任何个人信息。'),
      ];

  /// 最后一页为隐私政策正文
  int get _total => _pages.length + 1;
  bool get _isPolicyPage => _page == _pages.length;
  bool get _isFirst => _page == 0;

  @override
  void initState() {
    super.initState();
    _loadWelcome();
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadWelcome() async {
    final cfg = await WelcomeConfig.load();
    final shown = await WelcomeConfig.shownTimes();
    final limitReached = cfg.showCount > 0 && shown >= cfg.showCount;
    // 预览模式忽略次数上限，始终展示自定义欢迎页，方便立即查看效果。
    final splash = cfg.customWelcome && (widget.preview || !limitReached);
    if (splash && !widget.preview) {
      await WelcomeConfig.incrementShown();
    }
    if (!mounted) return;
    setState(() {
      _cfg = cfg;
      _loadingConfig = false;
      _showSplash = splash;
    });
    if (splash) {
      _splashTimer = Timer(Duration(seconds: cfg.showTime.clamp(1, 30)),
          () => _afterSplash());
    }
  }

  /// 闪屏结束：预览则直接返回；非预览时若已完成首次引导则直接进主界面，
  /// 否则进入隐私引导 PageView。
  Future<void> _afterSplash() async {
    _splashTimer?.cancel();
    if (!mounted) return;
    if (widget.preview) {
      Navigator.pop(context);
      return;
    }
    final p = await SharedPreferences.getInstance();
    final done = p.getBool('first_launch_done') ?? false;
    if (!mounted) return;
    if (done) {
      await _enter();
    } else {
      setState(() => _showSplash = false);
    }
  }

  Future<void> _enter() async {
    if (widget.preview) {
      if (mounted) Navigator.pop(context);
      return;
    }
    final p = await SharedPreferences.getInstance();
    await p.setBool('first_launch_done', true);
    await p.setBool('privacy_agreed', true);
    await p.setInt(
        'privacy_agreed_at', DateTime.now().millisecondsSinceEpoch);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainScreen()));
  }

  void _next() {
    if (!_isPolicyPage) {
      _controller.nextPage(
          duration: const Duration(milliseconds: 250), curve: Curves.easeInOut);
    } else if (_agreed) {
      _enter();
    }
  }

  void _back() {
    _controller.previousPage(
        duration: const Duration(milliseconds: 250), curve: Curves.easeInOut);
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingConfig) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_showSplash && _cfg != null) {
      return Scaffold(
        body: _CustomWelcomeView(
          cfg: _cfg!,
          onEnter: _afterSplash,
        ),
      );
    }
    final cfg = _cfg ?? WelcomeConfig();
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _total,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => i == _pages.length
                    ? _PolicyView(
                        agreed: _agreed,
                        onChanged: (v) => setState(() => _agreed = v),
                        policyText: cfg.privacyPolicy.isNotEmpty
                            ? cfg.privacyPolicy
                            : _PolicyView.policy,
                      )
                    : _pages[i],
              ),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < _total; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: i == _page ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                      color: i == _page
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(12)),
                ),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: Row(children: [
                TextButton.icon(
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('返回'),
                  onPressed: _isFirst ? null : _back,
                ),
                const Spacer(),
                SizedBox(
                  width: 180,
                  child: FilledButton.icon(
                    icon: _isPolicyPage
                        ? const Icon(Icons.check, size: 18)
                        : const Icon(Icons.arrow_forward, size: 18),
                    label: Text(_isPolicyPage
                        ? (cfg.buttonText.isNotEmpty
                            ? cfg.buttonText
                            : '同意并开始使用')
                        : '下一步'),
                    onPressed: _isPolicyPage && !_agreed ? null : _next,
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

/// 自定义欢迎闪屏：背景图 / 主题渐变 + 图标 + 欢迎语 + 进入按钮。
class _CustomWelcomeView extends StatelessWidget {
  const _CustomWelcomeView({required this.cfg, required this.onEnter});

  final WelcomeConfig cfg;
  final VoidCallback onEnter;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final imagePath = cfg.imageFor(dark);
    final hasImage = imagePath.isNotEmpty && File(imagePath).existsSync();
    final text = cfg.textFor(dark).isNotEmpty
        ? cfg.textFor(dark)
        : '欢迎使用$appDisplayName';
    final button = cfg.buttonText.isNotEmpty ? cfg.buttonText : '进入阅读';

    Widget background = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [cs.primaryContainer, cs.surface],
        ),
      ),
    );
    if (hasImage) {
      background = Stack(fit: StackFit.expand, children: [
        Image.file(File(imagePath), fit: BoxFit.cover),
        Container(color: cs.surface.withOpacity(0.55)),
      ]);
    }

    return SafeArea(
      child: Stack(
        fit: StackFit.expand,
        children: [
          background,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  IconData(cfg.iconFor(dark), fontFamily: 'MaterialIcons'),
                  size: 96,
                  color: cs.primary,
                ),
                const SizedBox(height: 32),
                Text(
                  text,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Text(
                  '${cfg.showTime} 秒后自动进入',
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: onEnter,
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  label: Text(button),
                ),
              ],
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: TextButton(
              onPressed: onEnter,
              child: const Text('跳过'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;
  const _Intro({required this.icon, required this.title, required this.desc});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 96, color: cs.primary),
          const SizedBox(height: 32),
          Text(title,
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Text(desc,
              style: TextStyle(
                  fontSize: 15, color: cs.onSurfaceVariant, height: 1.6),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

/// 隐私政策正文（可滚动）+ 同意勾选；正文可由欢迎页配置替换。
class _PolicyView extends StatelessWidget {
  final bool agreed;
  final ValueChanged<bool> onChanged;
  final String policyText;

  const _PolicyView({
    required this.agreed,
    required this.onChanged,
    this.policyText = policy,
  });

  static const String policy = '''
隐私政策

生效日期：2026 年 1 月 1 日

一、我们不收集任何个人信息
本应用为本地优先的开源阅读工具，无需注册即可使用全部核心功能。我们（以及本应用的分发渠道）不会收集、上传或出售你的个人信息，包括但不限于姓名、手机号、通讯录、通话记录、短信、相册内容与定位信息。

二、数据存储范围
你的书架、书源订阅、阅读进度、书签、替换规则、备份文件等数据，全部保存在你本机设备的私有目录中。卸载应用会导致这些数据一并删除，请在卸载前通过「备份与恢复」导出备份。

三、网络请求的触发条件
应用仅在下列由你主动发起的操作中产生网络请求：
1. 使用网络书源搜索、获取目录与正文章内容；
2. 使用发现页/订阅页拉取第三方站点数据；
3. 使用在线翻译、在线朗读 TTS 或 WebDAV 备份同步；
4. 检查应用更新。
除此之外，应用不会在后台悄悄联网。当你配置第三方书源/翻译/WebDAV 服务时，相关请求会以你的设备身份发送至该第三方服务，其隐私处理以该服务方的政策为准。

四、权限说明
应用可能申请以下权限，且均在你主动使用相关功能时才会触发：
· 存储读写：导入本机书籍、导出备份与缓存文件；
· 相机：扫描二维码导入书源；
· 通知：后台下载/朗读时展示进度提示。
你可以随时在系统设置中撤销授权，撤销后相应功能将无法使用，但不影响离线阅读。

五、第三方内容
正文下发的内容来源于你自行添加的第三方书源，内容的准确性、合法性由 source 提供方负责。若你发现侵权内容，请通过书源管理停用相关来源。

六、未成年人保护
本应用不面向未满 14 周岁的儿童提供服务。若你是未成年人的监护人，发现被监护人使用本应用，请引导其在你的监督下使用。

七、政策更新
当本政策发生变化时，我们会通过应用内页面或发行说明进行提示，不会另行单独通知。继续使用即视为接受更新后的政策。

八、联系我们
本应用为开源项目，你可以向项目维护者反馈问题并请求删除你的相关数据（相关数据仅存在于你本机，卸载即可彻底清除）。
''';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.policy_outlined, color: cs.primary, size: 22),
            const SizedBox(width: 8),
            Text('隐私政策',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withOpacity(0.4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
              ),
              child: Scrollbar(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Text(policyText,
                      style: TextStyle(
                          fontSize: 13, height: 1.7, color: cs.onSurfaceVariant)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('我已阅读并同意《隐私政策》',
                style: TextStyle(fontSize: 13)),
            value: agreed,
            onChanged: (v) => onChanged(v ?? false),
          ),
        ],
      ),
    );
  }
}
