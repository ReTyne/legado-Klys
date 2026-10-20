import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/constant/app_theme.dart';
import 'package:legado_md3/di/book_provider.dart';
import 'package:legado_md3/ui/main/main_screen.dart';
import 'package:legado_md3/ui/welcome/welcome_screen.dart';
import 'package:legado_md3/help/storage/crash_log_helper.dart';
import 'package:legado_md3/help/storage/auto_sync_service.dart';
import 'package:legado_md3/help/web/web_service.dart';
import 'package:legado_md3/common/app_navigator.dart';
import 'package:legado_md3/ui/book/reader_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  // 记录日志开关（oc_recordLog）
  if (prefs.getBool('oc_recordLog') ?? false) {
    CrashLogHelper.instance.install();
  }
  // 实验室：打开应用时自动 WebDAV 同步（开关关闭则立即返回，不影响启动）
  AutoSyncService.syncOnOpen();
  // 漫画界面开关（oc_showMangaUi）
  showMangaUi = prefs.getBool('oc_showMangaUi') ?? true;
  // Web 服务自动启动（oc_webAutoStart）
  if (prefs.getBool('oc_webAutoStart') ?? false) {
    final port = prefs.getInt('oc_webPort') ?? 1122;
    WebService().start(port: port).catchError((_) {});
  }
  runApp(const LegadoApp());
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
                const Text('阅读 MD3', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
            title: '阅读 MD3',
            debugShowCheckedModeBanner: false,
            theme: appTheme.lightTheme,
            darkTheme: appTheme.darkTheme,
            themeMode: appTheme.themeMode,
            home: const LaunchGate(),
          );
        },
      ),
    );
  }
}
