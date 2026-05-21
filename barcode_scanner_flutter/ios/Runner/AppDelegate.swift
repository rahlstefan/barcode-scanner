import UIKit
import Flutter
import AVFoundation
import TensorFlowLite
import Accelerate
#if canImport(CRPTZXBridge)
import CRPTZXBridge
#elseif canImport(ZXingObjC)
import ZXingObjC
#endif

// =====================================================================
//  Barcode Scanner — native iOS layer
//  - AVFoundation capture (AVCaptureSession + AVCaptureVideoDataOutput)
//  - TensorFlowLiteSwift float inference
//      model: yolo26n_320_multiclass_no_mosaic_tail_20260512_073544_float16.tflite
//      input  : float32 [1,320,320,3] normalized 0..1
//      output : float32 [1,300,6]      embedded postprocess
//                                    layout: x1, y1, x2, y2, score, cls
//                                    coords normalized to 0..1
//
//  Logs: NSLog + in-app overlay (Dart side reads `com.bboxfix/logs`).
// =====================================================================

// ---------------------------------------------------------------------
// MARK: - Global logger (NSLog + Flutter EventChannel + session history)
// ---------------------------------------------------------------------

final class DLog {
  static let shared = DLog()
  private static let iso = ISO8601DateFormatter()
  private let lock = NSLock()
  private var lines: [String] = []
  private var entries: [[String: Any]] = []
  private var nextId: Int = 1
  private var sink: FlutterEventSink?

  func attach(sink: @escaping FlutterEventSink) {
    lock.lock()
    self.sink = sink
    let snapshot = lines
    lock.unlock()
    DispatchQueue.main.async {
      for line in snapshot { sink(line) }
    }
  }

  func detach() {
    lock.lock(); defer { lock.unlock() }
    sink = nil
  }

  func clear() {
    lock.lock(); defer { lock.unlock() }
    lines.removeAll(keepingCapacity: false)
    entries.removeAll(keepingCapacity: false)
    nextId = 1
  }

  func exportJSON() -> String {
    lock.lock()
    let snapshot = entries
    lock.unlock()
    guard JSONSerialization.isValidJSONObject(snapshot),
          let data = try? JSONSerialization.data(withJSONObject: snapshot,
                                                 options: [.prettyPrinted, .sortedKeys]),
          let text = String(data: data, encoding: .utf8) else {
      return "[]"
    }
    return text
  }

  func saveJSONFile() throws -> String {
    let json = exportJSON()
    let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    let stamp = DLog.iso.string(from: Date()).replacingOccurrences(of: ":", with: "-")
    let url = dir.appendingPathComponent("bboxfix_logs_\(stamp).json")
    try json.data(using: .utf8)?.write(to: url, options: .atomic)
    return url.path
  }

  func log(_ msg: String, fields: [String: Any] = [:]) {
    let uptime = CACurrentMediaTime()
    let ts = String(format: "%.3f", uptime)
    let line = "[\(ts)] \(msg)"
    NSLog("[DMTX] %@", line)
    var sinkRef: FlutterEventSink?
    lock.lock()
    var entry: [String: Any] = [
      "id": nextId,
      "uptimeSec": uptime,
      "wallTime": DLog.iso.string(from: Date()),
      "message": msg,
      "line": line,
    ]
    for (k, v) in fields { entry[k] = v }
    nextId += 1
    lines.append(line)
    entries.append(entry)
    sinkRef = sink
    lock.unlock()
    if let s = sinkRef {
      DispatchQueue.main.async { s(line) }
    }
  }
}

@inline(__always) func dlog(_ msg: @autoclosure () -> String) {
  DLog.shared.log(msg())
}

