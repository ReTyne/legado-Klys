import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/db_models.dart';

/// 阅读页「划词 → 查词」的应用内弹窗。
///
/// 列出所有启用的词典规则，用户点某一条即在当前页面内嵌 WebView 打开
/// 查询结果（`{word}` 会被 URL 编码后替换），不再跳出到外部浏览器。
/// 若没有任何规则，给出一键添加的引导。
class DictLookupSheet extends StatefulWidget {
  final String word;
  const DictLookupSheet({super.key, required this.word});

  /// 在阅读页调用：[openDictLookup] 会 showModalBottomSheet。
  static Future<void> open(BuildContext context, String word) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => DictLookupSheet(word: word),
    );
  }

  @override
  State<DictLookupSheet> createState() => _DictLookupSheetState();
}

class _DictLookupSheetState extends State<DictLookupSheet> {
  final _db = DatabaseService();
  List<DictRule> _rules = [];
  DictRule? _active;
  double _progress = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await _db.getDictRules();
    final enabled = all.where((r) => r.enabled == 1 && r.url.contains('{word}')).toList();
    if (!mounted) return;
    setState(() {
      _rules = enabled;
      // 与阅读页旧逻辑保持一致的兜底：没有规则时用在线词典
      _active = enabled.isNotEmpty ? enabled.first : null;
      _loading = false;
    });
  }

  String get _activeUrl {
    final w = Uri.encodeComponent(widget.word.trim());
    if (_active == null) return 'https://www.baidu.com/s?wd=$w';
    return _active!.url.replaceAll('{word}', w);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final height = MediaQuery.of(context).size.height * 0.82;
    return SizedBox(
      height: height,
      child: Column(
        children: [
          // 标题 + 被查询词
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('查词', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        widget.word.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          // 词典源横向切换
          if (_rules.isNotEmpty)
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _rules.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final r = _rules[i];
                  final selected = r == _active;
                  return ChoiceChip(
                    label: Text(r.name),
                    selected: selected,
                    onSelected: (_) => setState(() => _active = r),
                  );
                },
              ),
            ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else ...[
            if (_rules.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.menu_book_outlined, size: 44, color: Colors.grey),
                      const SizedBox(height: 8),
                      const Text('还没有可用的词典规则'),
                      const SizedBox(height: 4),
                      const Text('当前使用在线词典兜底', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
              ),
            // 加载进度
            if (_active != null && _progress > 0 && _progress < 1)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            Expanded(
              child: InAppWebView(
                key: ValueKey(_activeUrl),
                initialUrlRequest: URLRequest(url: WebUri(_activeUrl)),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  domStorageEnabled: true,
                  supportZoom: false,
                  useOnDownloadStart: false,
                ),
                onProgressChanged: (controller, progress) {
                  if (mounted) setState(() => _progress = progress / 100);
                },
                shouldOverrideUrlLoading: (controller, action) async {
                  // 站内跳转继续加载；其它一律拦掉，避免查词页变成通用浏览器
                  final uri = action.request.url;
                  if (uri == null) return NavigationActionPolicy.CANCEL;
                  final host = uri.host;
                  if (host.contains('baidu.com') || host.contains('zdic.net') || host.contains('bing.com') || host.contains('youdao.com')) {
                    return NavigationActionPolicy.ALLOW;
                  }
                  return NavigationActionPolicy.CANCEL;
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
