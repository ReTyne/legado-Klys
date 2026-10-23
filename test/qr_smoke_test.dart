import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/ui/book/source/qr_share_screen.dart';

void main() {
  test('QR 编码生成合法 PNG', () {
    final qr = QrEncoder.encode('https://github.com/ReTyne/legado-Klys');
    final png = qr.toPngBytes(scale: 8, quietZone: 4);
    expect(png.length, greaterThan(8));
    expect(png[0], 0x89);
    expect(png[1], 0x50);
    expect(png[2], 0x4E);
    expect(png[3], 0x47);
  });
  test('QR 空串不崩溃', () {
    expect(() => QrEncoder.encode(''), returnsNormally);
  });
}
