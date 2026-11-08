import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 关系网节点：位置为归一化坐标（0~1），便于保存与不同屏幕尺寸复用。
class GraphNode {
  final String id;
  final String label;
  final String? avatar;
  final int? color;
  Offset position;

  GraphNode({
    required this.id,
    required this.label,
    this.avatar,
    this.color,
    Offset? position,
  }) : position = position ?? Offset.zero;
}

/// 关系网边：从 [from] 指向 [to]，[label] 为关系类型（盟友/亲属/对立…）。
class GraphEdge {
  final String from;
  final String to;
  final String label;

  const GraphEdge({required this.from, required this.to, this.label = '关联'});
}

/// 人物关系网绘制器：画关系边（含箭头与关系标签）与节点光环。
/// 节点头像用上层 `Positioned` 的 `CircleAvatar` 渲染，本 painter 只负责连线，
/// 这样既支持网络头像又保持拖拽时重绘开销最小。
class RelationGraphPainter extends CustomPainter {
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
  final ColorScheme colorScheme;
  final String? selectedId;
  final int version;

  RelationGraphPainter({
    required this.nodes,
    required this.edges,
    required this.colorScheme,
    this.selectedId,
    this.version = 0,
  });

  static const double nodeRadius = 30.0;

  @override
  void paint(Canvas canvas, Size size) {
    final byId = <String, GraphNode>{for (final n in nodes) n.id: n};
    final linePaint = Paint()
      ..color = colorScheme.outlineVariant
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    final activePaint = Paint()
      ..color = colorScheme.primary
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke;

    for (final e in edges) {
      final a = byId[e.from];
      final b = byId[e.to];
      if (a == null || b == null) continue;
      final pa = Offset(a.position.dx * size.width, a.position.dy * size.height);
      final pb = Offset(b.position.dx * size.width, b.position.dy * size.height);
      final active = selectedId == e.from || selectedId == e.to;
      final paint = active ? activePaint : linePaint;

      // 从节点边缘起止，箭头落在目标节点外沿
      final dir = pb - pa;
      final len = dir.distance;
      if (len < 1) continue;
      final unit = dir / len;
      final start = pa + unit * nodeRadius;
      final end = pb - unit * (nodeRadius + 6);
      canvas.drawLine(start, end, paint);
      _drawArrowHead(canvas, end, unit, paint);

      if (e.label.isNotEmpty) {
        final mid = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
        _drawLabel(canvas, size, mid, e.label, active);
      }
    }

    // 节点外环：选中态用主色加粗
    for (final n in nodes) {
      final c = Offset(n.position.dx * size.width, n.position.dy * size.height);
      final ring = Paint()
        ..color = n.id == selectedId
            ? colorScheme.primary
            : colorScheme.outlineVariant
        ..strokeWidth = n.id == selectedId ? 3 : 1.5
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(c, nodeRadius + 3, ring);
    }
  }

  void _drawArrowHead(Canvas canvas, Offset tip, Offset unit, Paint paint) {
    const arrowLen = 9.0;
    const wing = 0.5;
    final angle = math.atan2(unit.dy, unit.dx);
    final p1 = tip -
        Offset(math.cos(angle - wing), math.sin(angle - wing)) * arrowLen;
    final p2 = tip -
        Offset(math.cos(angle + wing), math.sin(angle + wing)) * arrowLen;
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..close();
    canvas.drawPath(path, paint..style = PaintingStyle.fill);
    paint.style = PaintingStyle.stroke;
  }

  void _drawLabel(Canvas canvas, Size size, Offset at, String label, bool active) {
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: active ? colorScheme.primary : colorScheme.onSurfaceVariant,
          fontSize: 10,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 80);
    final bg = Paint()
      ..color = colorScheme.surfaceContainerHighest.withOpacity(0.9);
    final rect = Rect.fromLTWH(
      (at.dx - tp.width / 2 - 3).clamp(0.0, size.width - tp.width - 6),
      (at.dy - tp.height / 2 - 2).clamp(0.0, size.height - tp.height - 4),
      tp.width + 6,
      tp.height + 4,
    );
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)), bg);
    tp.paint(canvas, Offset(rect.left + 3, rect.top + 2));
  }

  @override
  bool shouldRepaint(covariant RelationGraphPainter oldDelegate) =>
      oldDelegate.version != version ||
      oldDelegate.selectedId != selectedId ||
      oldDelegate.colorScheme != colorScheme ||
      oldDelegate.nodes.length != nodes.length ||
      oldDelegate.edges.length != edges.length;
}
