/// 由 change_source_screen.dart 按「一类一文件」拆出的 _SourceResult。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../change_source_screen.dart';


class _SourceResult {
  BookSource source;
  SearchBook? match;
  bool searching = true;
  String? error;
  _SourceResult(this.source);
}
