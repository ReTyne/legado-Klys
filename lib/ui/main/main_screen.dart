import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/help/storage/import_book_service.dart';
import 'package:legado_md3/help/storage/auto_update_service.dart';
import 'package:provider/provider.dart';
import 'package:legado_md3/di/book_provider.dart';
import 'package:legado_md3/ui/main/bookshelf/bookshelf_screen.dart';
import 'package:legado_md3/ui/main/discover/discover_screen.dart';
import 'package:legado_md3/ui/main/subscribe/subscribe_screen.dart';
import 'package:legado_md3/ui/main/my/profile_screen.dart';
import 'package:legado_md3/ui/book/local_import_screen.dart';
import 'package:legado_md3/ui/backup/backup_screen.dart';
import 'package:legado_md3/ui/cache/cache_manage_screen.dart';
import 'package:legado_md3/ui/bookmark/bookmark_screen.dart';
import 'package:legado_md3/ui/config/replace_rule_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

/// 主界面四个页签的标识。
///
/// 「发现」「订阅」可被用户在设置里隐藏（showDiscovery / showRss），
/// 所以页签列表是运行时动态计算的。
enum _HomeTab { bookshelf, discovery, subscribe, profile }

class _MainScreenState extends State<MainScreen> {
  static const List<_HomeTab> _allTabs = [
    _HomeTab.bookshelf,
    _HomeTab.discovery,
    _HomeTab.subscribe,
    _HomeTab.profile,
  ];

  int _currentIndex = 0;
  late PageController _pageController;
  List<_HomeTab> _tabs = _allTabs;
  static const _fileChannel = MethodChannel('legado/file_intent');
  final ImportBookService _importService = ImportBookService();

