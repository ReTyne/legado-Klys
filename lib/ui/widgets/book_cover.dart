import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:legado_md3/constant/app_theme.dart';

/// 统一的默认封面占位：低饱和深底 + 白字书名。
///
/// 全项目唯一实现，替换 bookshelf / discover / detail / search 各处复制的
/// `defaultCoverPalette` 色表字面量。色值来自 [defaultCoverPalette]，
/// 与 AppTheme 的 MD3 主题同属一套视觉底座。
class DefaultCover extends StatelessWidget {
  const DefaultCover({
    super.key,
    required this.name,
    required this.width,
    required this.height,
    this.radius = 4,
    this.fontSize = 10,
  });

  final String name;
  final double width;
  final double height;
  final double radius;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final color =
        defaultCoverPalette[name.hashCode.abs() % defaultCoverPalette.length];
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Text(
            name,
            maxLines: 3,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

/// 统一书籍封面：本地文件 > 网络 URL > 默认占位，支持角标与底部文字叠加。
///
/// - [coverUrl] / [localPath] 均无或加载失败时回退 [DefaultCover]。
/// - [badge] 未读数角标使用 `colorScheme.error`，不再硬编码 `Color(0xFFB3261E)`。
/// - 所有语义色取 `Theme.of(context).colorScheme`，跟随主题/AMOLED/E-ink。
class BookCover extends StatelessWidget {
  const BookCover({
    super.key,
    required this.name,
    this.coverUrl,
    this.localPath,
    this.width = 48,
    this.height = 66,
    this.radius = 4,
    this.badge,
    this.overlay,
    this.onTap,
  });

  final String name;
  final String? coverUrl;
  final String? localPath;
  final double width;
  final double height;
  final double radius;
  final int? badge;
  final Widget? overlay;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final placeholder = DefaultCover(
      name: name,
      width: width,
      height: height,
      radius: radius,
    );

    Widget image;
    final local = localPath;
    final url = coverUrl;
    if (local != null && local.isNotEmpty) {
      image = Image.file(
        File(local),
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
      );
    } else if (url != null && url.isNotEmpty) {
      image = CachedNetworkImage(
        imageUrl: url,
        width: width,
        height: height,
        fit: BoxFit.cover,
        placeholder: (_, __) => placeholder,
        errorWidget: (_, __, ___) => placeholder,
      );
    } else {
      image = placeholder;
    }

    Widget content = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Stack(
        children: [
          image,
          if (overlay != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0x99000000)],
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                child: overlay!,
              ),
            ),
          if (badge != null && badge! > 0)
            Positioned(
              right: 2,
              top: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: cs.error,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  badge! > 99 ? '99+' : '${badge!}',
                  style: TextStyle(
                    color: cs.onError,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    if (onTap != null) {
      content = GestureDetector(onTap: onTap, child: content);
    }
    return SizedBox(width: width, height: height, child: content);
  }
}
