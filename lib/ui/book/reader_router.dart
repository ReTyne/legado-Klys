import 'package:flutter/material.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/ui/book/audio/audio_player_screen.dart';
import 'package:legado_md3/ui/book/manga/manga_reader_screen.dart';
import 'package:legado_md3/ui/book/read/reading_screen.dart';

/// 统一阅读入口路由：根据书籍类型分流到对应的阅读器页面。
///
/// * [Book.typeText]  / [Book.typeLocal] -> [ReadingScreen]（文本阅读器）
/// * [Book.typeAudio]                    -> [AudioPlayerScreen]（有声书播放器）
/// * [Book.typeImage]                    -> [MangaReaderScreen]（漫画/图片阅读器）
///
/// [initialChapter] 指定起始章节（音频书为起始音频下标）；为空时回退到书籍
/// 已保存的阅读进度 [Book.durChapterIndex]。
Widget readerForBook(Book book, {int? initialChapter}) {
  final start = initialChapter ?? book.durChapterIndex;
  switch (book.type) {
    case Book.typeAudio:
      return AudioPlayerScreen(book: book, initialIndex: start);
    case Book.typeImage:
      return MangaReaderScreen(book: book, initialChapter: start);
    default:
      return ReadingScreen(book: book, initialChapter: initialChapter);
  }
}
