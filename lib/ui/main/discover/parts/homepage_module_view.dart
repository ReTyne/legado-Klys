/// 由 homepage_module_widgets.dart 按「一类一文件」拆出的 HomepageModuleView。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../homepage_module_widgets.dart';


/// 单个模块的视图：按 [HomepageModule.type] 分派到 8 种布局中的某一种。
/// banner / card / grid / waterfall / ranking 为精细布局；
/// buttonGroup / gridRanking / custom 为通用渲染（按钮组 / 带序号网格 / 卡片列表）。
class HomepageModuleView extends StatelessWidget {
  const HomepageModuleView({
    super.key,
    required this.module,
    required this.data,
    required this.items,
    required this.onTap,
    this.loading = false,
    this.error,
    this.onRetry,
  });

  final HomepageModule module;
  final HomepageModuleData data;
  final List<HomepageItem> items;
  final HomepageItemTap onTap;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    data.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                AppTag(homepageModuleTypeLabel(module.type)),
              ],
            ),
          ),
          _buildBody(context),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (error != null) {
      final cs = Theme.of(context).colorScheme;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 18, color: cs.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text('加载失败：$error',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ),
            if (onRetry != null)
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('重试'),
              ),
          ],
        ),
      );
    }
    if (items.isEmpty) {
      final cs = Theme.of(context).colorScheme;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.widgets_outlined, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '该模块暂无内容，可在「首页模块」中配置卡片或发现地址',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
    }
    switch (module.type) {
      case HomepageModuleType.banner:
        return _BannerSection(items: items, onTap: onTap);
      case HomepageModuleType.buttonGroup:
        return _ButtonGroupSection(items: items, onTap: onTap);
      case HomepageModuleType.card:
        return _CardSection(items: items, onTap: onTap);
      case HomepageModuleType.grid:
        return _GridSection(items: items, onTap: onTap, ranked: false);
      case HomepageModuleType.gridRanking:
        return _GridSection(items: items, onTap: onTap, ranked: true);
      case HomepageModuleType.ranking:
        return _RankingSection(items: items, onTap: onTap);
      case HomepageModuleType.waterfall:
        return _WaterfallSection(items: items, onTap: onTap);
      case HomepageModuleType.custom:
        return _CardSection(items: items, onTap: onTap);
    }
  }
}

/// 通用封面：优先网络图，失败/为空回退公共组件 DefaultCover。
/// width/height 传 double.infinity 时由 LayoutBuilder 取得父容器有限尺寸，
/// 避免把无限约束直接交给 DefaultCover / Container。
Widget _itemCover(
  BuildContext context,
  HomepageItem item, {
  double width = 48,
  double height = 66,
  double radius = 12,
}) {
  if (width.isInfinite || height.isInfinite) {
    return LayoutBuilder(
      builder: (context, cons) => _buildCover(
        item,
        width.isFinite ? width : cons.maxWidth,
        height.isFinite ? height : cons.maxHeight,
        radius,
      ),
    );
  }
  return _buildCover(item, width, height, radius);
}

Widget _buildCover(
  HomepageItem item,
  double width,
  double height,
  double radius,
) {
  final placeholder = DefaultCover(
    name: item.title,
    width: width,
    height: height,
    radius: radius,
    fontSize: width >= 90 ? 13 : 10,
  );
  final url = item.cover;
  if (url == null || url.isEmpty) return placeholder;
  return ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: Image.network(
      url,
      width: width,
      height: height,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => placeholder,
    ),
  );
}
