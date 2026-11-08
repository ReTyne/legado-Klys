/// 由 manga_reader_screen.dart 按「一类一文件」拆出的 _MangaImageState。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../manga_reader_screen.dart';


class _MangaImageState extends State<_MangaImage> {
  final TransformationController _transformController = TransformationController();
  // 仅缩放倍数大于 1 时开放平移，未缩放时把手势交还给外层滚动/翻页
  bool _panEnabled = false;

  @override
  void initState() {
    super.initState();
    _transformController.addListener(_onTransform);
  }

  @override
  void dispose() {
    _transformController.removeListener(_onTransform);
    _transformController.dispose();
    super.dispose();
  }

  /// 从变换矩阵估算当前缩放倍数是否大于 1。
  /// （该版本 vector_math 无 getMaxScaledValue，手动取 X 轴缩放平方与 1 比较）
  bool _isZoomed(Matrix4 m) {
    final s = m.storage;
    final scaleSq = s[0] * s[0] + s[1] * s[1];
    return scaleSq > 1.01 * 1.01;
  }

  void _onTransform() {
    final zoomed = _isZoomed(_transformController.value);
    if (zoomed != _panEnabled && mounted) {
      setState(() => _panEnabled = zoomed);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget img = CachedNetworkImage(
      imageUrl: widget.url,
      fit: widget.fit,
      placeholder: (context, url) => Container(
        height: 200,
        color: widget.dark ? Colors.grey[900] : null,
        child: Center(child: CircularProgressIndicator(color: widget.dark ? null : Colors.white)),
      ),
      errorWidget: (context, url, error) =>
          Icon(Icons.broken_image, color: widget.dark ? Colors.grey : Colors.grey),
    );
    // 墨水屏优化：灰度 + 提高对比度
    if (widget.eink) {
      img = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0, 0, 0, 1, 0,
        ]),
        child: img,
      );
      img = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          1.2, 0, 0, 0, -20,
          0, 1.2, 0, 0, -20,
          0, 0, 1.2, 0, -20,
          0, 0, 0, 1, 0,
        ]),
        child: img,
      );
    } else if (widget.gray) {
      img = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0, 0, 0, 1, 0,
        ]),
        child: img,
      );
    }
    // manga_threshold：二值化阈值（灰度/墨水屏之后按阈值拉开黑白对比）
    if (widget.eink || widget.gray) {
      final bias = -((widget.threshold.clamp(0, 255) - 128) * 1.8).toDouble();
      img = ColorFiltered(
        colorFilter: ColorFilter.matrix(<double>[
          3, 0, 0, 0, bias,
          0, 3, 0, 0, bias,
          0, 0, 3, 0, bias,
          0, 0, 0, 1, 0,
        ]),
        child: img,
      );
    }
    // manga_colorFilter：0 无 / 1 护眼 / 2 复古 / 3 冷色
    if (widget.colorFilter == 1) {
      img = ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          0.95, 0, 0, 0, 10,
          0, 0.95, 0, 0, 8,
          0, 0, 0.85, 0, 0,
          0, 0, 0, 1, 0,
        ]),
        child: img,
      );
    } else if (widget.colorFilter == 2) {
      img = ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          0.393, 0.769, 0.189, 0, 0,
          0.349, 0.686, 0.168, 0, 0,
          0.272, 0.534, 0.131, 0, 0,
          0, 0, 0, 1, 0,
        ]),
        child: img,
      );
    } else if (widget.colorFilter == 3) {
      img = ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          0.9, 0, 0, 0, 0,
          0, 0.95, 0, 0, 0,
          0, 0, 1.1, 0, 10,
          0, 0, 0, 1, 0,
        ]),
        child: img,
      );
    }
    // manga_noCrossFade / manga_pageAnim：图片淡入
    if (widget.fadeIn) {
      img = TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 260),
        builder: (context, v, child) => Opacity(opacity: v, child: child),
        child: img,
      );
    }
    // manga_noScale：禁用双指缩放时直接返回图片
    if (widget.noScale) return img;
    return InteractiveViewer(
      transformationController: _transformController,
      minScale: 1.0,
      maxScale: widget.scaleMax.clamp(2.0, 8.0).toDouble(),
      panEnabled: _panEnabled,
      // 结束交互时若缩放已回到 1 倍以内则复位，并恢复「禁用平移」
      onInteractionEnd: (_) {
        if (!_isZoomed(_transformController.value)) {
          _transformController.value = Matrix4.identity();
          if (_panEnabled && mounted) setState(() => _panEnabled = false);
        }
      },
      child: img,
    );
  }
}
