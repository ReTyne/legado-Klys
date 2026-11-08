import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:legado_md3/data/model/homepage_module.dart';
import 'package:legado_md3/data/model/search_book.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';

/// 当前启用的首页模块集 id 持久化（Feed 与模块集管理页共用）。
/// - null / 0：不使用模块集，展示全部启用模块（DAO 已按 customOrder 排序）。
/// - 其它：只展示该模块集 moduleIds 内、且启用的模块，顺序按 moduleIds。
class HomepageSetStore {
  HomepageSetStore._();

  static const String activeSetIdKey = 'homepage_active_set_id';

  static Future<int?> loadActiveSetId() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getInt(activeSetIdKey);
      return (v == null || v <= 0) ? null : v;
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveActiveSetId(int? id) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (id == null || id <= 0) {
        await p.remove(activeSetIdKey);
      } else {
        await p.setInt(activeSetIdKey, id);
      }
    } catch (_) {}
  }

  /// 解析 HomepageCustomSet.moduleIds（JSON 数组）为模块 id 列表。
  static List<int> parseModuleIds(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const <int>[];
    try {
      final d = jsonDecode(raw);
      if (d is List) {
        return d
            .map<int>((e) => e is int ? e : int.tryParse('$e') ?? -1)
            .where((e) => e > 0)
            .toList();
      }
    } catch (_) {}
    return const <int>[];
  }

  static String encodeModuleIds(List<int> ids) => jsonEncode(ids);
}

/// 首页模块类型的中文标签（Feed 与管理页共用）。
String homepageModuleTypeLabel(HomepageModuleType t) => switch (t) {
      HomepageModuleType.banner => '横幅',
      HomepageModuleType.buttonGroup => '按钮组',
      HomepageModuleType.card => '卡片',
      HomepageModuleType.grid => '网格',
      HomepageModuleType.gridRanking => '网格排行',
      HomepageModuleType.ranking => '排行榜',
      HomepageModuleType.waterfall => '瀑布流',
      HomepageModuleType.custom => '自定义',
    };

/// 卡片点击动作类型。
enum HomepageAction { none, search, book, explore, url }

HomepageAction _parseAction(String? v) => switch (v) {
      'search' => HomepageAction.search,
      'book' => HomepageAction.book,
      'explore' => HomepageAction.explore,
      'url' => HomepageAction.url,
      _ => HomepageAction.none,
    };

/// 首页模块内的一张卡片数据。
///
/// config JSON 中除 title/subtitle/cover/badge/action 外的键统一收进 [params]
/// （字符串化），便于动作携带 keyword / sourceUrl / exploreUrl / bookUrl /
/// origin 等参数，点击动作由 HomepageFeed 的 onAction 回调真实分发。
class HomepageItem {
  const HomepageItem({
    required this.title,
    this.subtitle = '',
    this.cover,
    this.badge,
    this.action = HomepageAction.none,
    this.params = const <String, String>{},
  });

  final String title;
  final String subtitle;
  final String? cover;
  final String? badge;
  final HomepageAction action;
  final Map<String, String> params;

  String param(String key) => params[key] ?? '';

  factory HomepageItem.fromMap(Map<String, dynamic> map) {
    final params = <String, String>{};
    const reserved = {'title', 'subtitle', 'cover', 'badge', 'action'};
    map.forEach((k, v) {
      if (!reserved.contains(k) && v != null) {
        params[k.toString()] = v.toString();
      }
    });
    return HomepageItem(
      title: (map['title'] ?? '').toString(),
      subtitle: (map['subtitle'] ?? '').toString(),
      cover: map['cover']?.toString(),
      badge: map['badge']?.toString(),
      action: _parseAction(map['action']?.toString()),
      params: params,
    );
  }

  /// 由发现 / 搜索书籍构造：默认动作 = 打开书籍详情。
  factory HomepageItem.fromSearchBook(SearchBook b) => HomepageItem(
        title: b.name,
        subtitle: b.author,
        cover: b.coverUrl,
        badge: b.lastChapter,
        action: HomepageAction.book,
        params: <String, String>{
          'bookName': b.name,
          'bookAuthor': b.author,
          'cover': b.coverUrl ?? '',
          'intro': b.intro ?? '',
          'kind': b.kind ?? '',
          'bookUrl': b.bookUrl ?? '',
          'origin': b.origin ?? '',
          'originName': b.originName ?? '',
          'lastChapter': b.lastChapter ?? '',
        },
      );
}

/// 模块的展示数据（标题 + 卡片列表），从 HomepageModule.config(JSON) 解析。
///
/// config 支持两种写法：
/// 1. `{"title":"...", "items":[{...}, ...]}`
/// 2. 直接 `[{...}, ...]`
/// 每个 item 的字段见 [HomepageItem.fromMap]。解析失败时安全退化为空列表，
/// 由 Feed 依据 sourceUrl/exploreUrl 拉取真实发现书籍填充。
class HomepageModuleData {
  const HomepageModuleData({required this.title, required this.items});

  final String title;
  final List<HomepageItem> items;

  factory HomepageModuleData.fromModule(HomepageModule m) {
    var title = m.name;
    final items = <HomepageItem>[];
    final cfg = m.config;
    if (cfg != null && cfg.trim().isNotEmpty) {
      try {
        final d = jsonDecode(cfg);
        if (d is Map) {
          final t = d['title']?.toString().trim() ?? '';
          if (t.isNotEmpty) title = t;
          final raw = d['items'];
          if (raw is List) {
            for (final e in raw) {
              if (e is Map) {
                items.add(HomepageItem.fromMap(Map<String, dynamic>.from(e)));
              }
            }
          }
        } else if (d is List) {
          for (final e in d) {
            if (e is Map) {
              items.add(HomepageItem.fromMap(Map<String, dynamic>.from(e)));
            }
          }
        }
      } catch (_) {}
    }
    return HomepageModuleData(title: title, items: items);
  }
}

