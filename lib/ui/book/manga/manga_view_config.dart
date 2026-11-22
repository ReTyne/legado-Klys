import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:legado_md3/ui/theme/app_design.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 漫画色彩滤镜配置：R/G/B/A 四通道独立调节 + 屏幕亮度 L。
///
/// 四通道取值 0~255，语义为「削减量」：0 表示该通道不削减，255 表示该通道
/// 完全关闭，换算到颜色矩阵对角线为 (255 - value) / 255，与图片渲染链路一致。
/// L 取值 0~255；0 表示不接管系统窗口亮度（跟随系统），大于 0 时按 L/255
/// 设置窗口亮度，使暗色场景下的漫画更柔和。配置以 JSON 持久化，并通过
/// [notifier] 让正在阅读的页面实时预览调节结果。
class MangaColorFilterConfig {
  final int r;
  final int g;
  final int b;
  final int a;
  final int l;

  const MangaColorFilterConfig({
    this.r = 0,
    this.g = 0,
    this.b = 0,
    this.a = 0,
    this.l = 0,
  });

  static const String prefKey = 'manga_color_filter_config';

  /// 当前活跃配置；由阅读页 / 设置页初始化并监听，调节时整体替换以触发通知。
  static final ValueNotifier<MangaColorFilterConfig> notifier =
      ValueNotifier<MangaColorFilterConfig>(const MangaColorFilterConfig());

  static int _clamp(int v) => v.clamp(0, 255);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'r': r,
        'g': g,
        'b': b,
        'a': a,
        'l': l,
      };

  factory MangaColorFilterConfig.fromJson(Map<String, dynamic> m) {
    int read(String k) => _clamp((m[k] is num ? (m[k] as num).round() : 0));
    return MangaColorFilterConfig(
      r: read('r'),
      g: read('g'),
      b: read('b'),
      a: read('a'),
      l: read('l'),
    );
  }

  static Future<MangaColorFilterConfig> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(prefKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return MangaColorFilterConfig.fromJson(
              decoded.map((k, v) => MapEntry(k.toString(), v)));
        }
      }
    } catch (_) {}
    return const MangaColorFilterConfig();
  }

  Future<void> save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(prefKey, jsonEncode(toJson()));
    } catch (_) {}
  }

  /// 是否有色彩通道需要削减（决定实际追加 ColorFiltered 层）。
  bool get hasColorAdjust => r > 0 || g > 0 || b > 0 || a > 0;

  /// 需要接管窗口亮度时的 0~1 值；L=0 表示不接管，返回 null。
  double? get windowBrightness => l > 0 ? _clamp(l) / 255.0 : null;

  /// 颜色矩阵（4x5），对角线用 (255 - 通道)/255 表示削减量。
  List<double> get matrix => <double>[
        (255 - _clamp(r)) / 255.0, 0, 0, 0, 0,
        0, (255 - _clamp(g)) / 255.0, 0, 0, 0,
        0, 0, (255 - _clamp(b)) / 255.0, 0, 0,
        0, 0, 0, (255 - _clamp(a)) / 255.0, 0,
      ];

  MangaColorFilterConfig copyWith({int? r, int? g, int? b, int? a, int? l}) =>
      MangaColorFilterConfig(
        r: r ?? this.r,
        g: g ?? this.g,
        b: b ?? this.b,
        a: a ?? this.a,
        l: l ?? this.l,
      );

  /// 从偏好重新载入并广播给监听者（阅读页进入时调用）。
  static Future<void> refresh() async {
    notifier.value = await load();
  }

  static Future<void> update(MangaColorFilterConfig next) async {
    notifier.value = next;
    await next.save();
  }
}

/// 漫画页脚信息栏配置：控制章节名 / 页码 / 章节号 / 阅读进度四段信息的
/// 显示与标签文字、整体对齐与显隐，以 JSON 持久化。
class MangaFooterConfig {
  final bool hideChapterName;
  final bool hidePageNumber;
  final bool hidePageNumberLabel;
  final bool hideChapter;
  final bool hideChapterLabel;
  final bool hideProgressRatio;
  final bool hideProgressRatioLabel;
  final bool hideFooter;
  /// 0 靠左，1 居中。
  final int footerOrientation;

  const MangaFooterConfig({
    this.hideChapterName = false,
    this.hidePageNumber = false,
    this.hidePageNumberLabel = false,
    this.hideChapter = false,
    this.hideChapterLabel = false,
    this.hideProgressRatio = false,
    this.hideProgressRatioLabel = false,
    this.hideFooter = false,
    this.footerOrientation = 0,
  });

  static const String prefKey = 'manga_footer_config';

  static final ValueNotifier<MangaFooterConfig> notifier =
      ValueNotifier<MangaFooterConfig>(const MangaFooterConfig());

