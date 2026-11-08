/// 由 audio_playback_controller.dart 按「一类一文件」拆出的 AudioResumePoint。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../audio_playback_controller.dart';


/// 断点续听读取结果：片段下标 + 片段内位置。
class AudioResumePoint {
  final int segment;
  final Duration position;
  const AudioResumePoint(this.segment, this.position);
}
