/// 由 qr_share_screen.dart 按「一类一文件」拆出的 QrShareScreen。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../qr_share_screen.dart';


/// 书源二维码分享页：把书源 JSON 编码为二维码展示，可导出 PNG 分享或复制 JSON
class QrShareScreen extends StatefulWidget {
  final BookSource source;
  const QrShareScreen({super.key, required this.source});

  @override
  State<QrShareScreen> createState() => _QrShareScreenState();
}
