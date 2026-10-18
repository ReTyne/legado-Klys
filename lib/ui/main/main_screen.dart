import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0; // 默认书架
  final PageController _pageController = PageController(initialPage: 0);
  static const _fileChannel = MethodChannel('legado/file_intent');
  final ImportBookService _importService = ImportBookService();

  final List<Widget> _screens = const [
    BookshelfScreen(),
    DiscoverScreen(),
    SubscribeScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<BookProvider>(context, listen: false).loadBooks();
      _checkOpenedFile();
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
    return Navigator(
      onGenerateRoute: (settings) {
        if (settings.name == '/') {
          return MaterialPageRoute(builder: (_) => _buildMainScaffold());
        }
        return _onGenerateRoute(settings);
      },
    );
  }

  Widget _buildMainScaffold() {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _onItemTapped,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: '书架',
          ),
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: '发现',
          ),
          NavigationDestination(
            icon: Icon(Icons.subscriptions_outlined),
            selectedIcon: Icon(Icons.subscriptions),
            label: '订阅',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
