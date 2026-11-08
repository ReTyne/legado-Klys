/// 由 theme_manage_screen.dart 按「一类一文件」拆出的 _HsvColorPickerDialogState。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../theme_manage_screen.dart';


class _HsvColorPickerDialogState extends State<_HsvColorPickerDialog> {
  late HSVColor _hsv;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initial);
  }

  Color get _color => _hsv.toColor();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('自定义颜色'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: double.infinity, height: 56,
          decoration: BoxDecoration(color: _color, borderRadius: BorderRadius.circular(12)),
          child: Center(child: Text('#${(_hsv.toColor().value & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0')}',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
        ),
        const SizedBox(height: 8),
        _hsvSlider('色相 H', _hsv.hue, 0.0, 360.0, Theme.of(context).sliderTheme.activeTrackColor ?? cs.primary,
          (v) => setState(() => _hsv = _hsv.withHue(v))),
        _hsvSlider('饱和度 S', _hsv.saturation, 0.0, 1.0, cs.onSurfaceVariant,
          (v) => setState(() => _hsv = _hsv.withSaturation(v))),
        _hsvSlider('明度 V', _hsv.value, 0.0, 1.0, cs.onSurfaceVariant,
          (v) => setState(() => _hsv = _hsv.withValue(v))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(context, _color), child: const Text('确定')),
      ],
    );
  }

  Widget _hsvSlider(String label, double value, double min, double max, Color color, ValueChanged<double> onChanged) {
    return Row(children: [
      SizedBox(width: 64, child: Text(label, style: const TextStyle(fontSize: 11))),
      Expanded(
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(activeTrackColor: color, thumbColor: color, inactiveTrackColor: Theme.of(context).colorScheme.outlineVariant),
          child: Slider(value: value, min: min, max: max, onChanged: onChanged),
        ),
      ),
    ]);
  }
}
