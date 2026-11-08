/// 由 video_player_screen.dart 按「一类一文件」拆出的 _LongPressSpeedPickerDialog。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../video_player_screen.dart';


/// 长按倍速选择对话框（对齐 E SettingsDialog 的 NumberPickerDialog：
/// 取值 0.5x–6.0x，步进 0.1x，默认 3.0x，可一键恢复默认）。
class _LongPressSpeedPickerDialog extends StatefulWidget {
  final int initial;
  const _LongPressSpeedPickerDialog({required this.initial});

  @override
  State<_LongPressSpeedPickerDialog> createState() =>
      _LongPressSpeedPickerDialogState();
}