// ---------------------------------------------------------------------
// MARK: - AppDelegate
// ---------------------------------------------------------------------

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var detectionsSink: FlutterEventSink?
  private var detector: YoloDetector?
  private let detectorLock = NSLock()
  private var lastDetectorError: String?
  private var pendingPickResult: FlutterResult?
  private var currentModelId: String = "multiclass_tail"
  private var confidenceThreshold: Float = 0.25
  private weak var lastCameraView: CameraPreviewView?
  private let barcodeDecoder = BarcodeDecoder()
  private var perfLatenciesMs: [Double] = []
  private var perfFrames: Int = 0
  private var perfDetections: Int = 0
  private var perfClassHits: [Int: Int] = [:]
  private var lastPerfLogTime: CFTimeInterval = CACurrentMediaTime()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    dlog("===== AppDelegate.didFinishLaunching =====")
    GeneratedPluginRegistrant.register(with: self)
    let controller = window?.rootViewController as! FlutterViewController
    let messenger = controller.binaryMessenger

    // 1. Logs EventChannel — register FIRST so Dart can attach early.
    let logsChannel = FlutterEventChannel(
      name: "com.bboxfix/logs", binaryMessenger: messenger)
    logsChannel.setStreamHandler(LogsStreamHandler())

    // 2. Detections EventChannel.
    let eventChannel = FlutterEventChannel(
      name: "com.bboxfix/detections", binaryMessenger: messenger)
    eventChannel.setStreamHandler(self)

    // 3. Control MethodChannel.
    let methodChannel = FlutterMethodChannel(
      name: "com.bboxfix/control", binaryMessenger: messenger)
    methodChannel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "setConfidence":
        if let args = call.arguments as? [String: Any],
           let v = args["value"] as? Double {
          self.confidenceThreshold = Float(v)
          dlog(String(format: "confidence threshold set to %.2f", v))
          result(nil)
        } else { result(FlutterError(code: "args", message: "value required", details: nil)) }
      case "setModel":
        guard let args = call.arguments as? [String: Any],
              let modelId = args["id"] as? String
        else {
          result(FlutterError(code: "args", message: "id required", details: nil))
          return
        }
        self.loadDetector(modelId: modelId, reason: "manual-switch")
        if self.detector == nil {
          result(FlutterError(code: "set_model",
                              message: self.lastDetectorError ?? "detector nil",
                              details: nil))
        } else {
          result(nil)
        }
      case "getModel":
        result(self.currentModelId)
      case "listModels":
        result(YoloDetector.allModels.map { ["id": $0.id, "name": $0.displayName] })
      case "selfTest":
        self.detectorLock.lock()
        let det = self.detector
        self.detectorLock.unlock()
        if let det = det {
          let res = det.runSelfTest()
          dlog("manual self-test -> \(res)")
          result(res)
        } else {
          let msg = "detector nil; lastError=\(self.lastDetectorError ?? "<none>")"
          dlog("manual self-test -> \(msg)")
          result(msg)
        }
      case "getLogsJson":
        result(DLog.shared.exportJSON())
      case "saveLogsJson":
        do {
          let path = try DLog.shared.saveJSONFile()
          dlog("logs json saved -> \(path)")
          result(path)
        } catch {
          result(FlutterError(code: "save_logs_json",
                              message: "\(error)", details: nil))
        }
      case "clearLogs":
        DLog.shared.clear()
        dlog("logs cleared")
        result(nil)
      case "pickCustomModel":
        self.pendingPickResult = result
        DispatchQueue.main.async { [weak self] in
          guard let self = self else { return }
          let picker = UIDocumentPickerViewController(
            documentTypes: ["public.data"],
            in: .import)
          picker.delegate = self
          picker.allowsMultipleSelection = false
          self.window?.rootViewController?.present(picker, animated: true)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // 4. Load TFLite model (after logs are wired).
    loadDetector(modelId: currentModelId, reason: "startup")

    // 5. PlatformView factory for the camera preview.
    let factory = CameraPreviewFactory(messenger: messenger, owner: self)
    self.registrar(forPlugin: "CameraPreviewPlugin")?
      .register(factory, withId: "com.bboxfix/camera_preview")

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Called by the camera view on every frame (videoQueue).
  func handleSampleBuffer(_ pixelBuffer: CVPixelBuffer, frameId: Int) {
    detectorLock.lock()
    let det = detector
    detectorLock.unlock()
    guard let det = det else {
      if frameId % 60 == 0 {
        dlog("frame=\(frameId) detector is nil; lastError=\(lastDetectorError ?? "<none>")")
      }
      return
    }
    let t0 = CACurrentMediaTime()
    let rawDets = det.run(pixelBuffer: pixelBuffer, frameId: frameId,
                          threshold: confidenceThreshold)

    // ZXing decode: for each YOLO detection, crop the frame and decode the barcode.
    // Only attempt on frames where YOLO found something (saves CPU on empty frames).
    var dets = rawDets
    if !rawDets.isEmpty {
      dets = rawDets.map { d in
        let x1  = (d["x1"] as? Float) ?? 0
        let y1  = (d["y1"] as? Float) ?? 0
        let x2  = (d["x2"] as? Float) ?? 1
        let y2  = (d["y2"] as? Float) ?? 1
        let cls = (d["cls"] as? Int) ?? 0
        if let text = barcodeDecoder.decode(
          pixelBuffer: pixelBuffer,
          x1: x1, y1: y1, x2: x2, y2: y2,
          cls: cls
        ) {
          var updated = d
          updated["text"] = text
          return updated
        }
        return d
      }
    }

    let dt = (CACurrentMediaTime() - t0) * 1000.0
    perfFrames += 1
    perfDetections += dets.count
    perfLatenciesMs.append(dt)
    if perfLatenciesMs.count > 180 {
      perfLatenciesMs.removeFirst(perfLatenciesMs.count - 180)
    }
    for detMap in dets {
      let cls = (detMap["cls"] as? Int) ?? 0
      perfClassHits[cls, default: 0] += 1
    }
    if frameId % 30 == 0 {
      let now = CACurrentMediaTime()
      let elapsed = max(now - lastPerfLogTime, 0.001)
      let fps = Double(perfFrames) / elapsed
      let avg = perfLatenciesMs.reduce(0, +) / Double(max(perfLatenciesMs.count, 1))
      let sorted = perfLatenciesMs.sorted()
      let p95Index = min(sorted.count - 1, Int(Double(max(sorted.count - 1, 0)) * 0.95))
      let p95 = sorted.isEmpty ? dt : sorted[p95Index]
      let detsPerFrame = Double(perfDetections) / Double(max(perfFrames, 1))
      let clsSummary = perfClassHits.keys.sorted().map {
        "\(det.className(for: $0))=\(perfClassHits[$0] ?? 0)"
      }.joined(separator: ",")
      DLog.shared.log(
        String(format: "frame=%d dets=%d thr=%.2f infer=%.1fms sink=%@ fps=%.1f avg=%.1f p95=%.1f det/frame=%.2f cls={%@}",
               frameId, dets.count, Double(confidenceThreshold), dt,
               detectionsSink == nil ? "NIL" : "OK", fps, avg, p95,
               detsPerFrame, clsSummary),
        fields: [
          "kind": "runtime_perf",
          "frameId": frameId,
          "detections": dets.count,
          "threshold": confidenceThreshold,
          "inferMs": dt,
          "fps": fps,
          "inferAvgMs": avg,
          "inferP95Ms": p95,
          "detectionsPerFrame": detsPerFrame,
          "classHits": perfClassHits,
        ])
      lastPerfLogTime = now
      perfFrames = 0
      perfDetections = 0
      perfClassHits.removeAll()
    } else if !dets.isEmpty {
      let topCls = det.className(for: (dets.first?["cls"] as? Int) ?? 0)
      dlog(String(format: "frame=%d dets=%d top=%.2f infer=%.1fms",
                  frameId, dets.count,
                  Double((dets.first?["score"] as? Float) ?? 0), dt) +
           " cls=\(topCls)")
    }
    if let sink = detectionsSink {
      DispatchQueue.main.async { sink(dets) }
    }
  }

  func setActiveCameraView(_ v: CameraPreviewView) { lastCameraView = v }

  private func resetPerfStats() {
    perfLatenciesMs.removeAll(keepingCapacity: true)
    perfFrames = 0
    perfDetections = 0
    perfClassHits.removeAll(keepingCapacity: true)
    lastPerfLogTime = CACurrentMediaTime()
  }

  private func loadDetector(modelId: String, reason: String) {
    guard let spec = YoloDetector.spec(for: modelId) else {
      lastDetectorError = "unknown model id: \(modelId)"
      dlog("FAILED to switch model: \(lastDetectorError ?? "unknown")")
      return
    }
    do {
      let newDet = try YoloDetector(spec: spec)
      detectorLock.lock()
      detector = newDet
      detectorLock.unlock()
      currentModelId = modelId
      lastDetectorError = nil
      resetPerfStats()
      dlog("YOLO model loaded OK id=\(modelId) reason=\(reason)")
      DLog.shared.log(newDet.startupSummary(), fields: [
        "kind": "model_metrics",
        "modelId": modelId,
        "model": spec.displayName,
        "precision": spec.valPrecision,
        "recall": spec.valRecall,
        "map50": spec.valMap50,
        "map50_95": spec.valMap50_95,
        "classes": spec.classNames,
      ])
      DispatchQueue.global(qos: .utility).async { [weak self] in
        guard let self = self else { return }
        self.detectorLock.lock()
        let det = self.detector
        self.detectorLock.unlock()
        if let s = det?.runSelfTest() { dlog("SELF-TEST: \(s)") }
      }
    } catch {
      lastDetectorError = "\(error)"
      detectorLock.lock()
      detector = nil
      detectorLock.unlock()
      dlog("FAILED to load model id=\(modelId): \(error)")
    }
  }
}

