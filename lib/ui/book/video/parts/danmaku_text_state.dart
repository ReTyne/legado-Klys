/// 由 video_player_screen.dart 按「一类一文件」拆出的 _DanmakuTextState。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../video_player_screen.dart';


class _DanmakuTextState extends State<_DanmakuText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(vsync: this, duration: const Duration(seconds: 6))
      ..forward();
    _ac.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.item;
    final screen = MediaQuery.of(context).size;
    final fixedTop = d.type == 5;
    final fixedBottom = d.type == 4;
    final fixed = fixedTop || fixedBottom;
    final reverse = d.type == 6;
    final lane = (d.text.hashCode % 8).abs().toDouble();
    final scaled =
        (widget.fontSize * (d.size / 25.0).clamp(0.6, 1.8)).toDouble();
    final textWidth = d.text.length * scaled * 0.7;
    return AnimatedBuilder(
      animation: _ac,
      builder: (_, __) {
        final t = _ac.value;
        final top = fixed
            ? (fixedTop
                ? 16.0 + lane * 22
                : (screen.height - 48 - lane * 22).clamp(0.0, screen.height))
            : 16.0 + lane * 22;
        final left = fixed
            ? ((screen.width - textWidth) / 2).clamp(0.0, screen.width)
            : (reverse
                ? (screen.width + textWidth) * t - textWidth
                : (screen.width + textWidth) * (1 - t));
        return Positioned(
          top: top,
          left: left,
          child: Opacity(
            opacity: widget.opacity.clamp(0.0, 1.0),
            child: Text(
              d.text,
              style: TextStyle(
                color: Color(d.color),
                fontSize: scaled,
                shadows: const [Shadow(color: Colors.black, blurRadius: 2)],
              ),
            ),
          ),
        );
      },
    );
  }
}
