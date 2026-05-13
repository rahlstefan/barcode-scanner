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
    }).asBroadcastStream();
    return _stream!;
  }

  static Future<void> setConfidenceThreshold(double t) async {
    await _control.invokeMethod('setConfidence', {'value': t});
  }

  static Future<void> setModel(String modelId) async {
    await _control.invokeMethod('setModel', {'id': modelId});
  }

  static Future<String> getModel() async {
    final r = await _control.invokeMethod<String>('getModel');
    return r ?? 'multiclass_tail';
  }

  static Future<List<Map<String, dynamic>>> listModels() async {
    final r = await _control.invokeMethod<List<dynamic>>('listModels') ?? const [];
    return r
        .map((e) => (e as Map).cast<dynamic, dynamic>())
        .map((m) => {
              'id': (m['id'] ?? '').toString(),
              'name': (m['name'] ?? '').toString(),
            })
        .toList(growable: false);
  }

  static Future<String> runSelfTest() async {
    final r = await _control.invokeMethod<String>('selfTest');
    return r ?? '<null>';
  }

  static Future<String> getLogsJson() async {
    final r = await _control.invokeMethod<String>('getLogsJson');
    return r ?? '[]';
  }

  static Future<String> saveLogsJson() async {
    final r = await _control.invokeMethod<String>('saveLogsJson');
    return r ?? '<null>';
  }

  static Future<void> clearNativeLogs() async {
    await _control.invokeMethod('clearLogs');
  }

  static Future<Map<String, String>?> pickCustomModel() async {
    final r = await _control.invokeMethod<Map<dynamic, dynamic>>('pickCustomModel');
    if (r == null) return null;
    return {
      'id': (r['id'] ?? '').toString(),
      'name': (r['name'] ?? '').toString(),
    };
  }
}

/// Native log line stream (mirrors NSLog into the app via EventChannel
/// `com.bboxfix/logs`). Useful when there is no Mac to read device logs.
class NativeLogStream {
  static const _channel = EventChannel('com.bboxfix/logs');
  static Stream<String>? _stream;
  static Stream<String> stream() {
    _stream ??= _channel.receiveBroadcastStream().map((e) => e.toString()).asBroadcastStream();
    return _stream!;
  }
}
