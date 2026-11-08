/// 由 video_player_screen.dart 按「一类一文件」拆出的 _VideoResume。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../video_player_screen.dart';


/// 断点续听读取结果：线路下标 + 位置。
class _VideoResume {
  final int line;
  final Duration position;
  const _VideoResume(this.line, this.position);
}
