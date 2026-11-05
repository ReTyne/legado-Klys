import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:legado_md3/data/model/bookmark.dart';

/// 书签导出（对齐 legado-E TocViewModel.saveBookmark / saveBookmarkMd）：
/// JSON 为全字段列表；Markdown 为 `## 书名 作者` + 每条 `#### 章节`/`###### 原文`/`###### 摘要`。
/// 目录页书签 Tab（E: menu_export_bookmark / menu_export_md）与书签页共用，避免两处重复实现。
Future<File> exportBookmarks(
  List<Bookmark> bookmarks, {
  String? bookName,
  String? bookAuthor,
  required bool markdown,
}) async {
  final name = bookName ?? '全部书签';
  final author = bookAuthor ?? '';
  final fileName =
      'bookmark-$name${author.isNotEmpty ? ' $author' : ''}.${markdown ? 'md' : 'json'}';
  String content;
  if (markdown) {
    final buffer = StringBuffer();
    buffer.writeln('## $name $author');
    buffer.writeln();
    for (final b in bookmarks) {
      buffer.writeln('#### ${b.chapterTitle}');
      buffer.writeln();
      buffer.writeln('###### 原文');
      buffer.writeln(' ${b.content ?? ''}');
      buffer.writeln();
      buffer.writeln('###### 摘要');
      buffer.writeln(' ');
      buffer.writeln();
    }
    content = buffer.toString();
  } else {
    content = const JsonEncoder.withIndent('  ')
        .convert(bookmarks.map((b) => b.toMap()).toList());
  }
  final dir = await getApplicationDocumentsDirectory();
  final exportDir = Directory('${dir.path}/export');
  if (!exportDir.existsSync()) exportDir.createSync(recursive: true);
  final safeName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  final file = File('${exportDir.path}/$safeName');
  await file.writeAsString(content);
  return file;
}
