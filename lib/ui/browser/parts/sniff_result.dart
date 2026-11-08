/// 由 browser_screen.dart 按「一类一文件」拆出的 _SniffResult。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../browser_screen.dart';


/// 嗅探结果
class _SniffResult {
  final List<Map<String, dynamic>> sources;
  final String? sourceUrl; // 页面内发现的可疑书源订阅链接
  final String? bookUrl; // 匹配到 bookUrlPattern 的书籍详情页
  final String? bookSourceUrl;
  _SniffResult({this.sources = const [], this.sourceUrl, this.bookUrl, this.bookSourceUrl});

  bool get isEmpty =>
      sources.isEmpty && sourceUrl == null && bookUrl == null;
}

const String _uaDesktop =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';
const String _uaMobile =
    'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36';

/// 快捷导航（书城 / 源仓库）
const List<Map<String, String>> _quickLinks = <Map<String, String>>[
  {'name': '123书城', 'url': 'https://www.123du.cc/'},
  {'name': '阅读源仓库 GitHub', 'url': 'https://github.com/gedoor/legado'},
  {'name': '阅读官网', 'url': 'https://gedoor.github.io/'},
  {
    'name': '搜索书源订阅',
    'url': 'https://github.com/search?q=legado+%E4%B9%A6%E6%BA%90&type=repositories'
  },
];