  Map<String, dynamic> toJson() => <String, dynamic>{
        'hideChapterName': hideChapterName,
        'hidePageNumber': hidePageNumber,
        'hidePageNumberLabel': hidePageNumberLabel,
        'hideChapter': hideChapter,
        'hideChapterLabel': hideChapterLabel,
        'hideProgressRatio': hideProgressRatio,
        'hideProgressRatioLabel': hideProgressRatioLabel,
        'hideFooter': hideFooter,
        'footerOrientation': footerOrientation,
      };

  factory MangaFooterConfig.fromJson(Map<String, dynamic> m) {
    bool b(String k, bool fallback) => m[k] is bool ? m[k] as bool : fallback;
    final rawOrientation = m['footerOrientation'];
    return MangaFooterConfig(
      hideChapterName: b('hideChapterName', false),
      hidePageNumber: b('hidePageNumber', false),
      hidePageNumberLabel: b('hidePageNumberLabel', false),
      hideChapter: b('hideChapter', false),
      hideChapterLabel: b('hideChapterLabel', false),
      hideProgressRatio: b('hideProgressRatio', false),
      hideProgressRatioLabel: b('hideProgressRatioLabel', false),
      hideFooter: b('hideFooter', false),
      footerOrientation:
          rawOrientation is num ? (rawOrientation.round() == 1 ? 1 : 0) : 0,
    );
  }

  static Future<MangaFooterConfig> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(prefKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return MangaFooterConfig.fromJson(
              decoded.map((k, v) => MapEntry(k.toString(), v)));
        }
      }
    } catch (_) {}
    return const MangaFooterConfig();
  }

  Future<void> save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(prefKey, jsonEncode(toJson()));
    } catch (_) {}
  }

  MangaFooterConfig copyWith({
    bool? hideChapterName,
    bool? hidePageNumber,
    bool? hidePageNumberLabel,
    bool? hideChapter,
    bool? hideChapterLabel,
    bool? hideProgressRatio,
    bool? hideProgressRatioLabel,
    bool? hideFooter,
    int? footerOrientation,
  }) =>
      MangaFooterConfig(
        hideChapterName: hideChapterName ?? this.hideChapterName,
        hidePageNumber: hidePageNumber ?? this.hidePageNumber,
        hidePageNumberLabel: hidePageNumberLabel ?? this.hidePageNumberLabel,
        hideChapter: hideChapter ?? this.hideChapter,
        hideChapterLabel: hideChapterLabel ?? this.hideChapterLabel,
        hideProgressRatio: hideProgressRatio ?? this.hideProgressRatio,
        hideProgressRatioLabel:
            hideProgressRatioLabel ?? this.hideProgressRatioLabel,
        hideFooter: hideFooter ?? this.hideFooter,
        footerOrientation: footerOrientation ?? this.footerOrientation,
      );

  /// 生成页脚文字。章节位置 pageIndex 与 chapterIndex 均为 0 起始；
  /// 书籍总进度按「已完成章节 + 当前章内图片占比」计算，最后一页封顶 100%，
  /// 非最后一页则封顶 99.9%，避免出现提前满 100% 的误解。
  String buildInfo({
    required String chapterName,
    required int chapterPos,
    required int imageCount,
    required int chapterIndex,
    required int chapterSize,
  }) {
    if (hideFooter) return '';
    final sb = StringBuffer();
    if (!hideChapterName && chapterName.isNotEmpty) {
      sb.write('$chapterName ');
    }
    if (!hidePageNumber) {
      if (!hidePageNumberLabel) sb.write('页码 ');
      sb.write('${chapterPos + 1}/$imageCount ');
    }
    if (!hideChapter) {
      if (!hideChapterLabel) sb.write('章节 ');
      sb.write('${chapterIndex + 1}/$chapterSize ');
    }
    if (!hideProgressRatio) {
      if (!hideProgressRatioLabel) sb.write('进度 ');
      sb.write(_percent(
        chapterIndex: chapterIndex,
        chapterSize: chapterSize,
        chapterPos: chapterPos,
        imageCount: imageCount,
      ));
    }
    return sb.toString().trim();
  }

  static String _percent({
    required int chapterIndex,
    required int chapterSize,
    required int chapterPos,
    required int imageCount,
  }) {
    if (chapterSize == 0 || (imageCount == 0 && chapterIndex == 0)) {
      return '0.0%';
    }
    late final double ratio;
    late final bool isLast;
    if (imageCount == 0) {
      ratio = (chapterIndex + 1) / chapterSize;
      isLast = true;
    } else {
      ratio = chapterIndex / chapterSize +
          (1 / chapterSize) * ((chapterPos + 1) / imageCount);
      isLast =
          chapterIndex + 1 == chapterSize && chapterPos + 1 == imageCount;
    }
    final formatted = '${(ratio * 100).toStringAsFixed(1)}%';
    // 浮点舍入提前显示 100% 但尚未读到最后一页时封顶 99.9%
    if (!isLast && formatted == '100.0%') return '99.9%';
    return formatted;
  }

  static Future<void> refresh() async {
    notifier.value = await load();
  }

  static Future<void> update(MangaFooterConfig next) async {
    notifier.value = next;
    await next.save();
  }
}

