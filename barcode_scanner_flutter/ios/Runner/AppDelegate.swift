import UIKit
import Flutter
import AVFoundation
import TensorFlowLite
import Accelerate

// =====================================================================
//  DMTX Scanner — native iOS layer
//  - AVFoundation capture (AVCaptureSession + AVCaptureVideoDataOutput)
//  - TensorFlowLiteSwift FULL int8 inference
//      model: best_full_integer_quant.tflite
//      input  : int8  [1,320,320,3]  scale=1/255 zero=-128
//      output : int8  [1,300,6]      scale~0.00412 zero=-124  (NMS embedded,
//                                    layout: x1,y1,x2,y2,score,cls normalized)
//  - Streams normalized detections to Flutter via EventChannel
//  - Hosts camera preview as a Flutter PlatformView
// =====================================================================

fileprivate let kLogTag = "[DMTX]"
fileprivate var kFrameLogEvery: Int = 30   // log a summary every N frames

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var detectionsSink: FlutterEventSink?
  private var detector: YoloDetector?
  private var confidenceThreshold: Float = 0.35
  private weak var lastCameraView: CameraPreviewView?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    NSLog("\(kLogTag) ===== AppDelegate.didFinishLaunching =====")
    GeneratedPluginRegistrant.register(with: self)
    let controller = window?.rootViewController as! FlutterViewController
    let messenger = controller.binaryMessenger

    // 1. Load TFLite model.
    do {
      detector = try YoloDetector()
      NSLog("\(kLogTag) YOLO full-int8 model loaded OK")
    } catch {
      NSLog("\(kLogTag) FAILED to load model: \(error)")
    }

    // 2. EventChannel for detections.
    let eventChannel = FlutterEventChannel(
      name: "com.bboxfix/detections", binaryMessenger: messenger)
    eventChannel.setStreamHandler(self)

    // 3. MethodChannel for control.
    let methodChannel = FlutterMethodChannel(
      name: "com.bboxfix/control", binaryMessenger: messenger)
    methodChannel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "setConfidence":
        if let args = call.arguments as? [String: Any],
           let v = args["value"] as? Double {
          self.confidenceThreshold = Float(v)
          result(nil)
        } else { result(FlutterError(code: "args", message: "value required", details: nil)) }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // 4. PlatformView factory for the camera preview.
    let factory = CameraPreviewFactory(messenger: messenger, owner: self)
    self.registrar(forPlugin: "CameraPreviewPlugin")?
      .register(factory, withId: "com.bboxfix/camera_preview")

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Called by the camera view on every frame.
  func handleSampleBuffer(_ pixelBuffer: CVPixelBuffer, frameId: Int) {
    guard let det = detector else {
      if frameId % kFrameLogEvery == 0 {
        NSLog("\(kLogTag) frame=\(frameId) skipped — detector is nil")
      }
      return
    }
    let t0 = CACurrentMediaTime()
    let dets = det.run(pixelBuffer: pixelBuffer, frameId: frameId,
                       threshold: confidenceThreshold)
    let dt = (CACurrentMediaTime() - t0) * 1000.0
    if frameId % kFrameLogEvery == 0 {
      NSLog(String(format: "\(kLogTag) frame=%d dets=%d thr=%.2f infer=%.1fms sink=%@",
                   frameId, dets.count, Double(confidenceThreshold), dt,
                   detectionsSink == nil ? "NIL" : "OK"))
    } else if !dets.isEmpty {
      NSLog(String(format: "\(kLogTag) frame=%d dets=%d top=%.2f infer=%.1fms",
                   frameId, dets.count,
                   Double((dets.first?["score"] as? Float) ?? 0), dt))
    }
    if let sink = detectionsSink {
      DispatchQueue.main.async { sink(dets) }
    }
  }

  func setActiveCameraView(_ v: CameraPreviewView) { lastCameraView = v }
}

extension AppDelegate: FlutterStreamHandler {
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    detectionsSink = events
    return nil
  }
  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    detectionsSink = nil
    return nil
  }
}

// ---------------------------------------------------------------------
//  PlatformView factory & view
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
    session.sessionPreset = .vga640x480 // small input — model is 320x320 anyway

    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                               for: .video, position: .back),
          let input = try? AVCaptureDeviceInput(device: device),
          session.canAddInput(input)
    else {
      NSLog("[DMTX] No camera available")
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
    if let conn = output.connection(with: .video), conn.isVideoOrientationSupported {
      conn.videoOrientation = .portrait
    }
    session.commitConfiguration()

    previewLayer = AVCaptureVideoPreviewLayer(session: session)
    previewLayer.videoGravity = .resizeAspectFill
    previewLayer.frame = container.bounds
    previewLayer.connection?.videoOrientation = .portrait
    container.layer.addSublayer(previewLayer)

    // Auto-resize preview to view bounds.
    container.layer.masksToBounds = true
    NotificationCenter.default.addObserver(
      forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      self?.previewLayer.frame = self?.container.bounds ?? .zero
    }

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      self?.session.startRunning()
    }
  }

  // Frame callback.
  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                     from connection: AVCaptureConnection) {
    guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    frameId &+= 1
    owner?.handleSampleBuffer(pb, frameId: frameId)
    // Keep preview frame in sync with container size.
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      if self.previewLayer.frame != self.container.bounds {
        self.previewLayer.frame = self.container.bounds
      }
    }
  }
}

