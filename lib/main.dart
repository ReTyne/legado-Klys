import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/constant/app_theme.dart';
import 'package:legado_md3/di/book_provider.dart';
import 'package:legado_md3/ui/main/main_screen.dart';
import 'package:legado_md3/ui/welcome/welcome_screen.dart';
import 'package:legado_md3/help/storage/crash_log_helper.dart';
import 'package:legado_md3/help/storage/auto_sync_service.dart';
import 'package:legado_md3/common/app_navigator.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 安装崩溃日志捕获（框架异常 + 异步异常落盘，供「我的-崩溃日志」查看）
  CrashLogHelper.instance.install();
  // 实验室：打开应用时自动 WebDAV 同步（开关关闭则立即返回，不影响启动）
  AutoSyncService.syncOnOpen();
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

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _firstLaunchDone = p.getBool('first_launch_done') ?? false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_firstLaunchDone == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return _firstLaunchDone! ? const MainScreen() : const WelcomeScreen();
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
