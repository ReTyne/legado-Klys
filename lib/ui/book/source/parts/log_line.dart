/// 由 source_debug_screen.dart 按「一类一文件」拆出的 _LogLine。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../source_debug_screen.dart';


class _LogLine {
  _LogLine(this.text, this.level);
  final String text;
  final _LogLevel level;
}
