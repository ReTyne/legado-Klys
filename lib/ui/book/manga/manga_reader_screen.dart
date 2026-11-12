import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_chapter.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/help/source/source_engine.dart';
import 'package:legado_md3/help/storage/book_progress_sync.dart';
import 'package:legado_md3/help/translate/manga_translate_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/ui/theme/app_design.dart';
part 'parts/manga_reader_screen_state.dart';
part 'parts/manga_image.dart';
part 'parts/manga_image_state.dart';

/// 当前翻页模式的总页数：单页=图片数；双页=相邻两页拼一屏（ceil(n/2)）。
/// 补齐双页拼合，抽成顶层纯函数便于离线单测。
int mangaPageCount(int imageCount, bool doublePage) =>
    doublePage ? (imageCount + 1) ~/ 2 : imageCount;

/// 双页模式第 [pageIndex] 屏对应的图片下标：正常两张 [左, 右]，奇数张时最后一屏仅 [左]。
/// 补齐双页拼合，抽成顶层纯函数便于离线单测。
List<int> mangaDoublePageIndices(int pageIndex, int imageCount) {
  final left = 2 * pageIndex;
  if (left >= imageCount) return const [];
  return left + 1 < imageCount ? [left, left + 1] : [left];
}



/// 漫画阅读器（图片书源 / 条漫）。
///
/// 图片获取策略（增量修复）：
/// 1. 先解析章节缓存 `chapter.content` 中的 `<img src>`（兼容旧缓存/本地漫画）；
/// 2. 缓存为空时调用书源引擎 `BookSourceEngine.getImageContent` 拉取图片 URL 列表，
///    并写回 `chapter.content` 缓存，下次阅读走本地缓存。
class MangaReaderScreen extends StatefulWidget {
  final Book book;
  final int initialChapter;
  const MangaReaderScreen({super.key, required this.book, this.initialChapter = 0});

  @override
  State<MangaReaderScreen> createState() => _MangaReaderScreenState();
}
