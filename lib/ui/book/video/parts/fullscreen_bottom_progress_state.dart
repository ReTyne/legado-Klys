/// 由 video_player_screen.dart 按「一类一文件」拆出的 _FullscreenBottomProgressState。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../video_player_screen.dart';


class _FullscreenBottomProgressState
    extends State<_FullscreenBottomProgress> {
  VideoPlayerController? _bound;
  double _value = 0;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(covariant _FullscreenBottomProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) _bind();
  }

  void _bind() {
    _bound?.removeListener(_onUpdate);
    _bound = widget.controller;
    _bound?.addListener(_onUpdate);
    _onUpdate();
  }

  void _onUpdate() {
    final c = _bound;
    if (c == null || !c.value.isInitialized) return;
    final dur = c.value.duration.inMilliseconds;
    final pos = c.value.position.inMilliseconds;
    final v = dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0.0;
    if ((v - _value).abs() > 0.001 && mounted) setState(() => _value = v);
  }

  @override
  void dispose() {
    _bound?.removeListener(_onUpdate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LinearProgressIndicator(
      value: _value,
      minHeight: 2,
      backgroundColor: Colors.transparent,
      color: Colors.white70,
    );
  }
}
