import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:legado_md3/help/translate/translation_service.dart';

/// 一条漫画图内文字区域（OCR 结果框 / 书源翻译规则框）。
///
/// 坐标为图片内的归一化值（0~1），`sourceText` 为框内原文，
/// `translated` 为经 [TranslationService] 翻译后的译文。
class MangaTextRegion {
  final double x;
  final double y;
  final double w;
  final double h;
  final String sourceText;
  String? translated;

  MangaTextRegion({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.sourceText,
    this.translated,
  });

  factory MangaTextRegion.fromJson(Map<String, dynamic> j) => MangaTextRegion(
        x: (j['x'] as num?)?.toDouble() ?? 0,
        y: (j['y'] as num?)?.toDouble() ?? 0,
        w: (j['w'] as num?)?.toDouble() ?? 0.2,
        h: (j['h'] as num?)?.toDouble() ?? 0.08,
        sourceText: (j['text'] ?? j['source'] ?? '').toString(),
        translated: j['translated']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'w': w,
        'h': h,
        'text': sourceText,
        if (translated != null) 'translated': translated,
      };

  MangaTextRegion copy() => MangaTextRegion(
        x: x,
        y: y,
        w: w,
        h: h,
        sourceText: sourceText,
        translated: translated,
      );
}

/// 漫画 AI 翻译配置与译文缓存。
///
/// 无 OCR SDK 时走「按书源翻译规则替换图内文字配置」的可兑现版本：
/// 规则（JSON 数组）直接给出图内文字框与框内原文，本类调用现有
/// [TranslationService] 把原文翻成译文，[MangaTranslationOverlay] 把译文
/// 以覆盖层盖回原图对应位置，实现「替换图内文字」。
/// 若后续接入 OCR，只需把 OCR 结果填入同一 [MangaTextRegion] 结构即可复用。
class MangaTranslateStore {
  MangaTranslateStore._();
  static final MangaTranslateStore instance = MangaTranslateStore._();

  static const String kEnabled = 'manga_translate_enabled';
  static String rulesKey(String origin) =>
      'manga_translate_regions_${origin.isEmpty ? 'default' : origin}';

  bool _enabled = false;
  String _origin = '';
  List<MangaTextRegion>? _cache;

  bool get enabled => _enabled;

  static const String sampleRules = '''[
  {"x":0.04,"y":0.05,"w":0.42,"h":0.10,"text":"What are you doing here?"},
  {"x":0.55,"y":0.78,"w":0.40,"h":0.09,"text":"I have been waiting for you."}
]''';

  Future<void> load(String origin) async {
    final p = await SharedPreferences.getInstance();
    _enabled = p.getBool(kEnabled) ?? false;
    _origin = origin;
    _cache = null;
  }

  Future<void> setEnabled(bool v) async {
    _enabled = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(kEnabled, v);
  }

  /// 读取规则：优先书源专属配置，回退到全局 default 配置；
  /// 从未配置过时写入一份可直接兑现的示例规则。
  Future<List<MangaTextRegion>> loadRules(String origin) async {
    final p = await SharedPreferences.getInstance();
    var raw = origin.isNotEmpty ? p.getString(rulesKey(origin)) : null;
    raw ??= p.getString(rulesKey(''));
    if (raw == null || raw.trim().isEmpty) {
      await p.setString(rulesKey(''), sampleRules);
      return _decode(sampleRules);
    }
    return _decode(raw);
  }

  Future<void> saveRules(String origin, String json) async {
    // 校验 JSON 合法且为数组，避免写入坏配置导致阅读页崩溃
    final decoded = jsonDecode(json);
    if (decoded is! List) {
      throw const FormatException('规则必须是 JSON 数组');
    }
    final p = await SharedPreferences.getInstance();
    await p.setString(rulesKey(origin), json);
    _cache = null;
  }

  static List<MangaTextRegion> _decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((m) => MangaTextRegion.fromJson(Map<String, dynamic>.from(m)))
            .where((r) => r.sourceText.trim().isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return <MangaTextRegion>[];
  }

  /// 返回已翻译的覆盖层框（带内存缓存，翻页不重复请求翻译）。
  Future<List<MangaTextRegion>> translatedRegions(String origin) async {
    final cached = _cache;
    if (cached != null && _origin == origin) return cached;
    final regions = await loadRules(origin);
    await TranslationService.instance.loadPrefs();
    for (final r in regions) {
      r.translated = await TranslationService.instance.translate(r.sourceText);
    }
    _origin = origin;
    _cache = regions;
    return regions;
  }

  void clearCache() => _cache = null;
}

/// 译文覆盖层：在每个文字框位置铺一层底色并绘制译文，遮住图内原文。
class MangaTranslationOverlay extends StatelessWidget {
  final List<MangaTextRegion> regions;

  const MangaTranslationOverlay({super.key, required this.regions});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (regions.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, cons) {
      final w = cons.maxWidth;
      final h = cons.maxHeight;
      return IgnorePointer(
        child: Stack(
          children: [
            for (final r in regions)
              Positioned(
                left: (r.x * w).clamp(0.0, w),
                top: (r.y * h).clamp(0.0, h),
                width: (r.w * w).clamp(24.0, w),
                height: (r.h * h).clamp(18.0, h),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withOpacity(0.92),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: cs.outlineVariant, width: 0.5),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      (r.translated ?? r.sourceText).trim(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.15,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }
}
