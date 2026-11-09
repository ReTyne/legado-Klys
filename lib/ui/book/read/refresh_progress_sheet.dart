import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:legado_md3/help/storage/book_progress_sync.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';

/// 刷新范围（对齐 Sigma `menu_refresh` 三档：目录 / 当前章 / 全文）
enum RefreshScope {
  toc,     // 刷新目录（目录/章节/全文 里的「目录」档：重拉目录 + 清全文缓存）
  chapter, // 刷新当前章节
  all,     // 刷新全文（当前章及其后全部章节）
}

const Map<RefreshScope, String> refreshScopeLabels = {
  RefreshScope.toc: '刷新目录',
  RefreshScope.chapter: '刷新当前章节',
  RefreshScope.all: '刷新全文（当前章及其后）',
};

const Map<RefreshScope, IconData> refreshScopeIcons = {
  RefreshScope.toc: Icons.list_alt_outlined,
  RefreshScope.chapter: Icons.refresh_outlined,
  RefreshScope.all: Icons.auto_stories_outlined,
};

/// 刷新三档 + 云进度拉取/覆盖 的统一底部面板。
///
/// - 三档刷新由阅读页注入 [onRefresh] 真实执行（清缓存 / 重拉目录 / 重载章节）；
/// - 「获取云进度 / 覆盖云进度」直接调 [BookProgressSync.instance.pull] / [push]；
/// - 全部动作给出 SnackBar 反馈，并把云进度拉取结果回调给阅读页刷新定位。
class RefreshProgressSheet extends StatefulWidget {
  final String bookName;
  final String author;
  final Future<void> Function(RefreshScope scope) onRefresh;
  final Future<void> Function(int changed) onProgressPulled;

  const RefreshProgressSheet({
    super.key,
    required this.bookName,
    required this.author,
    required this.onRefresh,
    required this.onProgressPulled,
  });

  static Future<void> open(
    BuildContext context, {
    required String bookName,
    required String author,
    required Future<void> Function(RefreshScope scope) onRefresh,
    required Future<void> Function(int changed) onProgressPulled,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => RefreshProgressSheet(
        bookName: bookName,
        author: author,
        onRefresh: onRefresh,
        onProgressPulled: onProgressPulled,
      ),
    );
  }

  @override
  State<RefreshProgressSheet> createState() => _RefreshProgressSheetState();
}

class _RefreshProgressSheetState extends State<RefreshProgressSheet> {
  bool _busy = false;

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  Future<void> _run(Future<void> Function() task, String done) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await task();
      _toast(done);
    } catch (e) {
      _toast('操作失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pull() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final changed = await BookProgressSync.instance.pull();
      await widget.onProgressPulled(changed);
      _toast(changed > 0
          ? '已拉取云端进度，更新 $changed 本书'
          : '云端暂无更新进度');
    } catch (e) {
      _toast('获取云进度失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _push() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ok = await BookProgressSync.instance.push();
      _toast(ok ? '已覆盖上传本地全部书籍进度' : '覆盖云进度失败，请检查 WebDAV 配置');
    } catch (e) {
      _toast('覆盖云进度失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _snapshot() async {
    try {
      final json = await BookProgressSync.instance.snapshotJson();
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final List<dynamic> items = (decoded['progress'] as List<dynamic>?) ?? [];
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('本地进度快照'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Text(
                items.isEmpty
                    ? '暂无进度记录'
                    : items
                        .map((e) =>
                            '${e['bookName']} · 第${(e['chapterIndex'] ?? 0) + 1}章 / 第${(e['pagePos'] ?? 0) + 1}页')
                        .join('\n'),
                style: const TextStyle(fontSize: 13, height: 1.6),
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
          ],
        ),
      );
    } catch (e) {
      _toast('读取快照失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.l, AppSpacing.l, AppSpacing.l, AppSpacing.s),
              child: Row(
                children: [
                  const Icon(Icons.sync_outlined, size: 20),
                  const SizedBox(width: AppSpacing.s),
                  Expanded(
                    child: Text('刷新与云进度 · ${widget.bookName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  if (_busy)
                    const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ),
            ),
            const AppSectionHeader('刷新章节内容'),
            for (final scope in RefreshScope.values)
              ListTile(
                dense: true,
                leading: Icon(refreshScopeIcons[scope], size: 20),
                title: Text(refreshScopeLabels[scope]!),
                subtitle: Text(
                  scope == RefreshScope.toc
                      ? '重新拉取目录并清理全文缓存'
                      : scope == RefreshScope.chapter
                          ? '仅强制重载当前章正文'
                          : '清理当前章及之后全部缓存并重载',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
                onTap: _busy
                    ? null
                    : () => _run(() => widget.onRefresh(scope),
                        '${refreshScopeLabels[scope]}完成'),
              ),
            const Divider(height: 1),
            const AppSectionHeader('云进度（WebDAV）'),
            ListTile(
              dense: true,
              leading: const Icon(Icons.cloud_download_outlined, size: 20),
              title: const Text('获取云进度'),
              subtitle: const Text('拉取较新的远端进度并写回本地',
                  style: TextStyle(fontSize: 11)),
              onTap: _busy ? null : _pull,
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.cloud_upload_outlined, size: 20),
              title: const Text('覆盖云进度'),
              subtitle: const Text('把本地全部书籍进度覆盖上传到云端',
                  style: TextStyle(fontSize: 11)),
              onTap: _busy ? null : _push,
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.data_object_outlined, size: 20),
              title: const Text('查看本地进度快照'),
              onTap: _snapshot,
            ),
            const SizedBox(height: AppSpacing.m),
          ],
        ),
      ),
    );
  }
}