// ---------------------------------------------------------------------
//  YOLO FULL int8 detector
// ---------------------------------------------------------------------
//
//  Model: best_full_integer_quant.tflite (YOLO26n single class "item",
//         320x320, NMS embedded).
//  Input  : int8  [1,320,320,3]  scale=1/255 zp=-128
//           => quantized = pixel(0..255) - 128  (stored as Int8 bit pattern)
//  Output : int8  [1,300,6]      scale~0.00412 zp=-124
//           layout: x1, y1, x2, y2, score, cls   (normalized to 0..1)
//
//  Verified Python sanity on host: dequant of raw int8 gives values in [0..1]
//  matching expected coords/scores; rows below threshold come back with score=0.

enum YoloError: Error { case modelNotFound, allocFailed, badTensor }

final class YoloDetector {
  private let interpreter: Interpreter
  private let inputW = 320
  private let inputH = 320
  private let inputChannels = 3

  // Reusable buffers.
  private var resizeBuf: [UInt8]              // 320x320 BGRA
  private var inputBuf: [UInt8]               // 320x320x3 packed RGB int8 bit-pattern

  // Quant params.
  private let inScale: Float
  private let inZero: Int
  private let outScale: Float
  private let outZero: Int

  // Cached output shape info.
  private let outRows: Int    // 300
  private let outCols: Int    // 6
  private var frameCounter: Int = 0

