import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'detection.dart';

/// Bridge to the native iOS AVFoundation camera + TFLite int8 detector.
///
///  - PlatformView identifier: `com.bboxfix/camera_preview`
///  - EventChannel:           `com.bboxfix/detections`
///  - MethodChannel:          `com.bboxfix/control`
class NativeCameraView extends StatelessWidget {
  const NativeCameraView({super.key});

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return const UiKitView(
        viewType: 'com.bboxfix/camera_preview',
        creationParams: <String, dynamic>{},
        creationParamsCodec: StandardMessageCodec(),
      );
    }
    return const ColoredBox(color: Color(0xFF111111));
  }
}

class DetectionStream {
  static const _channel = EventChannel('com.bboxfix/detections');
  static const _control = MethodChannel('com.bboxfix/control');

  static Stream<List<Detection>>? _stream;

  static Stream<List<Detection>> stream() {
    _stream ??= _channel.receiveBroadcastStream().map((event) {
      final list = (event as List).cast<dynamic>();
      return list.map<Detection>((e) {
        final m = (e as Map).cast<dynamic, dynamic>();
        return Detection(
          x1: (m['x1'] as num).toDouble(),
          y1: (m['y1'] as num).toDouble(),
          x2: (m['x2'] as num).toDouble(),
          y2: (m['y2'] as num).toDouble(),
          score: (m['score'] as num).toDouble(),
          classId: (m['cls'] as num).toInt(),
          frameId: (m['fid'] as num).toInt(),
        );
      }).toList();
    });
    return _stream!;
  }

  static Future<void> setConfidenceThreshold(double t) async {
    await _control.invokeMethod('setConfidence', {'value': t});
  }
}