extension AppDelegate: FlutterStreamHandler {
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    detectionsSink = events
    dlog("detections sink ATTACHED")
    return nil
  }
  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    detectionsSink = nil
    dlog("detections sink DETACHED")
    return nil
  }
}

final class LogsStreamHandler: NSObject, FlutterStreamHandler {
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    DLog.shared.attach(sink: events)
    DLog.shared.log("logs sink ATTACHED")
    return nil
  }
  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    DLog.shared.detach()
    return nil
  }
}

// ---------------------------------------------------------------------
// MARK: - Camera PlatformView
// ---------------------------------------------------------------------

class CameraPreviewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger
  private weak var owner: AppDelegate?
  init(messenger: FlutterBinaryMessenger, owner: AppDelegate) {
    self.messenger = messenger
    self.owner = owner
  }
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64,
              arguments args: Any?) -> FlutterPlatformView {
    return CameraPreviewView(frame: frame, owner: owner)
  }
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    return FlutterStandardMessageCodec.sharedInstance()
  }
}

class CameraPreviewView: NSObject, FlutterPlatformView,
                          AVCaptureVideoDataOutputSampleBufferDelegate {
  private let container: UIView
  private let session = AVCaptureSession()
  private var previewLayer: AVCaptureVideoPreviewLayer!
  private let videoQueue = DispatchQueue(label: "com.bboxfix.video", qos: .userInitiated)
  private weak var owner: AppDelegate?
  private var frameId: Int = 0

  init(frame: CGRect, owner: AppDelegate?) {
    self.container = UIView(frame: frame)
    self.owner = owner
    super.init()
    container.backgroundColor = .black
    owner?.setActiveCameraView(self)
    setupSession()
  }

  func view() -> UIView { container }

  private func setupSession() {
    session.beginConfiguration()
    session.sessionPreset = .vga640x480

    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                               for: .video, position: .back),
          let input = try? AVCaptureDeviceInput(device: device),
          session.canAddInput(input)
    else {
      dlog("camera: no back camera available")
      session.commitConfiguration()
      return
    }
    session.addInput(input)

    let output = AVCaptureVideoDataOutput()
    output.videoSettings = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]
    output.alwaysDiscardsLateVideoFrames = true
    output.setSampleBufferDelegate(self, queue: videoQueue)
    if session.canAddOutput(output) { session.addOutput(output) }
    if let conn = output.connection(with: .video) {
      if conn.isVideoOrientationSupported {
        conn.videoOrientation = .portrait
      }
      dlog("camera: data-output orientation=\(conn.videoOrientation.rawValue) suppOrient=\(conn.isVideoOrientationSupported)")
    }
    session.commitConfiguration()

    previewLayer = AVCaptureVideoPreviewLayer(session: session)
    previewLayer.videoGravity = .resizeAspectFill
    previewLayer.frame = container.bounds
    previewLayer.connection?.videoOrientation = .portrait
    container.layer.addSublayer(previewLayer)
    container.layer.masksToBounds = true

    NotificationCenter.default.addObserver(
      forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      self?.previewLayer.frame = self?.container.bounds ?? .zero
    }

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      self?.session.startRunning()
      dlog("camera: session.startRunning() called")
    }
  }

  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                     from connection: AVCaptureConnection) {
    guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    frameId &+= 1
    if frameId == 1 {
      let w = CVPixelBufferGetWidth(pb)
      let h = CVPixelBufferGetHeight(pb)
      let fmt = CVPixelBufferGetPixelFormatType(pb)
      let f0 = UInt8((fmt >> 24) & 0xff), f1 = UInt8((fmt >> 16) & 0xff)
      let f2 = UInt8((fmt >> 8) & 0xff),  f3 = UInt8(fmt & 0xff)
      let fc = String(bytes: [f0, f1, f2, f3], encoding: .ascii) ?? "?"
      dlog("first frame: \(w)x\(h) fmt='\(fc)' (0x\(String(fmt, radix:16)))")
    }
    owner?.handleSampleBuffer(pb, frameId: frameId)
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      if self.previewLayer.frame != self.container.bounds {
        self.previewLayer.frame = self.container.bounds
      }
    }
  }
}

