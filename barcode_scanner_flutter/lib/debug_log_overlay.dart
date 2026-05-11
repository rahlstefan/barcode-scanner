import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'native_camera.dart';

/// On-screen log overlay (no Mac required).
///
/// Tap the "LOG" pill (top-right) to expand/collapse a scrollable panel with
/// the most recent native log lines (mirrored from iOS NSLog via the
/// `com.bboxfix/logs` EventChannel). A "TEST" button runs the native
/// inference self-test and appends the result to the log.
class DebugLogOverlay extends StatefulWidget {
  const DebugLogOverlay({super.key, this.maxLines = 200});
  final int maxLines;

  @override
  State<DebugLogOverlay> createState() => _DebugLogOverlayState();
}

class _DebugLogOverlayState extends State<DebugLogOverlay> {
  final List<String> _lines = [];
  StreamSubscription<String>? _sub;
  bool _expanded = true;
  int _detCount = 0;
  int _detFrames = 0;
  StreamSubscription? _detSub;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _sub = NativeLogStream.stream().listen((line) {
      if (!mounted) return;
      setState(() {
        _lines.add(line);
        if (_lines.length > widget.maxLines) {
          _lines.removeRange(0, _lines.length - widget.maxLines);
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }, onError: (e) {
      _append('logs stream error: $e');
    });
    // Track how many detection batches actually arrive in Dart.
    _detSub = DetectionStream.stream().listen((dets) {
      _detFrames++;
      _detCount += dets.length;
    });
    _append('--- log overlay ready ---');
  }

  void _append(String s) {
    setState(() {
      _lines.add(s);
      if (_lines.length > widget.maxLines) {
        _lines.removeRange(0, _lines.length - widget.maxLines);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _detSub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _runSelfTest() async {
    _append('>>> running self-test...');
    try {
      final r = await DetectionStream.runSelfTest();
      _append('SELF-TEST RESULT: $r');
    } on PlatformException catch (e) {
      _append('SELF-TEST ERROR: $e');
    }
  }

  Future<void> _copyLogs() async {
    await Clipboard.setData(ClipboardData(text: _lines.join('\n')));
    _append('--- copied ${_lines.length} lines to clipboard ---');
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final h = _expanded ? mq.size.height * 0.45 : 0.0;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _expanded
                            ? 'LOG ▼  dets=$_detCount/${_detFrames}f'
                            : 'LOG ▲  dets=$_detCount/${_detFrames}f',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      _miniBtn('TEST', _runSelfTest),
                      const SizedBox(width: 6),
                      _miniBtn('COPY', _copyLogs),
                      const SizedBox(width: 6),
                      _miniBtn('CLR', () => setState(_lines.clear)),
                    ],
                  ),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              height: h,
              margin: const EdgeInsets.only(top: 4, left: 4, right: 4, bottom: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.78),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white24),
              ),
              child: _expanded
                  ? Scrollbar(
                      controller: _scroll,
                      thumbVisibility: true,
                      child: ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(6),
                        itemCount: _lines.length,
                        itemBuilder: (_, i) => Text(
                          _lines[i],
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 10,
                            fontFamily: 'Courier',
                            height: 1.15,
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniBtn(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.blueGrey.shade800,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white24),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
