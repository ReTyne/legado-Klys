// 对齐 legado-E 发现/登录控件的「规则化」布局与样式。
//
// 原版依据：
//  * app/.../ui/main/explore/ExploreAdapter.kt —— 所有控件放进同一个
//    com.google.android.flexbox.FlexboxLayout（flexWrap=wrap，
//    flexDirection=row），子项宽度由 style.layout_flexBasisPercent 决定，
//    layout_flexGrow=1 让同一行的剩余空间被均分填满。
//  * app/.../res/layout/item_fillet_text.xml —— 统一的圆角文字块：
//    wrap_content / 单一 selector_fillet_btn_bg 背景 / primaryText 文字色 /
//    gravity=center / maxLines=1 / ellipsize=end。原版并不按按钮名分三种颜色。
//
// 本文件把这两条规则做成可复用组件，供「书源登录页」与「发现页控件区」
// 共用，避免两处各写一套导致「顺序对、观感却像随便排」。

import 'package:flutter/material.dart';
import 'package:legado_md3/ui/theme/app_design.dart';

/// 解析 legado `style.layout_flexBasisPercent`（对齐 FlexboxLayoutManager）。
/// -1 / 0 / 非法 / 缺省 → 0.4（约一行 2 个）；>0 且 <0.95 → 原值；>=0.95 → 1（整行）。
double flexBasisPercentOf(dynamic style) {
  if (style is Map) {
    final v = style['layout_flexBasisPercent'];
    if (v is num) {
      final d = v.toDouble();
      if (d == -1 || d <= 0) return 0.4;
      if (d >= 0.95) return 1;
      return d;
    }
  }
  return 0.4;
}

/// 对齐 E 版 FlexboxLayout 的规则化布局：
/// 按 [percents] 累加分行（累计 > 1 换行；单项 >= 0.95 独占整行），
/// 每行用 Row + Expanded 让子项按 flex 权重**铺满整行**（等价于原版
/// flexWrap=wrap + layout_flexGrow=1 的均分效果）。
///
/// 相比 Wrap 的「内容宽度 + 右侧留白」，这里每一行都严格对齐、两侧齐平，
/// 按钮宽度也更大，中文标签不再被大量截断成「打赏享…」。
class FlexPercentLayout extends StatelessWidget {
  const FlexPercentLayout({
    super.key,
    required this.children,
    required this.percents,
    this.spacing = AppSpacing.s,
    this.runSpacing = AppSpacing.s,
  });

  final List<Widget> children;
  final List<double> percents;
  final double spacing;
  final double runSpacing;

  @override
  Widget build(BuildContext context) {
    assert(children.length == percents.length,
        'percents 必须与 children 一一对应');
    if (children.isEmpty) return const SizedBox.shrink();

    // 依累加 basisPercent 分组为「行」，返回每行在 children 中的下标。
    final rows = <List<int>>[];
    var cur = <int>[];
    var sum = 0.0;
    for (var i = 0; i < children.length; i++) {
      var p = i < percents.length ? percents[i] : 0.4;
      if (p <= 0 || p > 1) p = 0.4;
      if (p >= 0.95) {
        // 整行项：先把已累积的半行收尾，再自己独占一行
        if (cur.isNotEmpty) {
          rows.add(cur);
          cur = <int>[];
          sum = 0;
        }
        rows.add([i]);
        continue;
      }
      if (sum + p > 1.0001 && cur.isNotEmpty) {
        rows.add(cur);
        cur = <int>[];
        sum = 0;
      }
      cur.add(i);
      sum += p;
    }
    if (cur.isNotEmpty) rows.add(cur);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var r = 0; r < rows.length; r++) ...[
          if (r > 0) SizedBox(height: runSpacing),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var k = 0; k < rows[r].length; k++) ...[
                if (k > 0) SizedBox(width: spacing),
                Expanded(
                  flex: (percents[rows[r][k]] * 100).round().clamp(1, 100),
                  child: children[rows[r][k]],
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

/// 对齐 legado-E `item_fillet_text.xml` 的统一圆角文字按钮。
/// 单一浅色容器背景 + 居中文字 + 最多两行，不按按钮名做三色分级：
/// 书源自带 emoji 已足够区分语义，多套配色反而让列表显得杂乱。
class FilletButton extends StatelessWidget {
  const FilletButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: AppRadius.mAll,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        child: Container(
          constraints: const BoxConstraints(minHeight: 46),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s, vertical: AppSpacing.s),
          child: Text(
            label.trim().isEmpty ? '按钮' : label.trim(),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              height: 1.25,
              color: enabled ? cs.onSurface : cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
