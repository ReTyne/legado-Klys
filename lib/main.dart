import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:legado_md3/constant/app_theme.dart';
import 'package:legado_md3/di/book_provider.dart';
import 'package:legado_md3/ui/main/main_screen.dart';
import 'package:legado_md3/ui/welcome/welcome_screen.dart';
import 'package:legado_md3/help/storage/crash_log_helper.dart';
import 'package:legado_md3/help/storage/auto_sync_service.dart';
import 'package:legado_md3/help/storage/backup_service.dart';
import 'package:legado_md3/help/web/web_service.dart';
import 'package:legado_md3/help/web/web_tile_channel.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/common/app_navigator.dart';
import 'package:legado_md3/common/app_name.dart';
import 'package:legado_md3/common/deep_link_service.dart';
import 'package:legado_md3/help/net/network_monitor.dart';
import 'package:legado_md3/ui/book/reader_router.dart';

/// 应用语言（oc_language：0 跟随系统 / 1 简体中文 / 2 English）
/// 定义见 common/app_name.dart，显示名随生效语言切换（中文 -> 阅读，其他 -> legado）

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  // 记录日志开关（oc_recordLog）
  if (prefs.getBool('oc_recordLog') ?? false) {
    CrashLogHelper.instance.install();
  }
  // 漫画界面开关（oc_showMangaUi）
  showMangaUi = prefs.getBool('oc_showMangaUi') ?? true;
  // 语言设置（oc_language）
  final lang = prefs.getInt('oc_language') ?? 0;
  appLocale = lang == 1
      ? const Locale('zh', 'CN')
      : lang == 2
          ? const Locale('en')
          : null;
  runApp(const LegadoApp());
  // 首帧后的收尾启动任务：全部移到 postFrameCallback，启动不再卡顿
  WidgetsBinding.instance.addPostFrameCallback((_) {
    // 记录日志开关已在前；以下均为可延后的后台 IO / 网络
    AutoSyncService.syncOnOpen();
    BackupService.scheduleAutoBackup();
    // 网络状态监听：搜索/校验/上传前的快速离线判断（E: NetworkUtils.isAvailable）
    NetworkMonitor.instance.start();
    if (prefs.getBool('oc_autoClearExpired') ?? false) {
      DatabaseService().clearExpiredChapterContent().catchError((_) => 0);
    }
    if (prefs.getBool('oc_webAutoStart') ?? false) {
      final port = prefs.getInt('oc_webPort') ?? 1122;
      WebService().start(port: port).then((_) => WebTileChannel.syncFromUi()).catchError((_) {});
    }
    // Web 服务快捷磁贴（Android N+ 下拉磁贴，D3）
    WebTileChannel.register();
    // legado:// 深链与系统分享导入：监听并分派
    DeepLinkService.instance.init();
    DeepLinkService.instance.links.listen(
      (link) => DeepLinkService.instance.handleLink(link),
    );
  });
}

/// 启动根：首次进入显示欢迎/隐私引导，之后直接进主界面
class LaunchGate extends StatefulWidget {
  const LaunchGate({super.key});

  @override
  State<LaunchGate> createState() => _LaunchGateState();
}

class _LaunchGateState extends State<LaunchGate> {
  bool? _firstLaunchDone;
  bool _locked = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final pwd = p.getString('oc_password') ?? '';
      if (mounted) {
        setState(() {
          _firstLaunchDone = p.getBool('first_launch_done') ?? false;
          _locked = pwd.isNotEmpty;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_firstLaunchDone == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_locked) {
      return LockScreen(onUnlocked: () => setState(() => _locked = false));
    }
    return _firstLaunchDone! ? const MainScreen() : const WelcomeScreen();
  }
}

/// 启动密码锁（本地密码，对应「其他设置-设置本地密码」）。
class LockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  const LockScreen({super.key, required this.onUnlocked});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final p = await SharedPreferences.getInstance();
    final pwd = p.getString('oc_password') ?? '';
    if (_controller.text == pwd) {
      widget.onUnlocked();
    } else {
      setState(() => _error = '密码错误');
      _controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, size: 56, color: theme.colorScheme.primary),
                const SizedBox(height: 16),
                Text(appDisplayName, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 32),
                TextField(
                  controller: _controller,
                  obscureText: true,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _verify(),
                  decoration: InputDecoration(
                    hintText: '输入启动密码',
                    errorText: _error,
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.password),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(onPressed: _verify, child: const Text('解锁')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class LegadoApp extends StatelessWidget {
  const LegadoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppTheme()..load()),
        ChangeNotifierProvider(create: (_) => BookProvider()),
        ChangeNotifierProvider(create: (_) => ReadProvider()..load()),
      ],
      child: Consumer<AppTheme>(
        builder: (context, appTheme, _) {
          return MaterialApp(
            navigatorKey: appNavigatorKey,
            title: appDisplayName,
            debugShowCheckedModeBanner: false,
            theme: appTheme.lightTheme,
            darkTheme: appTheme.darkTheme,
            themeMode: appTheme.themeMode,
            locale: appLocale,
            supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const LaunchGate(),
          );
        },
      ),
    );
  }
}