// ---------------------------------------------------------------------
// MARK: - YOLO float32 detector (new multiclass float16 asset)
//   - TFLiteSwift 2.14 lacks an `int8` case in Tensor.DataType, so we
//     ship the float16 model whose I/O is float32 (weights are fp16).
//   - input  : float32 [1,320,320,3]   pixel/255
//   - output : float32 [1,300,6]       NMS embedded
//              layout per row: x1, y1, x2, y2, score, cls (coords 0..1)
// ---------------------------------------------------------------------

// ---------------------------------------------------------------------
// MARK: - Barcode Decoder backend selector
// ---------------------------------------------------------------------

private protocol BarcodeDecodingBackend {
  func decode(
    pixelBuffer: CVPixelBuffer,
    x1: Float, y1: Float, x2: Float, y2: Float,
    cls: Int
  ) -> String?
}

#if canImport(CRPTZXBridge)
private final class Epoch8Backend: BarcodeDecodingBackend {
  func decode(
    pixelBuffer: CVPixelBuffer,
    x1: Float, y1: Float, x2: Float, y2: Float,
    cls: Int
  ) -> String? {
    return CRPTZXBridge.decode(inPixelBuffer: pixelBuffer,
                               x1: x1, y1: y1, x2: x2, y2: y2,
                               cls: cls)
  }
}
#endif

#if canImport(ZXingObjC)
private final class ZXingObjCBackend: BarcodeDecodingBackend {
  private let dmReader      = ZXDataMatrixReader()
  private let code128Reader = ZXCode128Reader()
  private let pdf417Reader  = ZXPDF417Reader()

  private let dmHints: ZXDecodeHints = {
    let h = ZXDecodeHints()
    h.tryHarder = true
    return h
  }()

  func decode(
    pixelBuffer: CVPixelBuffer,
    x1: Float, y1: Float, x2: Float, y2: Float,
    cls: Int
  ) -> String? {
    guard let cgImage = cropToCGImage(pixelBuffer, x1: x1, y1: y1, x2: x2, y2: y2) else {
      return nil
    }
    guard let source = ZXCGImageLuminanceSource(cgImage: cgImage) else { return nil }
    let bitmap = ZXBinaryBitmap(binarizer: ZXHybridBinarizer(source: source))

    let result: ZXResult?
    switch cls {
    case 0:
      result = dmReader.decode(bitmap, hints: dmHints)
    case 1:
      result = code128Reader.decode(bitmap, hints: nil)
    case 2:
      result = pdf417Reader.decode(bitmap, hints: nil)
    default:
      return nil
    }
    return result?.text
  }

  private func cropToCGImage(
    _ pb: CVPixelBuffer,
    x1: Float, y1: Float, x2: Float, y2: Float
  ) -> CGImage? {
    CVPixelBufferLockBaseAddress(pb, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }

    let pbW    = CVPixelBufferGetWidth(pb)
    let pbH    = CVPixelBufferGetHeight(pb)
    let stride = CVPixelBufferGetBytesPerRow(pb)
    guard let base = CVPixelBufferGetBaseAddress(pb) else { return nil }

    let side = min(pbW, pbH)
    let xOff = (pbW - side) / 2
    let yOff = (pbH - side) / 2

    var cx1 = xOff + Int((x1 * Float(side)).rounded())
    var cy1 = yOff + Int((y1 * Float(side)).rounded())
    var cx2 = xOff + Int((x2 * Float(side)).rounded())
    var cy2 = yOff + Int((y2 * Float(side)).rounded())
    cx1 = max(0, min(cx1, pbW - 1))
    cy1 = max(0, min(cy1, pbH - 1))
    cx2 = max(cx1 + 1, min(cx2, pbW))
    cy2 = max(cy1 + 1, min(cy2, pbH))

    let cropW = cx2 - cx1
    let cropH = cy2 - cy1
    var bytes = [UInt8](repeating: 0, count: cropW * cropH * 4)
    bytes.withUnsafeMutableBytes { dst in
      let dstBase = dst.baseAddress!
      for row in 0..<cropH {
        memcpy(
          dstBase.advanced(by: row * cropW * 4),
          base.advanced(by: (cy1 + row) * stride + cx1 * 4),
          cropW * 4
        )
      }
    }
    let cfData = Data(bytes) as CFData
    guard let provider = CGDataProvider(data: cfData) else { return nil }
    return CGImage(
      width: cropW, height: cropH,
      bitsPerComponent: 8, bitsPerPixel: 32,
      bytesPerRow: cropW * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGBitmapInfo(rawValue:
        CGBitmapInfo.byteOrder32Little.rawValue |
        CGImageAlphaInfo.noneSkipFirst.rawValue),
      provider: provider,
      decode: nil, shouldInterpolate: false,
      intent: .defaultIntent
    )
  }
}
#endif

private final class BarcodeDecoder {
  private let backend: BarcodeDecodingBackend?

  init() {
#if canImport(CRPTZXBridge)
    backend = Epoch8Backend()
    dlog("barcode backend: epoch8 zxing-cpp (CRPTZXBridge)")
#elseif canImport(ZXingObjC)
    backend = ZXingObjCBackend()
    dlog("barcode backend: ZXingObjC fallback")
#else
    backend = nil
    dlog("barcode backend: NONE")
#endif
  }

  func decode(
    pixelBuffer: CVPixelBuffer,
    x1: Float, y1: Float, x2: Float, y2: Float,
    cls: Int
  ) -> String? {
    return backend?.decode(pixelBuffer: pixelBuffer, x1: x1, y1: y1, x2: x2, y2: y2, cls: cls)
  }
}

// ---------------------------------------------------------------------
enum YoloError: Error { case modelNotFound, allocFailed, badTensor }

final class YoloDetector {
  struct ModelSpec {
    let id: String
    let displayName: String
    let assetName: String
    let classNames: [String]
    let valPrecision: Float
    let valRecall: Float
    let valMap50: Float
    let valMap50_95: Float
    var customFilePath: String? = nil  // non-nil for user-loaded models
  }

