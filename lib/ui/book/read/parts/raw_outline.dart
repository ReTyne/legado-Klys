/// 由 pdf_reader_screen.dart 按「一类一文件」拆出的 _RawOutline。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../pdf_reader_screen.dart';


class _RawOutline {
  const _RawOutline(this.title, this.level, this.page);
  final String title;
  final int level;
  final int? page;
}
