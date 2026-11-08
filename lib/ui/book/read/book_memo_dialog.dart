import 'package:flutter/material.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book_memo.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';

/// 阅读菜单「备忘」弹窗（对齐原版 view_read_menu.xml ll_memo → BookMemoDialog）。
///
/// 按「书 + 章」编辑备忘，数据落在 DatabaseService 的 book_memos 表：
/// getBookMemos / upsertBookMemo / deleteBookMemo 三个 DAO 全部真实连通，
/// 不留死开关（feature_gap §3.B3）。
Future<void> showBookMemoDialog(
  BuildContext context, {
  required String bookName,
  required String author,
  required int chapterIndex,
  required String chapterTitle,
}) async {
  final db = DatabaseService();
  List<BookMemo> memos;
  try {
    memos = await db.getBookMemos(bookName, author);
  } catch (_) {
    memos = <BookMemo>[];
  }

  // 当前章已有备忘（同一章只保留一条，取最近更新）
  BookMemo? current;
  for (final m in memos) {
    if (m.chapterIndex == chapterIndex) {
      current = m;
      break;
    }
  }
  final controller = TextEditingController(text: current?.content ?? '');
  if (!context.mounted) {
    controller.dispose();
    return;
  }

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        final others =
            memos.where((m) => m.chapterIndex != chapterIndex).toList();
        return AlertDialog(
          title: Text(chapterTitle.isEmpty
              ? '备忘 · 第${chapterIndex + 1}章'
              : '备忘 · $chapterTitle'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  maxLines: 5,
                  minLines: 3,
                  decoration: const InputDecoration(hintText: '记录本章的备忘...'),
                ),
                if (others.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const AppSectionHeader('本书其它章节的备忘'),
                  ...others.map((m) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          m.chapterTitle.isEmpty
                              ? '第${m.chapterIndex + 1}章'
                              : m.chapterTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(m.content,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: '删除该备忘',
                          onPressed: () async {
                            if (m.id != null) {
                              await db.deleteBookMemo(m.id!);
                              setDialogState(() => memos.remove(m));
                            }
                          },
                        ),
                      )),
                ],
              ],
            ),
          ),
          actions: [
            if (current?.id != null)
              TextButton(
                onPressed: () async {
                  await db.deleteBookMemo(current!.id!);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('删除'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                final text = controller.text.trim();
                final now = DateTime.now().millisecondsSinceEpoch;
                if (text.isEmpty && current?.id != null) {
                  // 内容清空视为删除本章备忘
                  await db.deleteBookMemo(current!.id!);
                } else {
                  await db.upsertBookMemo(BookMemo(
                    id: current?.id,
                    bookName: bookName,
                    author: author,
                    chapterIndex: chapterIndex,
                    chapterTitle: chapterTitle,
                    content: text,
                    createTime: current?.createTime ?? now,
                    updateTime: now,
                  ));
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    ),
  );
  controller.dispose();
}
