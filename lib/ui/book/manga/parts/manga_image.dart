/// 由 manga_reader_screen.dart 按「一类一文件」拆出的 _MangaImage。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../manga_reader_screen.dart';


/// 单张漫画图片：灰度/墨水屏滤镜 + InteractiveViewer 双指缩放。
///
/// 缩放采用「放大后才允许平移」策略（TransformationController 监听缩放倍数），
/// 避免在条漫纵向滚动 / 翻页手势上产生冲突；`noScale` 为 true 时不包缩放层。
class _MangaImage extends StatefulWidget {
  final String url;
  final BoxFit fit;
  final bool dark;
  final bool gray;
  final bool eink;
  final bool noScale;
  final int threshold;
  final int colorFilter;
  final double scaleMax;
  final bool fadeIn;

  const _MangaImage({
    required this.url,
    required this.fit,
    required this.dark,
    required this.gray,
    required this.eink,
    required this.noScale,
    this.threshold = 128,
    this.colorFilter = 0,
    this.scaleMax = 4,
    this.fadeIn = true,
  });

  @override
  State<_MangaImage> createState() => _MangaImageState();
}
