import 'package:flutter/material.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/ui/book/audio/audio_player_screen.dart';
import 'package:legado_md3/ui/book/manga/manga_reader_screen.dart';
import 'package:legado_md3/ui/book/video/video_player_screen.dart';
import 'package:legado_md3/ui/book/read/pdf_reader_screen.dart';
import 'package:legado_md3/ui/book/read/reading_screen.dart';

/// 漫画界面开关（oc_showMangaUi），启动时由 main() 初始化，阅读路由据此分流。
bool showMangaUi = true;

/// 判断是否为 PDF 本地书：本地书统一标记为 [Book.typeLocal]（1），
/// 需再按 [Book.fileName] 的扩展名区分 PDF 与 txt/epub/mobi 等。
bool isPdfBook(Book book) {
  final fileName = book.fileName;
  return fileName != null &&
      fileName.isNotEmpty &&
      fileName.toLowerCase().endsWith('.pdf');
}

/// 统一阅读入口路由：根据书籍类型分流到对应的阅读器页面。
///
/// * [Book.typeText]  / [Book.typeLocal] -> [ReadingScreen]（文本阅读器）
/// * [Book.typeAudio]                    -> [AudioPlayerScreen]（有声书播放器）
/// * [Book.typeImage]                    -> [MangaReaderScreen]（漫画/图片阅读器，
///                                         关闭「显示漫画界面」时退回文本阅读器）
/// * [Book.typeVideo]                    -> [VideoPlayerScreen]（视频播放器，含弹幕）
/// * 本地 PDF 书（[isPdfBook]）            -> [PdfReaderScreen]（PDF 位图分页阅读器）
///
/// [initialChapter] 指定起始章节（音频/视频书为起始集数下标）；为空时回退到书籍
/// 已保存的阅读进度 [Book.durChapterIndex]。
Widget readerForBook(Book book, {int? initialChapter}) {
  final start = initialChapter ?? book.durChapterIndex;
  // PDF 本地书优先分流到 PDF 阅读器（type 与普通本地书相同，需按文件名判断）
  if (isPdfBook(book)) {
    return PdfReaderScreen(book: book);
  }
  switch (book.type) {
    case Book.typeAudio:
      return AudioPlayerScreen(book: book, initialIndex: start);
    case Book.typeImage:
      return showMangaUi
          ? MangaReaderScreen(book: book, initialChapter: start)
          : ReadingScreen(book: book, initialChapter: initialChapter);
    case Book.typeVideo:
      return VideoPlayerScreen(book: book, initialChapter: start);
    default:
      return ReadingScreen(book: book, initialChapter: initialChapter);
  }
}
