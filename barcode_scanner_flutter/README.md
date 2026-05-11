# DMTX Scanner — Flutter

iOS-first DataMatrix scanner.

- **UI**: Flutter (Dart) — `CustomPainter` overlay on top of native preview.
- **Camera**: native iOS `AVCaptureSession` + `AVCaptureVideoPreviewLayer`,
  exposed to Flutter as a `UiKitView` PlatformView.
- **Inference**: TensorFlowLiteSwift, int8 quantized YOLO26n
  (`assets/models/best_int8.tflite`, 320×320, single class `item`,
  exported with embedded NMS).
- **Smoothing**: Dart port of the temporal-buffer logic reconstructed in
  `dmtx_bbox_reconstruction.md` — sliding window per track, EMA on box
  corners, temporal hold up to `maxDetectionAgeMs` so the box "tracks the
  previous rendered position" instead of jittering with raw YOLO output.

## Channels

| Channel                       | Type           | Direction | Purpose                       |
| ----------------------------- | -------------- | --------- | ----------------------------- |
| `com.bboxfix/camera_preview`  | PlatformView   | iOS → UI  | Live AVFoundation preview     |
| `com.bboxfix/detections`      | EventChannel   | iOS → UI  | Per-frame normalized boxes    |
| `com.bboxfix/control`         | MethodChannel  | UI → iOS  | `setConfidence(value)`        |

## Build (CI)

`flutter build ios --release --no-codesign` is run by
`.github/workflows/build-unsigned-ipa-flutter.yml` on a `macos-15` runner.
The resulting `Runner.app` is repackaged into `Payload/` and zipped into
`DMTXScanner-unsigned.ipa` for Sideloadly install on a free Apple ID.

## Local dev

```sh
cd barcode_scanner_flutter
flutter create --org com.bboxfix --project-name barcode_scanner_flutter --platforms=ios .
flutter pub get
cd ios && pod install && cd ..
flutter run -d <device-id>
```
