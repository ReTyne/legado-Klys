import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/ui/main/main_screen.dart';

/// 首次启动欢迎与隐私引导（对齐原版启动协议页）
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final PageController _controller = PageController();
  int _page = 0;

  static const _pages = [
    _Intro(icon: Icons.menu_book, title: '欢迎使用阅读 MD3', desc: '开源网络文学阅读器，Material Design 3 风格，支持自定义书源、发现、订阅与本地导入。'),
    _Intro(icon: Icons.travel_explore, title: '书源与发现', desc: '导入书源后即可聚合搜索、发现书目；多书源并发搜索、换源、目录解析、正文清洗一应俱全。'),
    _Intro(icon: Icons.security, title: '隐私说明', desc: '书架、书源、阅读记录等数据仅保存在本机；网络请求仅发生在你主动使用书源/翻译/TTS 等功能时，应用不收集任何个人信息。'),
  ];

  Future<void> _enter() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('first_launch_done', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const MainScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => _pages[i],
              ),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < _pages.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: i == _page ? 22 : 8, height: 8,
                  decoration: BoxDecoration(color: i == _page ? cs.primary : cs.outlineVariant, borderRadius: BorderRadius.circular(4)),
                ),
            ]),
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    if (_page < _pages.length - 1) {
                      _controller.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeInOut);
                    } else {
                      _enter();
                    }
                  },
                  child: Text(_page < _pages.length - 1 ? '下一步' : '同意并开始使用'),
                ),
              ),
            ),
          ],
        ),
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
          Text(title, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Text(desc, style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant, height: 1.6), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
