import 'package:flutter/material.dart';
import 'detection.dart';

/// Draws smoothed boxes (normalized coords) onto a widget covering the camera
/// preview. Assumes the preview uses a "cover"-style aspect fill (the iOS
/// AVCaptureVideoPreviewLayer with `videoGravity = resizeAspectFill` does).
class BBoxPainter extends CustomPainter {
  final List<SmoothedDetection> detections;
  final Size frameSize; // model-space frame size used to produce boxes

  BBoxPainter({required this.detections, required this.frameSize});

  @override
  void paint(Canvas canvas, Size size) {
    if (detections.isEmpty) return;

    // Cover-fit mapping: scale = max(viewW/frameW, viewH/frameH).
    final scale = (size.width / frameSize.width)
        .clamp(0.0, double.infinity);
    final scaleY = size.height / frameSize.height;
    final s = scale > scaleY ? scale : scaleY;
    final dx = (size.width - frameSize.width * s) * 0.5;
    final dy = (size.height - frameSize.height * s) * 0.5;

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = const Color(0xFF00E5FF);
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0x2200E5FF);

    for (final d in detections) {
      final r = Rect.fromLTRB(
        dx + d.x1 * frameSize.width * s,
        dy + d.y1 * frameSize.height * s,
        dx + d.x2 * frameSize.width * s,
        dy + d.y2 * frameSize.height * s,
      );
      canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(6)), fill);
      canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(6)), stroke);

      final tp = TextPainter(
        text: TextSpan(
          text: '${(d.score * 100).toStringAsFixed(0)}%',
          style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              backgroundColor: Color(0xCC000000)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, r.topLeft + const Offset(4, 4));
    }
  }

  @override
  bool shouldRepaint(covariant BBoxPainter old) =>
      old.detections != detections || old.frameSize != frameSize;
}