  // 退出确认（ui_confirmExit / ui_exitClickCount）
  bool _confirmExit = false;
  int _exitClickCount = 2;
  int _backPressCount = 0;
  DateTime? _lastBackPress;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _loadTabConfig();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<BookProvider>(context, listen: false).loadBooks();
      _checkOpenedFile();
      _checkAutoUpdateSetting();
      AutoUpdateService.instance.start(onUpdated: (n) {
        if (mounted) {
          Provider.of<BookProvider>(context, listen: false).loadBooks();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('自动更新：$n 本有新章节')));
        }
      });
    });
    _fileChannel.setMethodCallHandler((call) async {
      if (call.method == 'onFileOpened' && call.arguments is String) {
        _importOpened(call.arguments as String);
      }
    });
  }

  /// 启动自动检查应用更新（oc_autoCheckUpdate / updateToVariant）。
  ///
  /// 具体逻辑统一在 `AutoUpdateService.checkAppUpdate()` 里：版本对比走
  /// package_info_plus 的真实版本号，并按更新通道（正式/测试/关闭）分支。
  /// 这里只负责在首帧后触发一次，避免启动期阻塞。
  Future<void> _checkAutoUpdateSetting() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (p.getBool('oc_autoCheckUpdate') ?? false) {
        await AutoUpdateService.checkAppUpdate();
      }
    } catch (_) {}
  }

  Future<void> _checkOpenedFile() async {
    try {
      final path = await _fileChannel.invokeMethod<String>('getInitialFile');
      if (path != null && path.isNotEmpty) _importOpened(path);
    } catch (_) {}
  }

  Future<void> _importOpened(String path) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await _importService.importPath(path);
      messenger.showSnackBar(SnackBar(content: Text('已导入《${res.book.name}》，共 ${res.chapterCount} 章')));
      if (mounted) Provider.of<BookProvider>(context, listen: false).loadBooks();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('导入失败: $e')));
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// 读取「发现/订阅页签显隐」「默认首页」「退出确认」配置并应用。
  Future<void> _loadTabConfig() async {
    SharedPreferences p;
    try {
      p = await SharedPreferences.getInstance();
    } catch (_) {
      return;
    }
    final showDiscovery = p.getBool('showDiscovery') ?? true;
    final showRss = p.getBool('showRss') ?? true;
    final tabs = <_HomeTab>[];
    for (final t in _allTabs) {
      if (t == _HomeTab.discovery && !showDiscovery) continue;
      if (t == _HomeTab.subscribe && !showRss) continue;
      tabs.add(t);
    }
    if (tabs.length < 2) {
      tabs
        ..clear()
        ..add(_HomeTab.bookshelf)
        ..add(_HomeTab.profile);
    }

    final wanted = (p.getInt('defaultHomePage') ?? 0).clamp(0, _allTabs.length - 1);
    var initial = tabs.indexOf(_allTabs[wanted]);
    if (initial < 0) initial = 0;

    if (!mounted) return;
    setState(() {
      _tabs = tabs;
      _currentIndex = initial;
      _confirmExit = p.getBool('ui_confirmExit') ?? false;
      _exitClickCount = (p.getInt('ui_exitClickCount') ?? 2) < 2 ? 2 : p.getInt('ui_exitClickCount') ?? 2;
    });
    _pageController.dispose();
    _pageController = PageController(initialPage: initial);
  }

  Widget _screenFor(_HomeTab tab) => switch (tab) {
        _HomeTab.bookshelf => const BookshelfScreen(),
        _HomeTab.discovery => const DiscoverScreen(),
        _HomeTab.subscribe => const SubscribeScreen(),
        _HomeTab.profile => const ProfileScreen(),
      };

  NavigationDestination _destinationFor(_HomeTab tab) => switch (tab) {
        _HomeTab.bookshelf => const NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: '书架',
          ),
        _HomeTab.discovery => const NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: '发现',
          ),
        _HomeTab.subscribe => const NavigationDestination(
            icon: Icon(Icons.subscriptions_outlined),
            selectedIcon: Icon(Icons.subscriptions),
            label: '订阅',
          ),
        _HomeTab.profile => const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
      };

  void _onPageChanged(int index) {
    setState(() => _currentIndex = index);
  }

  void _onItemTapped(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
    );
  }

  /// 返回 true 表示允许退出。
  ///
  /// 未开启确认时直接放行（保持原有行为）；开启后要求在 2 秒内连按达到
  /// ui_exitClickCount 次才退出，否则提示还剩几次。
  bool _allowExit() {
    if (!_confirmExit) return true;
    final now = DateTime.now();
    if (_lastBackPress == null || now.difference(_lastBackPress!) > const Duration(seconds: 2)) {
      _backPressCount = 1;
    } else {
      _backPressCount++;
    }
    _lastBackPress = now;
    if (_backPressCount >= _exitClickCount) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('再按 ${_exitClickCount - _backPressCount} 次退出')),
    );
    return false;
  }

  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/local_import':
        return MaterialPageRoute(builder: (_) => const LocalImportScreen());
      case '/backup':
        return MaterialPageRoute(builder: (_) => const BackupScreen());
      case '/cache':
        return MaterialPageRoute(builder: (_) => const CacheManageScreen());
      case '/bookmark':
        return MaterialPageRoute(builder: (_) => const BookmarkScreen());
      case '/replace':
        return MaterialPageRoute(builder: (_) => const ReplaceRuleScreen());
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final navigator = Navigator(
      onGenerateRoute: (settings) {
        if (settings.name == '/') {
          return MaterialPageRoute(builder: (_) => _buildMainScaffold());
        }
        return _onGenerateRoute(settings);
      },
    );
    if (!_confirmExit) return navigator;
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        if (_allowExit()) SystemNavigator.pop();
      },
      child: navigator,
    );
  }

  Widget _buildMainScaffold() {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        children: _tabs.map(_screenFor).toList(),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex.clamp(0, _tabs.length - 1),
        onDestinationSelected: _onItemTapped,
        destinations: _tabs.map(_destinationFor).toList(),
      ),
    );
  }
}
