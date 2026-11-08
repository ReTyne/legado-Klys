/// 由 video_player_screen.dart 按「一类一文件」拆出的 _DanmakuItem。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../video_player_screen.dart';


/// 单条弹幕数据（兼容 B 站 DanmakuItem 的颜色 / 字号 / 类型）。
class _DanmakuItem {
  final double time;
  final String text;
  final int color;
  final double size;
  final int type;
  const _DanmakuItem(this.time, this.text,
      {this.color = 0xFFFFFFFF, this.size = 25, this.type = 1});
}