/// 色彩滤镜调节面板：5 条滑杆实时改动 [MangaColorFilterConfig.notifier]。
Future<void> showMangaColorFilterSheet(BuildContext context) async {
  final current = MangaColorFilterConfig.notifier.value;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: StatefulBuilder(
          builder: (ctx, setLocal) {
            Widget slider(String label, int value, ValueChanged<int> onChanged) {
              return Row(
                children: [
                  SizedBox(width: 24, child: Text(label)),
                  Expanded(
                    child: Slider(
                      value: value.toDouble(),
                      min: 0,
                      max: 255,
                      divisions: 255,
                      label: '$value',
                      onChanged: (v) => onChanged(v.round()),
                    ),
                  ),
                  SizedBox(width: 36, child: Text('$value', textAlign: TextAlign.end)),
                ],
              );
            }

            void apply(MangaColorFilterConfig next) {
              setLocal(() {});
              MangaColorFilterConfig.notifier.value = next;
              unawaited(next.save());
            }

            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('色彩滤镜', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  const Text('R/G/B/A 表示对应通道削减量，0 为原色；亮度 0 表示跟随系统。',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: AppSpacing.m),
                  slider('亮度', current.l, (v) => apply(current.copyWith(l: v))),
                  slider('R', current.r, (v) => apply(current.copyWith(r: v))),
                  slider('G', current.g, (v) => apply(current.copyWith(g: v))),
                  slider('B', current.b, (v) => apply(current.copyWith(b: v))),
                  slider('A', current.a, (v) => apply(current.copyWith(a: v))),
                  const SizedBox(height: AppSpacing.s),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => apply(const MangaColorFilterConfig()),
                        child: const Text('重置'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('完成'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
}

/// 页脚信息栏设置面板：各段信息显隐 / 标签 / 对齐 / 整体显隐实时改动
/// [MangaFooterConfig.notifier]。
Future<void> showMangaFooterSheet(BuildContext context) async {
  final current = MangaFooterConfig.notifier.value;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: StatefulBuilder(
          builder: (ctx, setLocal) {
            void apply(MangaFooterConfig next) {
              setLocal(() {});
              MangaFooterConfig.notifier.value = next;
              unawaited(next.save());
            }

            Widget toggle(String title, bool value, ValueChanged<bool> onChanged) =>
                SwitchListTile(
              dense: true,
              title: Text(title, style: const TextStyle(fontSize: 14)),
              value: value,
              onChanged: (v) => onChanged(v),
            );

            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('页脚信息栏', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  toggle('隐藏整个页脚', current.hideFooter,
                      (v) => apply(current.copyWith(hideFooter: v))),
                  toggle('隐藏章节名', current.hideChapterName,
                      (v) => apply(current.copyWith(hideChapterName: v))),
                  toggle('隐藏页码', current.hidePageNumber,
                      (v) => apply(current.copyWith(hidePageNumber: v))),
                  toggle('隐藏「页码」标签', current.hidePageNumberLabel,
                      (v) => apply(current.copyWith(hidePageNumberLabel: v))),
                  toggle('隐藏章节号', current.hideChapter,
                      (v) => apply(current.copyWith(hideChapter: v))),
                  toggle('隐藏「章节」标签', current.hideChapterLabel,
                      (v) => apply(current.copyWith(hideChapterLabel: v))),
                  toggle('隐藏阅读进度', current.hideProgressRatio,
                      (v) => apply(current.copyWith(hideProgressRatio: v))),
                  toggle('隐藏「进度」标签', current.hideProgressRatioLabel,
                      (v) => apply(current.copyWith(hideProgressRatioLabel: v))),
                  const SizedBox(height: AppSpacing.s),
                  Text('对齐方式', style: Theme.of(ctx).textTheme.bodySmall),
                  const SizedBox(height: AppSpacing.xs),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('靠左')),
                      ButtonSegment(value: 1, label: Text('居中')),
                    ],
                    selected: {current.footerOrientation},
                    onSelectionChanged: (s) =>
                        apply(current.copyWith(footerOrientation: s.first)),
                  ),
                  const SizedBox(height: AppSpacing.m),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('完成'),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
}