typedef HomepageItemTap = void Function(HomepageItem item);

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

/// 横幅：横向可滚动的大图卡片（封面 + 标题/副标题叠加）。
class _BannerSection extends StatelessWidget {
  const _BannerSection({required this.items, required this.onTap});
  final List<HomepageItem> items;
  final HomepageItemTap onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 152,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final item = items[i];
          return SizedBox(
            width: 260,
            child: Card(
              clipBehavior: Clip.antiAlias,
              margin: EdgeInsets.zero,
              child: InkWell(
                onTap: () => onTap(item),
                child: Row(
                  children: [
                    _itemCover(context, item, width: 100, height: 152, radius: 0),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(item.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: cs.onSurface)),
                            if (item.subtitle.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(item.subtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: cs.onSurfaceVariant)),
                            ],
                            if (item.badge != null && item.badge!.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              AppTag(item.badge!, accent: true),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 按钮组：流式排列的动作按钮。
class _ButtonGroupSection extends StatelessWidget {
  const _ButtonGroupSection({required this.items, required this.onTap});
  final List<HomepageItem> items;
  final HomepageItemTap onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: items
            .map((item) => ActionChip(
                  avatar: const Icon(Icons.apps_outlined, size: 16),
                  label: Text(item.title),
                  onPressed: () => onTap(item),
                ))
            .toList(),
      ),
    );
  }
}

/// 卡片列表：每个 item 一张横向卡片（封面 + 标题/副标题/角标）。
class _CardSection extends StatelessWidget {
  const _CardSection({required this.items, required this.onTap});
  final List<HomepageItem> items;
  final HomepageItemTap onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: items.map((item) {
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: _itemCover(context, item, width: 48, height: 66),
              title: Text(item.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (item.subtitle.isNotEmpty)
                    Text(item.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12)),
                  if (item.badge != null && item.badge!.isNotEmpty)
                    Text(item.badge!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: cs.primary)),
                ],
              ),
              trailing: Icon(Icons.chevron_right,
                  size: 18, color: cs.onSurfaceVariant),
              onTap: () => onTap(item),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// 网格 / 网格排行：自适应列数的网格，ranked 时左上角叠加序号。
class _GridSection extends StatelessWidget {
  const _GridSection({
    required this.items,
    required this.onTap,
    required this.ranked,
  });
  final List<HomepageItem> items;
  final HomepageItemTap onTap;
  final bool ranked;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 720
            ? 5
            : width >= 520
                ? 4
                : 3;
        const spacing = 10.0;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: spacing,
              mainAxisSpacing: spacing,
              childAspectRatio: 0.62,
            ),
            itemBuilder: (context, i) {
              final item = items[i];
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onTap(item),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: _itemCover(context, item,
                                width: double.infinity,
                                height: double.infinity),
                          ),
                          if (ranked)
                            Positioned(
                              left: 4,
                              top: 4,
                              child: _RankBadge(index: i, small: true),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: cs.onSurface)),
                    if (item.subtitle.isNotEmpty)
                      Text(item.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 10, color: cs.onSurfaceVariant)),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// 排行榜：带序号徽章的列表，前三名强调色。
class _RankingSection extends StatelessWidget {
  const _RankingSection({required this.items, required this.onTap});
  final List<HomepageItem> items;
  final HomepageItemTap onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: items.asMap().entries.map((e) {
          final item = e.value;
          return Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _RankBadge(index: e.key),
                  const SizedBox(width: 8),
                  _itemCover(context, item, width: 40, height: 56),
                ],
              ),
              title: Text(item.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                item.subtitle.isNotEmpty ? item.subtitle : (item.badge ?? ''),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              trailing: Icon(Icons.chevron_right,
                  size: 18, color: cs.onSurfaceVariant),
              onTap: () => onTap(item),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.index, this.small = false});
  final int index;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final top = index < 3;
    return Container(
      width: small ? 20 : 24,
      height: small ? 20 : 24,
      decoration: BoxDecoration(
        color: top ? cs.primary : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(
        '${index + 1}',
        style: TextStyle(
          fontSize: small ? 11 : 13,
          fontWeight: FontWeight.bold,
          color: top ? cs.onPrimary : cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 瀑布流：两列不等高卡片，按序号交错高度形成瀑布效果。
class _WaterfallSection extends StatelessWidget {
  const _WaterfallSection({required this.items, required this.onTap});
  final List<HomepageItem> items;
  final HomepageItemTap onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final left = <HomepageItem>[];
    final right = <HomepageItem>[];
    for (var i = 0; i < items.length; i++) {
      (i % 2 == 0 ? left : right).add(items[i]);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _waterfallColumn(context, left, 0, cs),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _waterfallColumn(context, right, 1, cs),
          ),
        ],
      ),
    );
  }

  Widget _waterfallColumn(BuildContext context, List<HomepageItem> list,
      int columnSeed, ColorScheme cs) {
    return Column(
      children: list.asMap().entries.map((e) {
        final item = e.value;
        final tall = (e.key + columnSeed) % 2 == 0;
        final h = tall ? 168.0 : 128.0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onTap(item),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: double.infinity,
                    height: h,
                    child: _itemCover(context, item,
                        width: double.infinity, height: h, radius: 0),
                  ),
                ),
                const SizedBox(height: 4),
                Text(item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: cs.onSurface)),
                if (item.subtitle.isNotEmpty)
                  Text(item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