  static let builtInModels: [ModelSpec] = [
    ModelSpec(
      id: "multiclass_tail",
      displayName: "yolo26n_320_multiclass_no_mosaic_tail_20260512_073544",
      assetName: "yolo26n_320_multiclass_no_mosaic_tail_20260512_073544_float16.tflite",
      classNames: ["datamatrix", "code128", "pdf417"],
      valPrecision: 0.95583,
      valRecall: 0.95400,
      valMap50: 0.97400,
      valMap50_95: 0.82577),
    ModelSpec(
      id: "latency_auto",
      displayName: "train_latency_yolo26n_320_auto",
      assetName: "train_latency_yolo26n_320_auto_float16.tflite",
      classNames: ["datamatrix", "code128", "pdf417"],
      valPrecision: 0.0,
      valRecall: 0.0,
      valMap50: 0.0,
      valMap50_95: 0.0),
    ModelSpec(
      id: "multiclass_5090",
      displayName: "yolo26n_320_multiclass_5090_v5",
      assetName: "yolo26n_320_multiclass_5090_v5_float16.tflite",
      classNames: ["datamatrix", "code128", "pdf417"],
      valPrecision: 0.95953,
      valRecall: 0.96243,
      valMap50: 0.98025,
      valMap50_95: 0.83291),
  ]

  // User-loaded models (added at runtime via document picker).
  static var customModels: [ModelSpec] = []

  static var allModels: [ModelSpec] { builtInModels + customModels }

  static func spec(for id: String) -> ModelSpec? {
    return allModels.first { $0.id == id }
  }

  private let interpreter: Interpreter
  private let interpreterLock = NSLock()
  let spec: ModelSpec
  private let inputW = 320
  private let inputH = 320

  private enum OutputLayout {
    case end2end(rows: Int, cols: Int)
    case oneToMany(channels: Int, anchors: Int)
    case unknown
  }

  // Reusable buffers.
  private var resizeBuf: [UInt8]              // 320x320 BGRA
  private var inputBuf: [Float32]             // 320x320x3 packed RGB float

  // Output shape.
  private let outRows: Int
  private let outCols: Int
  private let outputLayout: OutputLayout

  init(spec: ModelSpec) throws {
    self.spec = spec

    // For user-loaded models, use the pre-copied file path directly.
    var resolved: String? = spec.customFilePath
    if let custom = resolved, !FileManager.default.fileExists(atPath: custom) {
      dlog("custom model path not found: \(custom)")
      throw YoloError.modelNotFound
    }

    if resolved == nil {
      // Flutter ships assets inside App.framework, NOT under Runner.app/.
      // Use FlutterDartProject.lookupKey(forAsset:) to translate the
      // pubspec asset path -> bundle resource key, then resolve via
      // Bundle.main.path(forResource:ofType:).
      let assetCandidates = [
        "assets/models/\(spec.assetName)",
      ]
      for asset in assetCandidates {
        let key = FlutterDartProject.lookupKey(forAsset: asset)
        if let p = Bundle.main.path(forResource: key, ofType: nil) {
          dlog("model resolved via FlutterDartProject: \(asset) -> key=\(key)")
          resolved = p
          break
        } else {
          dlog("FlutterDartProject lookup miss: asset=\(asset) key=\(key)")
        }
      }

      // Fallback: scan App.framework/flutter_assets directly.
      if resolved == nil {
        let fm = FileManager.default
        let frameworksDir = (Bundle.main.bundlePath as NSString)
          .appendingPathComponent("Frameworks")
        if let frameworks = try? fm.contentsOfDirectory(atPath: frameworksDir) {
          outer: for fw in frameworks where fw.hasSuffix(".framework") {
            for name in [spec.assetName] {
              let candidate = (frameworksDir as NSString)
                .appendingPathComponent(fw)
                .appending("/flutter_assets/assets/models/\(name)")
              if fm.fileExists(atPath: candidate) {
                dlog("model resolved via framework scan: \(candidate)")
                resolved = candidate
                break outer
              }
            }
          }
        }
      }
    } // end if resolved == nil

    guard let path = resolved else {
      // Diagnostic dump of bundle contents.
      dlog("model NOT found. Bundle dump:")
      dlog("  bundlePath=\(Bundle.main.bundlePath)")
      let fm = FileManager.default
      let fwDir = (Bundle.main.bundlePath as NSString).appendingPathComponent("Frameworks")
      if let fws = try? fm.contentsOfDirectory(atPath: fwDir) {
        dlog("  Frameworks/: \(fws)")
        for fw in fws where fw.hasSuffix(".framework") {
          let assetsDir = (fwDir as NSString)
            .appendingPathComponent(fw)
            .appending("/flutter_assets/assets/models")
          let files = (try? fm.contentsOfDirectory(atPath: assetsDir)) ?? []
          dlog("    \(fw)/flutter_assets/assets/models: \(files)")
        }
      }
      throw YoloError.modelNotFound
    }

    var opts = Interpreter.Options()
    opts.threadCount = 2
    dlog("step1: Interpreter(modelPath:) path=\(path)")
    let interp: Interpreter
    do {
      interp = try Interpreter(modelPath: path, options: opts)
    } catch {
      dlog("step1 FAILED: \(error)")
      throw error
    }
    dlog("step2: allocateTensors()")
    do { try interp.allocateTensors() } catch {
      dlog("step2 FAILED: \(error)"); throw error
    }
    self.interpreter = interp
    dlog("step3: inputTensorCount=\(interp.inputTensorCount) outputTensorCount=\(interp.outputTensorCount)")

    let inT: Tensor
    do { inT = try interp.input(at: 0) }
    catch { dlog("step4 FAILED reading input(0): \(error)"); throw error }
    let outT: Tensor
    do { outT = try interp.output(at: 0) }
    catch { dlog("step5 FAILED reading output(0): \(error)"); throw error }

    let oshape = outT.shape.dimensions
    if oshape.count == 3 {
      let d1 = oshape[1]
      let d2 = oshape[2]
      if d2 >= 6 {
        self.outRows = d1
        self.outCols = d2
        self.outputLayout = .end2end(rows: d1, cols: d2)
      } else if d1 >= 5 && d2 > 10 {
        self.outRows = d2
        self.outCols = d1
        self.outputLayout = .oneToMany(channels: d1, anchors: d2)
      } else {
        dlog("UNEXPECTED output shape: \(oshape)")
        self.outRows = 300
        self.outCols = 6
        self.outputLayout = .unknown
      }
    } else {
      dlog("UNEXPECTED output rank/shape: \(oshape)")
      self.outRows = 300
      self.outCols = 6
      self.outputLayout = .unknown
    }

    self.resizeBuf = [UInt8](repeating: 0, count: inputW * inputH * 4)
    self.inputBuf  = [Float32](repeating: 0, count: inputW * inputH * 3)

    dlog("===== YoloDetector init =====")
    dlog("input  shape=\(inT.shape.dimensions) dtype=\(inT.dataType)")
    dlog("output shape=\(oshape) dtype=\(outT.dataType)")
    dlog("rows=\(outRows) cols=\(outCols)")
    switch outputLayout {
    case .end2end(let rows, let cols):
      dlog("output layout=end2end rows=\(rows) cols=\(cols)")
    case .oneToMany(let channels, let anchors):
      dlog("output layout=oneToMany channels=\(channels) anchors=\(anchors)")
    case .unknown:
      dlog("output layout=unknown")
    }
  }