  init() throws {
    // Resolve asset path (Flutter copies assets/* under flutter_assets/).
    let candidates: [(String, String?)] = [
      ("best_full_integer_quant", "flutter_assets/assets/models"),
      ("best_full_integer_quant", nil),
      ("best_int8", "flutter_assets/assets/models"),  // legacy fallback
      ("best_int8", nil),
    ]
    var resolved: String? = nil
    for (name, dir) in candidates {
      if let p = Bundle.main.path(forResource: name, ofType: "tflite", inDirectory: dir) {
        NSLog("\(kLogTag) model resolved: \(name).tflite at dir=\(dir ?? "<root>") -> \(p)")
        resolved = p
        break
      }
    }
    guard let path = resolved else {
      NSLog("\(kLogTag) model NOT found in bundle. Listing flutter_assets/assets/models:")
      if let res = Bundle.main.resourcePath {
        let modelsDir = (res as NSString)
          .appendingPathComponent("flutter_assets/assets/models")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: modelsDir)) ?? []
        for f in files { NSLog("\(kLogTag)   - \(f)") }
      }
      throw YoloError.modelNotFound
    }

    var opts = Interpreter.Options()
    opts.threadCount = 2
    let interp = try Interpreter(modelPath: path, options: opts)
    try interp.allocateTensors()
    self.interpreter = interp

    let inT = try interp.input(at: 0)
    let outT = try interp.output(at: 0)

    self.inScale = Float(inT.quantizationParameters?.scale ?? (1.0 / 255.0))
    self.inZero  = inT.quantizationParameters?.zeroPoint ?? -128
    self.outScale = Float(outT.quantizationParameters?.scale ?? 1.0)
    self.outZero  = outT.quantizationParameters?.zeroPoint ?? 0

    // Expected shape: [1, 300, 6]
    let oshape = outT.shape.dimensions
    if oshape.count == 3 {
      self.outRows = oshape[1]
      self.outCols = oshape[2]
    } else {
      NSLog("\(kLogTag) UNEXPECTED output shape: \(oshape)")
      self.outRows = 300
      self.outCols = 6
    }

    self.resizeBuf = [UInt8](repeating: 0, count: inputW * inputH * 4)
    self.inputBuf  = [UInt8](repeating: 0, count: inputW * inputH * 3)

    NSLog("\(kLogTag) ===== YoloDetector initialised =====")
    NSLog("\(kLogTag) input  shape=\(inT.shape.dimensions) dtype=\(inT.dataType) scale=\(inScale) zp=\(inZero)")
    NSLog("\(kLogTag) output shape=\(oshape) dtype=\(outT.dataType) scale=\(outScale) zp=\(outZero)")
    NSLog("\(kLogTag) outTensorCount=\(interp.outputTensorCount) rows=\(outRows) cols=\(outCols)")
  }

  func run(pixelBuffer: CVPixelBuffer, frameId: Int, threshold: Float) -> [[String: Any]] {
    frameCounter &+= 1
    let logThis = (frameCounter % kFrameLogEvery == 0)

    guard let inputData = preprocess(pixelBuffer, logThis: logThis) else {
      if logThis { NSLog("\(kLogTag) preprocess returned nil") }
      return []
    }

    do {
      try interpreter.copy(inputData, toInputAt: 0)
      try interpreter.invoke()
    } catch {
      NSLog("\(kLogTag) invoke error: \(error)")
      return []
    }
    return decode(frameId: frameId, threshold: threshold, logThis: logThis)
  }

  // -----------------------------------------------------------------
  //  Preprocess: BGRA pixel buffer -> 320x320 RGB int8 bit-pattern
  // -----------------------------------------------------------------
  private func preprocess(_ pb: CVPixelBuffer, logThis: Bool) -> Data? {
    CVPixelBufferLockBaseAddress(pb, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }

    let w = CVPixelBufferGetWidth(pb)
    let h = CVPixelBufferGetHeight(pb)
    let stride = CVPixelBufferGetBytesPerRow(pb)
    guard let base = CVPixelBufferGetBaseAddress(pb) else {
      NSLog("\(kLogTag) preprocess: base address nil")
      return nil
    }

    // Center-crop square.
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
      NSLog("\(kLogTag) preprocess: vImageScale failed err=\(err)")
      return nil
    }

    // BGRA(0..255) -> RGB int8 bit-pattern. Quantization is exact:
    //   real = pixel/255
    //   q    = round(real / scale + zp) = round(pixel/255 * 255 + (-128)) = pixel - 128
    // Stored as Int8 bit pattern, which equals (pixel ^ 0x80) for every byte.
    let count = inputW * inputH
    var rMin: UInt8 = 255, rMax: UInt8 = 0
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
            if r < rMin { rMin = r }
            if r > rMax { rMax = r }
          }
          // pixel - 128 (overflow), gives exact int8 bit pattern.
          dst[di + 0] = r &- 128
          dst[di + 1] = g &- 128
          dst[di + 2] = b &- 128
          di += 3
        }
      }
    }

    if logThis {
      NSLog(String(format: "\(kLogTag) preprocess src=%dx%d crop=%d resized=320x320 R range=[%d..%d]",
                   w, h, side, rMin, rMax))
    }
    return Data(inputBuf)
  }

  // -----------------------------------------------------------------
  //  Decode: int8 [1, 300, 6] -> normalized boxes
  // -----------------------------------------------------------------
  private func decode(frameId: Int, threshold: Float, logThis: Bool) -> [[String: Any]] {
    guard let out0 = try? interpreter.output(at: 0) else {
      NSLog("\(kLogTag) decode: output(0) failed")
      return []
    }
    let raw = [UInt8](out0.data)
    let n = outRows
    let k = outCols
    let scale = outScale
    let zp = Float(outZero)

    // Helper: read int8 -> dequantized float.
    @inline(__always) func deq(_ idx: Int) -> Float {
      let v = Int8(bitPattern: raw[idx])
      return (Float(Int(v)) - zp) * scale
    }

    var out: [[String: Any]] = []
    out.reserveCapacity(8)
    var topScore: Float = 0
    var anyAboveZero = 0

    for i in 0..<n {
      let base = i * k
      let conf = deq(base + 4)
      if conf > 0.001 { anyAboveZero += 1 }
      if conf > topScore { topScore = conf }
      if conf < threshold { continue }
      var x1 = deq(base + 0)
      var y1 = deq(base + 1)
      var x2 = deq(base + 2)
      var y2 = deq(base + 3)
      let cls = Int(deq(base + 5).rounded())
      // Already normalized 0..1; clamp.
      x1 = min(max(x1, 0), 1); y1 = min(max(y1, 0), 1)
      x2 = min(max(x2, 0), 1); y2 = min(max(y2, 0), 1)
      if x2 <= x1 || y2 <= y1 { continue }
      out.append([
        "x1": x1, "y1": y1, "x2": x2, "y2": y2,
        "score": conf, "cls": cls, "fid": frameId,
      ])
      if out.count >= 50 { break }
    }

    if logThis {
      NSLog(String(format: "\(kLogTag) decode rows=%d nonZero=%d topScore=%.3f kept=%d (thr=%.2f)",
                   n, anyAboveZero, Double(topScore), out.count, Double(threshold)))
      // Dump first row raw + dequant for diagnostics.
      if raw.count >= k {
        let row0: [Float] = (0..<k).map { deq($0) }
        NSLog("\(kLogTag) decode row[0] dequant=\(row0)")
      }
    }
    return out
  }
}

private extension Data {
  func toFloatArray() -> [Float] {
    return withUnsafeBytes { raw -> [Float] in
      let p = raw.bindMemory(to: Float32.self)
      return Array(p)
    }
  }
}
