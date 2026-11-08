/// 由 bookshelf_screen.dart 按「一类一文件」拆出的 _CoverCfg。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../bookshelf_screen.dart';


/// 封面配置（来自 SharedPreferences，由封面配置页 CoverConfigScreen 写入）
class _CoverCfg {
  /// cover_onlyWifi：仅在 WiFi 下加载网络封面。
  /// 由 NetworkMonitor.isWifi（原生 ConnectivityManager 通道 legado/network）
  /// 精确判断；非 Android 平台回退为不加载网络封面（保守）。
  final bool onlyWifi;
  /// cover_showName / cover_showAuthor：封面区域叠加显示书名 / 作者。
  /// 叠加文字统一交给 BookCover.overlay（白色随组件自带渐变墨层），不再引入
  /// cover_defaultColor / cover_dayTextColor / cover_nightTextColor 这套第二套
  /// 封面配色；默认占位统一由 DefaultCover（defaultCoverPalette）承担。
  final bool showName;
  final bool showAuthor;

  const _CoverCfg({
    this.onlyWifi = false,
    this.showName = true,
    this.showAuthor = true,
  });

  static Future<_CoverCfg> load() async {
    final p = await SharedPreferences.getInstance();
    return _CoverCfg(
      onlyWifi: p.getBool('cover_onlyWifi') ?? false,
      showName: p.getBool('cover_showName') ?? true,
      showAuthor: p.getBool('cover_showAuthor') ?? true,
    );
  }
}
