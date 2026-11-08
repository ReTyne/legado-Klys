/// 由 epub_reader_screen.dart 按「一类一文件」拆出的 _SpineItem。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../epub_reader_screen.dart';


class _SpineItem {
  final String title;
  final String html;
  final String? anchor;
  final String? fileKey;
  const _SpineItem(
      {required this.title, required this.html, this.anchor, this.fileKey});
}
