import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// 通用二维码/条码扫描页，扫描成功后 pop 返回识别到的文本
class QrScannerScreen extends StatefulWidget {
  final String title;
  const QrScannerScreen({super.key, this.title = '扫描二维码'});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture cap) {
    if (_handled) return;
    final code = cap.barcodes.isNotEmpty ? cap.barcodes.first.rawValue : null;
    if (code != null && code.isNotEmpty) {
      _handled = true;
      Navigator.pop(context, code);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(icon: const Icon(Icons.flash_on), tooltip: '闪光灯',
            onPressed: () => _controller.toggleTorch()),
          IconButton(icon: const Icon(Icons.cameraswitch), tooltip: '切换镜头',
            onPressed: () => _controller.switchCamera()),
        ],
      ),
      body: Stack(alignment: Alignment.center, children: [
        MobileScanner(controller: _controller, onDetect: _onDetect),
        // 取景框
        Container(width: 240, height: 240,
          decoration: BoxDecoration(border: Border.all(color: Colors.white.withOpacity(0.8), width: 3), borderRadius: BorderRadius.circular(12))),
        Positioned(bottom: 48, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
          child: const Text('将二维码放入框内自动识别', style: TextStyle(color: Colors.white, fontSize: 13)),
        )),
      ]),
    );
  }
}
