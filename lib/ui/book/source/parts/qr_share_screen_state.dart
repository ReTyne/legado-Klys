/// 由 qr_share_screen.dart 按「一类一文件」拆出的 _QrShareScreenState。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../qr_share_screen.dart';


class _QrShareScreenState extends State<QrShareScreen> {
  late final String _json;
  QrCode? _qr;
  bool _compact = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _json = const JsonEncoder.withIndent('  ').convert(widget.source.toJson());
    try {
      _qr = QrEncoder.encode(_json);
    } on QrEncodeException {
      // 完整 JSON 超长时退化用精简字段（省略空值），导入端可正常还原
      try {
        final compact = jsonEncode(_compactSourceJson(widget.source));
        _qr = QrEncoder.encode(compact);
        _compact = true;
      } on QrEncodeException catch (e) {
        _error = e.toString();
      }
    }
  }

  /// 仅保留非空/非默认字段的精简书源 JSON
  Map<String, dynamic> _compactSourceJson(BookSource source) {
    final compact = <String, dynamic>{};
    source.toJson().forEach((key, value) {
      if (value == null) return;
      if (value is String && value.isEmpty) return;
      if (value is Map && value.isEmpty) return;
      compact[key] = value;
    });
    return compact;
  }

  Future<void> _shareImage() async {
    final qr = _qr;
    if (qr == null) return;
    try {
      final bytes = qr.toPngBytes(scale: 10, quietZone: 4);
      final file = File(
          '${Directory.systemTemp.path}/source_qr_${widget.source.bookSourceUrl.hashCode.abs()}.png');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)],
          text: '书源二维码：${widget.source.bookSourceName}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导出图片失败: $e')));
      }
    }
  }

  Future<void> _copyJson() async {
    await Clipboard.setData(ClipboardData(text: _json));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('书源 JSON 已复制到剪贴板')));
    }
  }

  /// 扫码导入：复用 QrScannerScreen 识别二维码，内容交给
  /// DeepLinkService.importRaw 自动识别类型并落库，与「二维码分享」形成双向闭环。
  Future<void> _scanImport() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const QrScannerScreen(title: '扫描导入二维码'),
      ),
    );
    if (code == null || code.trim().isEmpty) return;
    try {
      await DeepLinkService.instance.importRaw(code.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('扫码内容已提交导入')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败：$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final qr = _qr;
    return Scaffold(
      appBar: AppBar(
        title: const Text('二维码分享'),
        actions: [
          IconButton(
              icon: const Icon(Icons.qr_code_scanner_outlined),
              tooltip: '扫码导入',
              onPressed: _scanImport),
          IconButton(
              icon: const Icon(Icons.copy_all_outlined),
              tooltip: '复制 JSON',
              onPressed: _copyJson),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: qr == null
                    ? _buildErrorState()
                    // 二维码必须保持「浅底深模块」的高对比度才能被扫码器识别，
                    // 故此处固定浅色底，不随主题反色；其余容器仍走主题语义色。
                    : DecoratedBox(
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: AppRadius.lAll,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.m),
                          child: SizedBox(
                            width: 300,
                            height: 300,
                            child: CustomPaint(
                              painter: _QrPainter(qr, Colors.black),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: AppSpacing.m),
            Card(
              color: theme.colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.m),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.source.bookSourceName,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: AppSpacing.xs),
                    Text('JSON 大小：${_json.length} 字节',
                        style: theme.textTheme.bodySmall),
                    Text('二维码版本：${(qr != null ? (qr.size - 17) ~/ 4 : '-')}（纠错等级 M）',
                        style: theme.textTheme.bodySmall),
                    if (_compact)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: Text('书源字段较多，二维码内为精简 JSON（省略空字段），可正常导入',
                            style: TextStyle(fontSize: 11, color: theme.colorScheme.tertiary)),
                      ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: Text(_error!,
                            style: TextStyle(fontSize: 11, color: theme.colorScheme.error)),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.m),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('分享二维码图片'),
                    onPressed: qr == null ? null : _shareImage,
                  ),
                ),
                const SizedBox(width: AppSpacing.m),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.content_copy_outlined),
                    label: const Text('复制 JSON'),
                    onPressed: _copyJson,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return const AppEmptyState(
      icon: Icons.qr_code_2_outlined,
      title: '无法生成二维码',
      message: '书源 JSON 超出二维码（版本 10 / 纠错 M）容量上限，请改用「复制 JSON」或分享 JSON 文本。',
    );
  }
}
