/// 由 theme_manage_screen.dart 按「一类一文件」拆出的 _HsvColorPickerDialog。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../theme_manage_screen.dart';


/// Flutter 自带 HSV 取色对话框：Hue/Saturation/Value 三条滑块 + 明暗预览，不依赖三方色盘包
class _HsvColorPickerDialog extends StatefulWidget {
  final Color initial;
  const _HsvColorPickerDialog({this.initial = const Color(0xFF6750A4)});

  @override
  State<_HsvColorPickerDialog> createState() => _HsvColorPickerDialogState();
}