  func startupSummary() -> String {
    let classes = spec.classNames.joined(separator: ",")
    return String(
      format: "model=%@ classes=[%@] valP=%.3f valR=%.3f mAP50=%.3f mAP50-95=%.3f",
      spec.displayName, classes,
      Double(spec.valPrecision), Double(spec.valRecall),
      Double(spec.valMap50), Double(spec.valMap50_95))
  }

  func className(for id: Int) -> String {
    guard id >= 0 && id < spec.classNames.count else { return "cls\(id)" }
    return spec.classNames[id]
  }

  func run(pixelBuffer: CVPixelBuffer, frameId: Int, threshold: Float) -> [[String: Any]] {
    let logThis = (frameId % 30 == 0)
    guard let inputData = preprocess(pixelBuffer, logThis: logThis) else {
      if logThis { dlog("preprocess returned nil") }
      return []
    }
    interpreterLock.lock()
    defer { interpreterLock.unlock() }
    do {
      try interpreter.copy(inputData, toInputAt: 0)
      try interpreter.invoke()
    } catch {
      dlog("invoke error: \(error)")
      return []
    }
    return decode(frameId: frameId, threshold: threshold, logThis: logThis)
  }

  // -----------------------------------------------------------------
  // MARK: Preprocess  -> Float32 RGB normalized [0..1]
  // -----------------------------------------------------------------
  private func preprocess(_ pb: CVPixelBuffer, logThis: Bool) -> Data? {
    CVPixelBufferLockBaseAddress(pb, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }

    let w = CVPixelBufferGetWidth(pb)
    let h = CVPixelBufferGetHeight(pb)
    let stride = CVPixelBufferGetBytesPerRow(pb)
    guard let base = CVPixelBufferGetBaseAddress(pb) else {
      dlog("preprocess: base address nil")
      return nil
    }

    let side = min(w, h)
    let xOff = (w - side) / 2
    let yOff = (h - side) / 2

    var srcBuf = vImage_Buffer(
      data: base.advanced(by: yOff * stride + xOff * 4),
      height: vImagePixelCount(side),
      width: vImagePixelCount(side),
      rowBytes: stride)

    let err: vImage_Error = resizeBuf.withUnsafeMutableBufferPointer { ptr -> vImage_Error in
      var dstBuf = vImage_Buffer(
        data: ptr.baseAddress,
        height: vImagePixelCount(inputH),
        width: vImagePixelCount(inputW),
        rowBytes: inputW * 4)
      return vImageScale_ARGB8888(&srcBuf, &dstBuf, nil,
                                  vImage_Flags(kvImageHighQualityResampling))
    }
    if err != kvImageNoError {
      dlog("preprocess: vImageScale failed err=\(err)")
      return nil
    }

    // BGRA(0..255) -> RGB float32 (0..1).
    let count = inputW * inputH
    var rSum: Int = 0, gSum: Int = 0, bSum: Int = 0
    var rMin: UInt8 = 255, rMax: UInt8 = 0
    let inv: Float = 1.0 / 255.0
    inputBuf.withUnsafeMutableBufferPointer { dstPtr in
      resizeBuf.withUnsafeBufferPointer { srcPtr in
        let src = srcPtr.baseAddress!
        let dst = dstPtr.baseAddress!
        var di = 0
        for i in 0..<count {
          let b = src[i * 4 + 0]
          let g = src[i * 4 + 1]
          let r = src[i * 4 + 2]
          if logThis {
            rSum &+= Int(r); gSum &+= Int(g); bSum &+= Int(b)
            if r < rMin { rMin = r }
            if r > rMax { rMax = r }
          }
          dst[di + 0] = Float(r) * inv
          dst[di + 1] = Float(g) * inv
          dst[di + 2] = Float(b) * inv
          di += 3
        }
      }
    }

    if logThis {
      let n = max(1, count)
      dlog(String(format: "preproc src=%dx%d crop=%d Rmean=%d Gmean=%d Bmean=%d Rrange=[%d..%d]",
                  w, h, side, rSum / n, gSum / n, bSum / n, rMin, rMax))
    }
    return inputBuf.withUnsafeBufferPointer { Data(buffer: $0) }
  }

