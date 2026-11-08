/// 由 qr_share_screen.dart 按「一类一文件」拆出的 _QrPainter。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../qr_share_screen.dart';


/// 二维码绘制（含 2 模块静默区）。
/// 二维码为功能性编码：固定白底 + 深色模块，保证任意主题下均可被扫码，
/// 不随 ColorScheme 反色。
class _QrPainter extends CustomPainter {
  final QrCode qr;
  final Color color;
  const _QrPainter(this.qr, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = Colors.white;
    canvas.drawRect(Offset.zero & size, bg);
    final n = qr.size;
    const qz = 2;
    final cell = size.width / (n + qz * 2);
    final dark = Paint()
      ..color = color
      ..isAntiAlias = false;
    for (var row = 0; row < n; row++) {
      for (var col = 0; col < n; col++) {
        if (!qr.modules[row][col]) continue;
        final dx = (col + qz) * cell;
        final dy = (row + qz) * cell;
        // 轻微外扩避免亚像素缝隙
        canvas.drawRect(
            Rect.fromLTWH(dx - 0.05, dy - 0.05, cell + 0.1, cell + 0.1), dark);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrPainter old) =>
      old.qr != qr || old.color != color;
}
