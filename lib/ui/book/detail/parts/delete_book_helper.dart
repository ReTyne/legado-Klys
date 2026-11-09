import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';

/// 删除书籍「同时删除源文件」相关实现。
///
/// 对齐 legado-E `ui/book/info/BookInfoActivity.kt:954` `deleteBook()`：
///  - 仅本地书（`book.isLocal`）出现「删除源文件」复选框
///    （`R.string.delete_book_file`，strings.xml:680）；
///  - 复选框初值来自 `LocalConfig.deleteBookOriginal`，
///    确认后把选择结果写回并据此调用 `delBook(deleteBookOriginal)`；
///  - `BookInfoViewModel.delBook` 里 `LocalBook.deleteBook(it, deleteOriginal)`
///    真正删除源文件。
/// 批量删除（`BookshelfManageActivity.kt:327-344`）同样带该复选框，故抽成
/// 公共助手供详情页与书架长按菜单共用。

/// 对齐 E `LocalConfig.deleteBookOriginal` 的持久化键。
const String kDeleteBookOriginalPref = 'deleteBookOriginal';

/// 解析本地书籍源文件路径（纯函数，便于回归）。
///
/// 本项目 `ImportBookService` 把完整路径存入 `Book.fileName`
/// （如 `.../books/foo.txt`）；部分导入路径把 `bookUrl` 写成
/// `local://<path>`。两种形态都兼容。
String? localBookSourcePath(Book book) {
  final path = book.fileName;
  if (path != null && path.isNotEmpty) return path;
  final url = book.bookUrl;
  if (url != null && url.startsWith('local://')) {
    return url.substring('local://'.length);
  }
  return null;
}

/// 该路径是否可由 dart:io 直接删除。
///
/// 平台差异（显式降级）：Android `content://` / `android.resource://` 等
/// 系统 URI 无法通过 dart:io 的 [File] 删除，需要平台通道 / SAF，
/// 本工程暂无该通道，故对这类源返回 false，`tryDeleteLocalSource` 会跳过
/// 文件删除但不会阻断「移出书架」主流程。
bool canDeleteSourceFile(String? path) {
  if (path == null || path.isEmpty) return false;
  final l = path.toLowerCase();
  if (l.startsWith('content://') || l.startsWith('android.resource://')) {
    return false;
  }
  return true;
}

/// 真正删除本地源文件。返回是否删除成功；不支持/不存在/异常均返回 false，
/// 由调用方仅提示、不阻断 DB 删除。
Future<bool> tryDeleteLocalSource(Book book) async {
  final path = localBookSourcePath(book);
  if (!canDeleteSourceFile(path)) return false;
  try {
    final f = File(path!);
    if (await f.exists()) {
      await f.delete();
      return true;
    }
    return false;
  } catch (_) {
    return false;
  }
}

class DeleteBookChoice {
  final bool confirmed;
  final bool deleteOriginal;

  const DeleteBookChoice(this.confirmed, this.deleteOriginal);
}

/// 删除确认框。本地书额外带「同时删除源文件」复选框，
/// 确认后把选择持久化到 [kDeleteBookOriginalPref]（仅本地书，对齐 E）。
Future<DeleteBookChoice> showDeleteBookConfirm(
  BuildContext context, {
  required Book book,
  String title = '移除书籍',
  String? message,
  String confirmText = '移除',
}) async {
  final prefs = await SharedPreferences.getInstance();
  bool deleteOriginal = prefs.getBool(kDeleteBookOriginalPref) ?? false;
  final isLocal = book.local;
  if (!context.mounted) return const DeleteBookChoice(false, false);
  final result = await showDialog<DeleteBookChoice>(
    context: context,
    builder: (d) => StatefulBuilder(builder: (d, setS) {
      final cs = Theme.of(d).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message ?? '确定要从书架移除《${book.name}》吗？'),
            if (isLocal) ...[
              const SizedBox(height: AppSpacing.s),
              Row(
                children: [
                  Checkbox(
                    value: deleteOriginal,
                    onChanged: (v) =>
                        setS(() => deleteOriginal = v ?? false),
                  ),
                  const Expanded(child: Text('同时删除源文件')),
                ],
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(d, const DeleteBookChoice(false, false)),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: cs.error, foregroundColor: cs.onError),
            onPressed: () =>
                Navigator.pop(d, DeleteBookChoice(true, deleteOriginal)),
            child: Text(confirmText),
          ),
        ],
      );
    }),
  );
  final choice = result ?? const DeleteBookChoice(false, false);
  // E: yesButton { LocalConfig.deleteBookOriginal = checkBox.isChecked }
  if (choice.confirmed && isLocal) {
    await prefs.setBool(kDeleteBookOriginalPref, choice.deleteOriginal);
  }
  return choice;
}

/// 落实删除选择：先删 DB 记录，再按勾选删除源文件。
/// 抽这里是保证「复选框」一定有真实消费点（不是只写不读的假开关）。
Future<void> applyDeleteBookChoice(
  Book book,
  DeleteBookChoice choice,
  Future<void> Function() deleteFromDb,
) async {
  if (!choice.confirmed) return;
  await deleteFromDb();
  if (choice.deleteOriginal && book.local) {
    await tryDeleteLocalSource(book);
  }
}
