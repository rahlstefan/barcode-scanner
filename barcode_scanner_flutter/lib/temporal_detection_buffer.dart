// Port of the temporal-buffer / "drainPendingDetections" smoothing logic
// reconstructed from dmtx_bbox_reconstruction.md.
//
// The detector runs every frame, but the rendered box must NOT track raw
// per-frame jitter. We:
//   1. Append accepted detections into a sliding window keyed by track.
//   2. Cluster across the window by IoU to recover stable tracks.
//   3. Emit the EMA-smoothed corners of each track that has at least
//      `stabilityThreshold` of frames in its window.
//   4. Hold the last stable box for `maxDetectionAgeMs` even when the current
//      frame has no fresh detection — this is what makes it look like
//      "tracking the previous rendered position".

import 'dart:collection';
import 'detection.dart';

class _Track {
  final int id;
  final Queue<Detection> recent = Queue<Detection>();
  // EMA-smoothed corners.
  double sx1, sy1, sx2, sy2, sScore;
  int lastFrameId;
  int lastTimestampMs;
  int classId;

  _Track({
    required this.id,
    required Detection seed,
    required this.lastTimestampMs,
  })  : sx1 = seed.x1,
        sy1 = seed.y1,
        sx2 = seed.x2,
        sy2 = seed.y2,
        sScore = seed.score,
        lastFrameId = seed.frameId,
        classId = seed.classId {
    recent.add(seed);
  }
}

class TemporalDetectionBuffer {
  /// How many recent frames to remember per track.
  final int returnWindowSize;

  /// Minimum IoU to consider two detections part of the same track.
  final double matchIouThreshold;

  /// Fraction of the window that a track must have observations in
  /// before it is considered "stable" enough to be drawn.
  final double stabilityThreshold;

  /// EMA factor (0..1). Lower = smoother, higher = more responsive.
  /// Maximally smooth: keep this small.
  final double emaAlpha;

  /// Keep the last known box alive for this many ms after the model
  /// stops emitting it — this is the temporal hold.
  final int maxDetectionAgeMs;

  int _frameCounter = 0;
  int _nextTrackId = 1;
  final List<_Track> _tracks = [];

  TemporalDetectionBuffer({
    this.returnWindowSize = 8,
    this.matchIouThreshold = 0.20,
    this.stabilityThreshold = 0.30,
    this.emaAlpha = 0.55,
    this.maxDetectionAgeMs = 180,
    this.renderNmsIou = 0.30,
  });

  /// IoU above which two emitted (rendered) boxes are merged to a single
  /// one — kills "stacking" duplicates that survived as separate tracks
  /// when the camera moved fast and IoU matching produced a stale + a
  /// fresh track for the same physical object.
  final double renderNmsIou;

  /// Feed raw per-frame detections from the native detector.
  /// Returns the smoothed set that should be drawn on screen.
  List<SmoothedDetection> append(List<Detection> raw) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _frameCounter += 1;
    final fid = _frameCounter;

    // Re-stamp incoming detections with the current frame id.
    final stamped = raw
        .map((d) => Detection(
              x1: d.x1,
              y1: d.y1,
              x2: d.x2,
              y2: d.y2,
              score: d.score,
              classId: d.classId,
              frameId: fid,
            ))
        .toList();

    // 1) Greedy IoU match against existing tracks.
    //    Match against the LAST RAW detection (not the smoothed box),
    //    so that on fast camera motion the lagging EMA does not break
    //    track association.
    final used = List<bool>.filled(stamped.length, false);
    for (final t in _tracks) {
      final ref = t.recent.isNotEmpty
          ? t.recent.last
          : Detection(
              x1: t.sx1,
              y1: t.sy1,
              x2: t.sx2,
              y2: t.sy2,
              score: t.sScore,
              classId: t.classId,
              frameId: t.lastFrameId);
      int bestIdx = -1;
      double bestIou = matchIouThreshold;
      for (var i = 0; i < stamped.length; i++) {
        if (used[i]) continue;
        if (stamped[i].classId != t.classId) continue;
        final iou = ref.iou(stamped[i]);
        if (iou > bestIou) {
          bestIou = iou;
          bestIdx = i;
        }
      }
      if (bestIdx >= 0) {
        final m = stamped[bestIdx];
        used[bestIdx] = true;
        t.recent.add(m);
        while (t.recent.length > returnWindowSize) {
          t.recent.removeFirst();
        }
        // EMA update.
        t.sx1 = t.sx1 + emaAlpha * (m.x1 - t.sx1);
        t.sy1 = t.sy1 + emaAlpha * (m.y1 - t.sy1);
        t.sx2 = t.sx2 + emaAlpha * (m.x2 - t.sx2);
        t.sy2 = t.sy2 + emaAlpha * (m.y2 - t.sy2);
        t.sScore = t.sScore + emaAlpha * (m.score - t.sScore);
        t.lastFrameId = fid;
        t.lastTimestampMs = nowMs;
      }
    }