  // -----------------------------------------------------------------
  // MARK: Decode
  // -----------------------------------------------------------------
  private func iou(_ a: (Float, Float, Float, Float), _ b: (Float, Float, Float, Float)) -> Float {
    let ix1 = max(a.0, b.0)
    let iy1 = max(a.1, b.1)
    let ix2 = min(a.2, b.2)
    let iy2 = min(a.3, b.3)
    let iw = max(ix2 - ix1, 0)
    let ih = max(iy2 - iy1, 0)
    let inter = iw * ih
    let areaA = max(a.2 - a.0, 0) * max(a.3 - a.1, 0)
    let areaB = max(b.2 - b.0, 0) * max(b.3 - b.1, 0)
    let union = areaA + areaB - inter
    return union > 0 ? inter / union : 0
  }

  private func nmsByClass(
    _ boxes: [(x1: Float, y1: Float, x2: Float, y2: Float, conf: Float, cls: Int)],
    iouThreshold: Float,
    maxKeep: Int
  ) -> [(x1: Float, y1: Float, x2: Float, y2: Float, conf: Float, cls: Int)] {
    var grouped: [Int: [(x1: Float, y1: Float, x2: Float, y2: Float, conf: Float, cls: Int)]] = [:]
    for b in boxes {
      grouped[b.cls, default: []].append(b)
    }
    var kept: [(x1: Float, y1: Float, x2: Float, y2: Float, conf: Float, cls: Int)] = []
    for (_, clsBoxes) in grouped {
      let sorted = clsBoxes.sorted { $0.conf > $1.conf }
      var localKeep: [(x1: Float, y1: Float, x2: Float, y2: Float, conf: Float, cls: Int)] = []
      for cand in sorted {
        var suppressed = false
        for k in localKeep {
          if iou((cand.x1, cand.y1, cand.x2, cand.y2), (k.x1, k.y1, k.x2, k.y2)) > iouThreshold {
            suppressed = true
            break
          }
        }
        if !suppressed {
          localKeep.append(cand)
        }
      }
      kept.append(contentsOf: localKeep)
    }
    kept.sort { $0.conf > $1.conf }
    if kept.count > maxKeep {
      return Array(kept.prefix(maxKeep))
    }
    return kept
  }

  private func decode(frameId: Int, threshold: Float, logThis: Bool) -> [[String: Any]] {
    guard let out0 = try? interpreter.output(at: 0) else {
      dlog("decode: output(0) failed")
      return []
    }
    let n = outRows
    let k = outCols
    let total = n * k

    let floats: [Float] = out0.data.withUnsafeBytes { raw -> [Float] in
      let p = raw.bindMemory(to: Float32.self)
      return Array(UnsafeBufferPointer(start: p.baseAddress, count: min(p.count, total)))
    }
    if floats.count < total {
      dlog("decode: short output \(floats.count) < \(total)")
      return []
    }

    var out: [[String: Any]] = []
    out.reserveCapacity(8)
    var topScore: Float = 0
    var topIdx: Int = 0
    var nAboveZero = 0
    var pixelCoordRows = 0
    var normalizedRows = 0
    var droppedGeom = 0

    switch outputLayout {
    case .end2end:
      for i in 0..<n {
        let base = i * k
        let conf = floats[base + 4]
        if conf > 0.001 { nAboveZero += 1 }
        if conf > topScore { topScore = conf; topIdx = i }
        if conf < threshold { continue }
        var x1 = floats[base + 0]
        var y1 = floats[base + 1]
        var x2 = floats[base + 2]
        var y2 = floats[base + 3]
        let cls = Int(floats[base + 5].rounded())
        let label = className(for: cls)

        let coordAbsMax = max(abs(x1), abs(y1), abs(x2), abs(y2))
        if coordAbsMax > 2.0 {
          x1 /= Float(inputW)
          x2 /= Float(inputW)
          y1 /= Float(inputH)
          y2 /= Float(inputH)
          pixelCoordRows += 1
        } else {
          normalizedRows += 1
        }

        x1 = min(max(x1, 0), 1); y1 = min(max(y1, 0), 1)
        x2 = min(max(x2, 0), 1); y2 = min(max(y2, 0), 1)
        if x2 <= x1 || y2 <= y1 {
          droppedGeom += 1
          continue
        }
        out.append([
          "x1": x1, "y1": y1, "x2": x2, "y2": y2,
          "score": conf, "cls": cls, "label": label, "fid": frameId,
        ])
        if out.count >= 50 { break }
      }
    case .oneToMany(let channels, let anchors):
      var candidates: [(x1: Float, y1: Float, x2: Float, y2: Float, conf: Float, cls: Int)] = []
      candidates.reserveCapacity(64)
      for a in 0..<anchors {
        let cx = floats[a]
        let cy = floats[anchors + a]
        let w = floats[anchors * 2 + a]
        let h = floats[anchors * 3 + a]
        var bestCls = 0
        var bestScore: Float = 0
        if channels > 4 {
          for c in 4..<channels {
            let s = floats[anchors * c + a]
            if s > bestScore {
              bestScore = s
              bestCls = c - 4
            }
          }
        }
        if bestScore > 0.001 { nAboveZero += 1 }
        if bestScore > topScore {
          topScore = bestScore
          topIdx = a
        }
        if bestScore < threshold { continue }

        var x1 = cx - w * 0.5
        var y1 = cy - h * 0.5
        var x2 = cx + w * 0.5
        var y2 = cy + h * 0.5
        let coordAbsMax = max(abs(x1), abs(y1), abs(x2), abs(y2))
        if coordAbsMax > 2.0 {
          x1 /= Float(inputW)
          x2 /= Float(inputW)
          y1 /= Float(inputH)
          y2 /= Float(inputH)
          pixelCoordRows += 1
        } else {
          normalizedRows += 1
        }

        x1 = min(max(x1, 0), 1); y1 = min(max(y1, 0), 1)
        x2 = min(max(x2, 0), 1); y2 = min(max(y2, 0), 1)
        if x2 <= x1 || y2 <= y1 {
          droppedGeom += 1
          continue
        }
        candidates.append((x1: x1, y1: y1, x2: x2, y2: y2, conf: bestScore, cls: bestCls))
      }
      let kept = nmsByClass(candidates, iouThreshold: 0.45, maxKeep: 50)
      for kbox in kept {
        out.append([
          "x1": kbox.x1, "y1": kbox.y1, "x2": kbox.x2, "y2": kbox.y2,
          "score": kbox.conf, "cls": kbox.cls,
          "label": className(for: kbox.cls), "fid": frameId,
        ])
      }
    case .unknown:
      dlog("decode: unsupported output layout")
      return []
    }

    if logThis {
      let mode = pixelCoordRows > normalizedRows ? "pixel320" : "norm01"
      dlog(String(format: "decode rows=%d nonZero=%d topScore=%.3f kept=%d droppedGeom=%d mode=%@ (thr=%.2f)",
                  n, nAboveZero, Double(topScore), out.count, droppedGeom, mode,
                  Double(threshold)))
      switch outputLayout {
      case .end2end:
        let b = topIdx * k
        let row: [Float] = (0..<k).map { floats[b + $0] }
        dlog("decode topRow#\(topIdx)=\(row.map { String(format: "%.3f", $0) })")
      case .oneToMany:
        dlog("decode topAnchor#\(topIdx) conf=\(String(format: "%.3f", Double(topScore)))")
      case .unknown:
        break
      }
    }
    return out
  }

