/// 由 theme_manage_screen.dart 按「一类一文件」拆出的 _Preset。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../theme_manage_screen.dart';


/// 预设主题色
class _Preset {
  final String name;
  final int primary;
  final int accent;
  const _Preset(this.name, this.primary, this.accent);
}

/// 预设主题色（低饱和方案：松烟墨蓝 0xFF3F5A72 / 黛绿 0xFF38624A /
/// 暖杏棕 0xFF7A5C4E / 黛青 0xFF2B5C8A 及其同族 muted 衍生色）。
/// 替换旧版高饱和黄 0xFFF9A825 / 橙红 0xFFE64A19 / 正红 0xFFC62828 等，
/// 数量与名称结构不变；蓝灰、深灰原值本已低饱和，予以保留。
const List<_Preset> _presets = [
  _Preset('默认紫', 0xFF3F5A72, 0xFF5B7183), // 松烟墨蓝（与 AppTheme 默认 seed 一致）
  _Preset('蓝色', 0xFF2B5C8A, 0xFF3D6CA3), // 黛青
  _Preset('青色', 0xFF2F5D5A, 0xFF3F726E), // 黛青衍生青灰
  _Preset('绿色', 0xFF38624A, 0xFF4C7C60), // 黛绿
  _Preset('酸橙', 0xFF5C6B3F, 0xFF72844D), // 黛绿衍生橄榄
  _Preset('黄色', 0xFF8A7A52, 0xFFA3906A), // 暖杏棕衍生暗金
  _Preset('橙色', 0xFF8A5A3B, 0xFFA26B48), // 暖杏棕衍生赤陶
  _Preset('棕色', 0xFF7A5C4E, 0xFF92705F), // 暖杏棕
  _Preset('红色', 0xFF8A4A42, 0xFFA25C52), // 砖红（低饱和）
  _Preset('粉色', 0xFF8A5560, 0xFFA26A74), // 暗玫瑰
  _Preset('紫色', 0xFF5E4A6E, 0xFF775C88), // 灰紫
  _Preset('靛蓝', 0xFF3A3F6B, 0xFF4B5183), // 黛青衍生靛青
  _Preset('蓝灰', 0xFF37474F, 0xFF455A64),
  _Preset('深灰', 0xFF212121, 0xFF424242),
];