    // 2) Spawn new tracks for unmatched detections, but suppress those
    //    that overlap an existing track's smoothed box (NMS-like) to
    //    prevent duplicate stacked boxes when the EMA lagged behind.
    for (var i = 0; i < stamped.length; i++) {
      if (used[i]) continue;
      final s = stamped[i];
      var suppress = false;
      for (final t in _tracks) {
        if (t.classId != s.classId) continue;
        final cur = Detection(
            x1: t.sx1,
            y1: t.sy1,
            x2: t.sx2,
            y2: t.sy2,
            score: t.sScore,
            classId: t.classId,
            frameId: t.lastFrameId);
        if (cur.iou(s) > renderNmsIou) {
          // Snap the existing track to this fresh detection so we do
          // not lose responsiveness during motion.
          t.recent.add(s);
          while (t.recent.length > returnWindowSize) {
            t.recent.removeFirst();
          }
          t.sx1 = s.x1;
          t.sy1 = s.y1;
          t.sx2 = s.x2;
          t.sy2 = s.y2;
          t.sScore = s.score;
          t.lastFrameId = fid;
          t.lastTimestampMs = nowMs;
          suppress = true;
          break;
        }
      }
      if (!suppress) {
        _tracks.add(_Track(
          id: _nextTrackId++,
          seed: s,
          lastTimestampMs: nowMs,
        ));
      }
    }

    // 3) Trim stale window entries and drop dead tracks.
    final keepWindowFrom = fid - returnWindowSize;
    _tracks.removeWhere((t) {
      while (t.recent.isNotEmpty && t.recent.first.frameId < keepWindowFrom) {
        t.recent.removeFirst();
      }
      final age = nowMs - t.lastTimestampMs;
      return age > maxDetectionAgeMs;
    });

    // 4) Emit only tracks that are stable AND were updated this frame
    //    (or very recently) — no more "ghost" boxes lingering for half
    //    a second after the underlying detection disappeared.
    final minObs =
        (returnWindowSize * stabilityThreshold).ceil().clamp(1, returnWindowSize);
    final candidates = <SmoothedDetection>[];
    for (final t in _tracks) {
      final age = nowMs - t.lastTimestampMs;
      final stableEnough = t.recent.length >= minObs;
      if (stableEnough && age <= maxDetectionAgeMs) {
        candidates.add(SmoothedDetection(
          x1: t.sx1,
          y1: t.sy1,
          x2: t.sx2,
          y2: t.sy2,
          score: t.sScore,
          classId: t.classId,
          trackId: t.id,
        ));
      }
    }

    // 5) Final render-side NMS to guarantee no two visibly overlapping
    //    boxes are drawn for the same physical target.
    candidates.sort((a, b) => b.score.compareTo(a.score));
    final out = <SmoothedDetection>[];
    for (final c in candidates) {
      var keep = true;
      for (final k in out) {
        if (k.classId != c.classId) continue;
        if (_iou(c, k) > renderNmsIou) {
          keep = false;
          break;
        }
      }
      if (keep) out.add(c);
    }
    return out;
  }

  static double _iou(SmoothedDetection a, SmoothedDetection b) {
    final ix1 = a.x1 > b.x1 ? a.x1 : b.x1;
    final iy1 = a.y1 > b.y1 ? a.y1 : b.y1;
    final ix2 = a.x2 < b.x2 ? a.x2 : b.x2;
    final iy2 = a.y2 < b.y2 ? a.y2 : b.y2;
    final iw = ix2 - ix1;
    final ih = iy2 - iy1;
    if (iw <= 0 || ih <= 0) return 0;
    final inter = iw * ih;
    final aw = (a.x2 - a.x1) * (a.y2 - a.y1);
    final bw = (b.x2 - b.x1) * (b.y2 - b.y1);
    final uni = aw + bw - inter;
    return uni <= 0 ? 0 : inter / uni;
  }
}
