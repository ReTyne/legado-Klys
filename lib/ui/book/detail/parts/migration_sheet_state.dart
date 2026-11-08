/// 由 change_source_screen.dart 按「一类一文件」拆出的 _MigrationSheetState。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../change_source_screen.dart';


class _MigrationSheetState extends State<_MigrationSheet> {
  late final _MigrationOptions _opt =
      _MigrationOptions(keepProgress: widget.hasMatch);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text('换源迁移选项',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text('《${widget.bookName}》→ ${widget.sourceName}',
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurfaceVariant)),
                ),
                const Divider(height: 1),
                ListTile(
                  dense: true,
                  leading: Icon(
                    widget.hasMatch
                        ? Icons.my_location
                        : Icons.warning_amber_outlined,
                    color: widget.hasMatch ? cs.primary : cs.error,
                  ),
                  title: Text(widget.hasMatch
                      ? '已匹配到章节「${widget.matchedTitle}」'
                      : '未匹配到对应章节，将从头开始'),
                  subtitle: const Text('按章节标题归一化在新源目录中定位'),
                ),
                SwitchListTile(
                  title: const Text('保留阅读进度'),
                  subtitle: Text(widget.hasMatch
                      ? '跳到匹配章节；关闭则从第 1 章开始'
                      : '无匹配章节，该选项不可用'),
                  value: _opt.keepProgress && widget.hasMatch,
                  onChanged: widget.hasMatch
                      ? (v) => setState(() => _opt.keepProgress = v)
                      : null,
                ),
                SwitchListTile(
                  title: const Text('保留章内阅读位置'),
                  subtitle: const Text('沿用当前章节内的页 / 字符偏移'),
                  value: _opt.keepPagePos &&
                      _opt.keepProgress &&
                      widget.hasMatch,
                  onChanged: (_opt.keepProgress && widget.hasMatch)
                      ? (v) => setState(() => _opt.keepPagePos = v)
                      : null,
                ),
                SwitchListTile(
                  title: Text('迁移书签（${widget.bookmarkCount} 条）'),
                  subtitle: const Text('按章节标题重新映射到新目录'),
                  value: _opt.migrateBookmarks && widget.bookmarkCount > 0,
                  onChanged: widget.bookmarkCount > 0
                      ? (v) => setState(() => _opt.migrateBookmarks = v)
                      : null,
                ),
                SwitchListTile(
                  title:
                      Text('迁移划线 / 高亮（${widget.highlightCount} 条）'),
                  subtitle: const Text('按章节标题重新映射，保留颜色与批注'),
                  value: _opt.migrateHighlights && widget.highlightCount > 0,
                  onChanged: widget.highlightCount > 0
                      ? (v) => setState(() => _opt.migrateHighlights = v)
                      : null,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Text(
                    '无法匹配到新章节的书签 / 高亮会原样保留，不会丢失。',
                    style: TextStyle(
                        fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('取消')),
                      const SizedBox(width: 8),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, _opt),
                          child: const Text('确定换源')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
