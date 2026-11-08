import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:epubx/epubx.dart' as epub;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/help/storage/book_progress_sync.dart';
import 'package:legado_md3/ui/book/read/reading_screen.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';

part 'parts/fragment_ids.dart';
part 'parts/spine_item.dart';
part 'parts/epub_reader_screen_state.dart';


/// EPUB 保版式阅读器（对齐 fork NG 的 EPUB 阅读，采用「EPUB → HTML + WebView」折中）。
///
/// 与「解析成纯文本走通用阅读器」的路线不同，这里：
/// * 用 `epubx` 读出 XHTML 章节、原书 CSS、图片字节；
/// * 把 CSS 内联、图片转成 data URI，保留原书排版与 `id` fragment；
/// * 用 `InAppWebView` 渲染，支持章内 fragment 跳转与滚动进度记忆；
/// * 接入 `book_chapters.startFragmentId / endFragmentId`（v14 补列）定位章节边界。
///
/// 主代理接线：`reader_router.dart` 里对本地 `.epub` 书返回
/// [EpubReaderScreen]（或调用 [EpubReaderScreen.open]）。
class EpubReaderScreen extends StatefulWidget {
  final Book book;
  final int initialChapter;

  const EpubReaderScreen(
      {super.key, required this.book, this.initialChapter = 0});

  /// 该书籍是否是可直接打开的本地 EPUB。
  static bool canOpen(Book book) {
    final path = localPathOf(book);
    return path != null && path.toLowerCase().endsWith('.epub');
  }

  /// 本地 EPUB 文件路径（本地书导入时路径落在 `Book.fileName`）。
  static String? localPathOf(Book book) {
    for (final candidate in [book.fileName, book.bookUrl, book.noteUrl]) {
      if (candidate == null) continue;
      var v = candidate;
      if (v.startsWith('file://')) v = v.substring(7);
      if (v.isEmpty) continue;
      if (v.toLowerCase().endsWith('.epub') || File(v).existsSync()) return v;
    }
    return null;
  }

  /// 统一路由入口，供阅读页菜单 / 路由表调用。
  static Future<void> open(BuildContext context, Book book,
          {int? initialChapter}) =>
      Navigator.of(context).push<void>(MaterialPageRoute<void>(
        builder: (_) => EpubReaderScreen(
          book: book,
          initialChapter: initialChapter ?? book.durChapterIndex,
        ),
      ));

  @override
  State<EpubReaderScreen> createState() => _EpubReaderScreenState();
}
