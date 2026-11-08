/// 由 qr_share_screen.dart 按「一类一文件」拆出的 QrCode。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../qr_share_screen.dart';


/// 二维码矩阵（不含静默区）。modules[row][col] 为 true 表示深色模块。
class QrCode {
  final int size;
  final List<List<bool>> modules;

  const QrCode(this.size, this.modules);

  /// 导出 PNG 图片字节（8 位灰度，deflate 使用无压缩存储块，零第三方依赖）
  Uint8List toPngBytes({int scale = 10, int quietZone = 4}) =>
      QrEncoder._encodePng(modules, scale: scale, quietZone: quietZone);
}