  // -----------------------------------------------------------------
  // MARK: Self-test (synthetic checkerboard square)
  // -----------------------------------------------------------------
  func runSelfTest() -> String {
    var inp = [Float32](repeating: 0, count: inputW * inputH * 3)
    var di = 0
    for y in 0..<inputH {
      for x in 0..<inputW {
        let inSquare = (x >= 110 && x < 210 && y >= 110 && y < 210)
        var pix: Float = 0.9
        if inSquare {
          let cellOn = (((x - 110) / 10 + (y - 110) / 10) & 1) == 0
          pix = cellOn ? 0.0 : 0.06
        }
        inp[di + 0] = pix
        inp[di + 1] = pix
        inp[di + 2] = pix
        di += 3
      }
    }
    do {
      interpreterLock.lock()
      defer { interpreterLock.unlock() }
      let data = inp.withUnsafeBufferPointer { Data(buffer: $0) }
      try interpreter.copy(data, toInputAt: 0)
      try interpreter.invoke()
      guard let out0 = try? interpreter.output(at: 0) else { return "no out0" }
      let total = outRows * outCols
      let floats: [Float] = out0.data.withUnsafeBytes { raw -> [Float] in
        let p = raw.bindMemory(to: Float32.self)
        return Array(UnsafeBufferPointer(start: p.baseAddress, count: min(p.count, total)))
      }
      switch outputLayout {
      case .end2end(let rows, let cols):
        var topScore: Float = 0
        var topRow: [Float] = []
        for i in 0..<rows {
          let b = i * cols
          let conf = floats[b + 4]
          if conf > topScore {
            topScore = conf
            topRow = (0..<cols).map { floats[b + $0] }
          }
        }
        let rs = topRow.map { String(format: "%.3f", $0) }
        return "synthDM[end2end] topScore=\(String(format: "%.3f", topScore)) topRow=\(rs)"
      case .oneToMany(let channels, let anchors):
        var topScore: Float = 0
        var topAnchor: Int = 0
        if channels > 4 {
          for a in 0..<anchors {
            var best: Float = 0
            for c in 4..<channels {
              let s = floats[anchors * c + a]
              if s > best { best = s }
            }
            if best > topScore {
              topScore = best
              topAnchor = a
            }
          }
        }
        return "synthDM[oneToMany] topScore=\(String(format: "%.3f", topScore)) topAnchor=\(topAnchor)"
      case .unknown:
        return "self-test: unknown output layout"
      }
    } catch {
      return "self-test error: \(error)"
    }
  }
}

// ---------------------------------------------------------------------
// MARK: - UIDocumentPickerDelegate
// ---------------------------------------------------------------------

extension AppDelegate: UIDocumentPickerDelegate {
  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    guard let url = urls.first else {
      pendingPickResult?(FlutterError(code: "no_file",
                                     message: "No file selected", details: nil))
      pendingPickResult = nil
      return
    }
    // Copy to Documents for persistence (import mode gives a temp URL).
    let docs = FileManager.default.urls(for: .documentDirectory,
                                        in: .userDomainMask).first!
    let destURL = docs.appendingPathComponent(url.lastPathComponent)
    do {
      if FileManager.default.fileExists(atPath: destURL.path) {
        try FileManager.default.removeItem(at: destURL)
      }
      try FileManager.default.copyItem(at: url, to: destURL)
    } catch {
      pendingPickResult?(FlutterError(code: "copy_failed",
                                     message: "\(error)", details: nil))
      pendingPickResult = nil
      return
    }
    let fileName = url.deletingPathExtension().lastPathComponent
    let modelId  = "custom_\(fileName)"
    let customSpec = YoloDetector.ModelSpec(
      id: modelId,
      displayName: fileName,
      assetName: "",
      classNames: ["datamatrix", "code128", "pdf417"],
      valPrecision: 0,
      valRecall: 0,
      valMap50: 0,
      valMap50_95: 0,
      customFilePath: destURL.path)
    YoloDetector.customModels.removeAll { $0.id == modelId }
    YoloDetector.customModels.append(customSpec)
    dlog("custom model registered: id=\(modelId) path=\(destURL.path)")
    loadDetector(modelId: modelId, reason: "custom-pick")
    if detector != nil {
      pendingPickResult?(["id": modelId, "name": fileName])
    } else {
      pendingPickResult?(FlutterError(code: "load_failed",
                                     message: lastDetectorError ?? "load failed",
                                     details: nil))
    }
    pendingPickResult = nil
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    pendingPickResult?(FlutterError(code: "cancelled",
                                   message: "cancelled", details: nil))
    pendingPickResult = nil
  }
}
