import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'detection.dart';
import 'temporal_detection_buffer.dart';
import 'bbox_painter.dart';
import 'native_camera.dart';
import 'debug_log_overlay.dart';

void main() {
  runApp(const BarcodeScannerApp());
}

class BarcodeScannerApp extends StatelessWidget {
  const BarcodeScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DMTX Scanner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const ScannerPage(),
    );
  }
}

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final _buffer = TemporalDetectionBuffer(
    returnWindowSize: 12,
    matchIouThreshold: 0.30,
    stabilityThreshold: 0.30,
    emaAlpha: 0.18, // максимально плавно
    maxDetectionAgeMs: 600,
  );

  StreamSubscription<List<Detection>>? _sub;
  List<SmoothedDetection> _smoothed = const [];
  String _modelId = kModelIdMulticlassTail;
  bool _switchingModel = false;
  bool _loadingCustomModel = false;
  late Map<String, String> _modelMap;
  // Model input frame is 320x320 (square). We render in normalized coords so
  // the actual frame size used here only matters for aspect mapping.
  final Size _frameSize = const Size(1, 1);

  @override
  void initState() {
    super.initState();
    _modelMap = Map.from(kModelNames);
    _initModelSelection();
    _sub = DetectionStream.stream().listen((raw) {
      final out = _buffer.append(raw);
      if (mounted) setState(() => _smoothed = out);
    });
  }

  Future<void> _initModelSelection() async {
    try {
      final id = await DetectionStream.getModel();
      if (!mounted) return;
      if (_modelMap.containsKey(id)) {
        setState(() => _modelId = id);
      }
    } catch (_) {
      // Keep default model id if native side is unavailable.
    }
  }

  Future<void> _loadCustomModel() async {
    if (_loadingCustomModel) return;
    setState(() => _loadingCustomModel = true);
    try {
      final info = await DetectionStream.pickCustomModel();
      if (info == null) return;
      final id = info['id'] as String;
      final name = info['name'] as String;
      if (!mounted) return;
      setState(() {
        _modelMap[id] = name;
        _modelId = id;
        _smoothed = const [];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Custom model loaded: $name')),
      );
    } on PlatformException catch (e) {
      if (e.code == 'cancelled') return;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Load failed: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Load failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _loadingCustomModel = false);
    }
  }

  Future<void> _switchModel(String id) async {
    if (_switchingModel || id == _modelId) return;
    setState(() => _switchingModel = true);
    try {
      await DetectionStream.setModel(id);
      if (!mounted) return;
      setState(() {
        _modelId = id;
        _smoothed = const [];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Model switched: ${kModelNames[id] ?? id}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Model switch failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _switchingModel = false);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const NativeCameraView(),
          IgnorePointer(
            child: CustomPaint(
              painter: BBoxPainter(
                  detections: _smoothed, frameSize: _frameSize),
            ),
          ),
          Positioned(
            top: 48,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${(kModelNames[_modelId] ?? kModelDisplayName)} • ${_smoothed.length}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
          Positioned(
            top: 48,
            right: 16,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _modelMap.containsKey(_modelId) ? _modelId : _modelMap.keys.first,
                      dropdownColor: Colors.black87,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      iconEnabledColor: Colors.white,
                      onChanged: _switchingModel ? null : (v) {
                        if (v != null) _switchModel(v);
                      },
                      items: _modelMap.entries.map((e) {
                        return DropdownMenuItem<String>(
                          value: e.key,
                          child: Text(e.value),
                        );
                      }).toList(growable: false),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: _loadingCustomModel ? null : _loadCustomModel,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: _loadingCustomModel
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.folder_open,
                            color: Colors.white, size: 18),
                  ),
                ),
              ],
            ),
          ),
          const DebugLogOverlay(),
        ],
      ),
    );
  }
}
