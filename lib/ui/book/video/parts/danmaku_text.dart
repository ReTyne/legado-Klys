/// 由 video_player_screen.dart 按「一类一文件」拆出的 _DanmakuText。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../video_player_screen.dart';


/// 单条弹幕：按 type 滚动（1 右→左 / 6 左→右）或固定（5 顶 / 4 底）。
class _DanmakuText extends StatefulWidget {
  final _DanmakuItem item;
  final double opacity;
  final double fontSize;
  const _DanmakuText({
    super.key,
    required this.item,
    required this.opacity,
    required this.fontSize,
  });

  @override
  State<_DanmakuText> createState() => _DanmakuTextState();
}
