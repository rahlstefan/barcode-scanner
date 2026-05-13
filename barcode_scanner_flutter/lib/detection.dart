import 'package:flutter/foundation.dart';

const String kModelDisplayName =
    'yolo26n_320_multiclass_no_mosaic_tail_20260512_073544';

const Map<int, String> kDetectionClassNames = {
  0: 'datamatrix',
  1: 'code128',
  2: 'pdf417',
};

String detectionClassLabel(int classId) =>
    kDetectionClassNames[classId] ?? 'cls$classId';

/// Single detection in NORMALIZED model-space coordinates (0..1).
/// `cx,cy,w,h` are center+size in the same normalized space.
@immutable
class Detection {
  final double x1, y1, x2, y2;
  final double score;
  final int classId;
  final int frameId; // monotonic frame counter when produced

  const Detection({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.score,
    required this.classId,
    required this.frameId,
  });

  double get cx => (x1 + x2) * 0.5;
  double get cy => (y1 + y2) * 0.5;
  double get w => (x2 - x1).abs();
  double get h => (y2 - y1).abs();

  double iou(Detection o) {
    final ix1 = x1 > o.x1 ? x1 : o.x1;
    final iy1 = y1 > o.y1 ? y1 : o.y1;
    final ix2 = x2 < o.x2 ? x2 : o.x2;
    final iy2 = y2 < o.y2 ? y2 : o.y2;
    final iw = (ix2 - ix1).clamp(0.0, 1.0);
    final ih = (iy2 - iy1).clamp(0.0, 1.0);
    final inter = iw * ih;
    final ua = w * h + o.w * o.h - inter;
    if (ua <= 0) return 0;
    return inter / ua;
  }
}

/// Smoothed detection emitted to the UI layer.
@immutable
class SmoothedDetection {
  final double x1, y1, x2, y2;
  final double score;
  final int classId;
  final int trackId;

  const SmoothedDetection({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.score,
    required this.classId,
    required this.trackId,
  });
}
