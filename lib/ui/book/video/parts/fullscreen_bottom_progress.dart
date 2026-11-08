/// 由 video_player_screen.dart 按「一类一文件」拆出的 _FullscreenBottomProgress。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../video_player_screen.dart';


/// 全屏底部细进度条（E: GSY fullBottomProgressBar）：
/// 自监听控制器位置变化局部刷新，避免整页重建。
class _FullscreenBottomProgress extends StatefulWidget {
  final VideoPlayerController? controller;
  const _FullscreenBottomProgress(this.controller);

  @override
  State<_FullscreenBottomProgress> createState() =>
      _FullscreenBottomProgressState();
}
