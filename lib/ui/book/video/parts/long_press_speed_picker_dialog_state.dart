/// 由 video_player_screen.dart 按「一类一文件」拆出的 _LongPressSpeedPickerDialogState。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../video_player_screen.dart';


class _LongPressSpeedPickerDialogState
    extends State<_LongPressSpeedPickerDialog> {
  late int _value = widget.initial
      .clamp(VideoPlayConfig.minSpeedTenths, VideoPlayConfig.maxSpeedTenths);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('长按倍速'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('${(_value / 10).toStringAsFixed(1)}x',
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        Slider(
          min: VideoPlayConfig.minSpeedTenths.toDouble(),
          max: VideoPlayConfig.maxSpeedTenths.toDouble(),
          divisions: VideoPlayConfig.maxSpeedTenths - VideoPlayConfig.minSpeedTenths,
          value: _value.toDouble(),
          label: '${(_value / 10).toStringAsFixed(1)}x',
          onChanged: (v) => setState(() => _value = v.round()),
        ),
        Text('取值范围 0.5x – 6.0x',
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ]),
      actions: [
        TextButton(
          onPressed: () async {
            await VideoPlayConfig.setLongPressSpeed(
                VideoPlayConfig.defaultSpeedTenths);
            if (context.mounted) Navigator.pop(context, VideoPlayConfig.defaultSpeedTenths);
          },
          child: const Text('恢复默认'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () async {
            await VideoPlayConfig.setLongPressSpeed(_value);
            if (context.mounted) Navigator.pop(context, _value);
          },
          child: const Text('确定'),
        ),
      ],
    );
  }
}
