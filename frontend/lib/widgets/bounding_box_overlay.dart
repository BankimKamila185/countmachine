import 'package:flutter/material.dart';
import '../models/detected_item.dart';

class BoundingBoxOverlay extends StatelessWidget {
  final CountResult result;
  final Size previewSize;

  const BoundingBoxOverlay({
    super.key,
    required this.result,
    required this.previewSize,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _DetectionPainter(
        items: result.items,
        sourceWidth: result.processedWidth.toDouble(),
        sourceHeight: result.processedHeight.toDouble(),
      ),
    );
  }
}

class _DetectionPainter extends CustomPainter {
  final List<DetectedItem> items;
  final double sourceWidth;
  final double sourceHeight;

  _DetectionPainter({
    required this.items,
    required this.sourceWidth,
    required this.sourceHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (items.isEmpty || sourceWidth <= 0 || sourceHeight <= 0) return;

    final scaleX = size.width / sourceWidth;
    final scaleY = size.height / sourceHeight;

    final boxPaint = Paint()
      ..color = const Color(0xFF00FF9D)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final glowPaint = Paint()
      ..color = const Color(0x6600FF9D)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    final dotPaint = Paint()
      ..color = const Color(0xFFFF2A6D)
      ..style = PaintingStyle.fill;

    final dotBorderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    for (final item in items) {
      final rect = Rect.fromLTWH(
        item.bbox.left * scaleX,
        item.bbox.top * scaleY,
        item.bbox.width * scaleX,
        item.bbox.height * scaleY,
      );

      final center = Offset(
        item.center.dx * scaleX,
        item.center.dy * scaleY,
      );

      // Draw Glowing outline
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        glowPaint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        boxPaint,
      );

      // Draw Center Focal Dot
      canvas.drawCircle(center, 5.0, dotPaint);
      canvas.drawCircle(center, 5.0, dotBorderPaint);

      // Draw Pin Badge Chip (#1, #2)
      final badgeText = '#${item.id}';
      final textSpan = TextSpan(
        text: badgeText,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      final badgeRect = Rect.fromLTWH(
        rect.left,
        rect.top - 20 < 0 ? rect.top : rect.top - 20,
        textPainter.width + 12,
        18,
      );

      final badgeBgPaint = Paint()..color = const Color(0xFF00FF9D);
      canvas.drawRRect(
        RRect.fromRectAndRadius(badgeRect, const Radius.circular(4)),
        badgeBgPaint,
      );

      textPainter.paint(
        canvas,
        Offset(badgeRect.left + 6, badgeRect.top + 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DetectionPainter oldDelegate) {
    return oldDelegate.items != items ||
        oldDelegate.sourceWidth != sourceWidth ||
        oldDelegate.sourceHeight != sourceHeight;
  }
}
