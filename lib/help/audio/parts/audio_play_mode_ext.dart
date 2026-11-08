/// 由 audio_playback_controller.dart 按「一类一文件」拆出的 AudioPlayModeExt。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../audio_playback_controller.dart';


extension AudioPlayModeExt on AudioPlayMode {
  String get label =>
      const ['顺序播放', '单曲循环', '随机播放', '列表循环'][index];

  IconData get icon => const [
        Icons.playlist_play,
        Icons.repeat_one,
        Icons.shuffle,
        Icons.repeat,
      ][index];

  AudioPlayMode get next =>
      AudioPlayMode.values[(index + 1) % AudioPlayMode.values.length];
}
