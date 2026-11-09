/// 由 source_manage_screen.dart 拆分还原（历史合并点）。
/// 以 part 形式归属同一库，私有成员互通，外部 import 路径不变。
part of 'source_manage_screen.dart';


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

  /// 从相册选择图片识别二维码
  Future<void> _pickFromGallery() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      final path = result?.files.single.path;
      if (path == null || !mounted) return;
      final ok = await _controller.analyzeImage(path);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未能从图片中识别出二维码')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('读取图片失败')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(icon: const Icon(Icons.photo_library_outlined), tooltip: '从相册选择',
            onPressed: _pickFromGallery),
          IconButton(icon: const Icon(Icons.flash_on_outlined), tooltip: '闪光灯',
            onPressed: () => _controller.toggleTorch()),
          IconButton(icon: const Icon(Icons.cameraswitch_outlined), tooltip: '切换镜头',
            onPressed: () => _controller.switchCamera()),
        ],
      ),
      body: Stack(alignment: Alignment.center, children: [
        MobileScanner(controller: _controller, onDetect: _onDetect),
        // 取景框与提示条叠加在实时相机预览上，背景明暗不可控，
        // 故固定高对比「白描边 / 半透黑底白字」，不随主题反色（功能性例外）。
        Container(width: 240, height: 240,
          decoration: BoxDecoration(border: Border.all(color: Colors.white.withOpacity(0.8), width: 3), borderRadius: AppRadius.mAll)),
        Positioned(bottom: 48, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l, vertical: AppSpacing.s),
          decoration: const BoxDecoration(color: Colors.black54, borderRadius: AppRadius.mAll),
          child: const Text('将二维码放入框内自动识别', style: TextStyle(color: Colors.white, fontSize: 13)),
        )),
      ]),
    );
  }
}
