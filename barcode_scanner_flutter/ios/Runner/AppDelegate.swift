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
//      input  : int8  [1,320,320,3]  scale=1/255 zp=-128
//      output : int8  [1,300,6]      scale~0.00412 zp=-124   NMS embedded
//                                    layout: x1, y1, x2, y2, score, cls
//                                    coords normalized to 0..1
//
//  Logs: NSLog + in-app overlay (Dart side reads `com.bboxfix/logs`).
// =====================================================================

// ---------------------------------------------------------------------
// MARK: - Global logger (NSLog + Flutter EventChannel + ring buffer)
// ---------------------------------------------------------------------

final class DLog {
  static let shared = DLog()
  private let lock = NSLock()
  private var ring: [String] = []
  private let ringMax = 400
  private var sink: FlutterEventSink?

  func attach(sink: @escaping FlutterEventSink) {
    lock.lock()
    self.sink = sink
    let snapshot = ring
    lock.unlock()
    DispatchQueue.main.async {
      for line in snapshot { sink(line) }
    }
  }

  func detach() {
    lock.lock(); defer { lock.unlock() }
    sink = nil
  }

  func log(_ msg: String) {
    let ts = String(format: "%.3f", CACurrentMediaTime())
    let line = "[\(ts)] \(msg)"
    NSLog("[DMTX] %@", line)
    var sinkRef: FlutterEventSink?
    lock.lock()
    ring.append(line)
    if ring.count > ringMax { ring.removeFirst(ring.count - ringMax) }
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
  private var lastDetectorError: String?
  private var confidenceThreshold: Float = 0.25
  private weak var lastCameraView: CameraPreviewView?

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
      case "selfTest":
        if let det = self.detector {
          let res = det.runSelfTest()
          dlog("manual self-test -> \(res)")
          result(res)
        } else {
          let msg = "detector nil; lastError=\(self.lastDetectorError ?? "<none>")"
          dlog("manual self-test -> \(msg)")
          result(msg)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // 4. Load TFLite model (after logs are wired).
    do {
      detector = try YoloDetector()
      dlog("YOLO full-int8 model loaded OK")
      // Run startup self-test on a synthetic pattern (proves inference works).
      DispatchQueue.global(qos: .utility).async { [weak self] in
        if let s = self?.detector?.runSelfTest() { dlog("SELF-TEST: \(s)") }
      }
    } catch {
      lastDetectorError = "\(error)"
      dlog("FAILED to load model: \(error)")
    }

    // 5. PlatformView factory for the camera preview.
    let factory = CameraPreviewFactory(messenger: messenger, owner: self)
    self.registrar(forPlugin: "CameraPreviewPlugin")?
      .register(factory, withId: "com.bboxfix/camera_preview")

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Called by the camera view on every frame (videoQueue).
  func handleSampleBuffer(_ pixelBuffer: CVPixelBuffer, frameId: Int) {
    guard let det = detector else {
      if frameId % 60 == 0 {
        dlog("frame=\(frameId) detector is nil; lastError=\(lastDetectorError ?? "<none>")")
      }
      return
    }
    let t0 = CACurrentMediaTime()
    let dets = det.run(pixelBuffer: pixelBuffer, frameId: frameId,
                       threshold: confidenceThreshold)
    let dt = (CACurrentMediaTime() - t0) * 1000.0
    if frameId % 30 == 0 {
      dlog(String(format: "frame=%d dets=%d thr=%.2f infer=%.1fms sink=%@",
                  frameId, dets.count, Double(confidenceThreshold), dt,
                  detectionsSink == nil ? "NIL" : "OK"))
    } else if !dets.isEmpty {
      dlog(String(format: "frame=%d dets=%d top=%.2f infer=%.1fms",
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
// MARK: - YOLO FULL int8 detector
// ---------------------------------------------------------------------

enum YoloError: Error { case modelNotFound, allocFailed, badTensor }

final class YoloDetector {
  private let interpreter: Interpreter
  private let inputW = 320
  private let inputH = 320

  // Reusable buffers.
  private var resizeBuf: [UInt8]              // 320x320 BGRA
  private var inputBuf: [UInt8]               // 320x320x3 packed RGB int8 bit-pattern

  // Quant params.
  private let inScale: Float
  private let inZero: Int
  private let outScale: Float
  private let outZero: Int

  // Output shape.
  private let outRows: Int    // 300
  private let outCols: Int    // 6

  init() throws {
    // Flutter ships assets inside App.framework, NOT under Runner.app/.
    // Use FlutterDartProject.lookupKey(forAsset:) to translate the
    // pubspec asset path -> bundle resource key, then resolve via
    // Bundle.main.path(forResource:ofType:).
    let assetCandidates = [
      "assets/models/best_full_integer_quant.tflite",
      "assets/models/best_int8.tflite",
    ]
    var resolved: String? = nil
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

    // Fallback 1: scan App.framework/flutter_assets directly.
    if resolved == nil {
      let fm = FileManager.default
      let frameworksDir = (Bundle.main.bundlePath as NSString)
        .appendingPathComponent("Frameworks")
      if let frameworks = try? fm.contentsOfDirectory(atPath: frameworksDir) {
        for fw in frameworks where fw.hasSuffix(".framework") {
          let candidate = (frameworksDir as NSString)
            .appendingPathComponent(fw)
            .appending("/flutter_assets/assets/models/best_full_integer_quant.tflite")
          if fm.fileExists(atPath: candidate) {
            dlog("model resolved via framework scan: \(candidate)")
            resolved = candidate
            break
          }
        }
      }
    }

    // Fallback 2: legacy Bundle.main.path(forResource:inDirectory:).
    if resolved == nil {
      let legacy: [(String, String?)] = [
        ("best_full_integer_quant", "flutter_assets/assets/models"),
        ("best_full_integer_quant", nil),
      ]
      for (name, dir) in legacy {
        if let p = Bundle.main.path(forResource: name, ofType: "tflite", inDirectory: dir) {
          dlog("model resolved via legacy lookup: \(p)")
          resolved = p
          break
        }
      }
    }

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
    let interp = try Interpreter(modelPath: path, options: opts)
    try interp.allocateTensors()
    self.interpreter = interp

    let inT = try interp.input(at: 0)
    let outT = try interp.output(at: 0)

    self.inScale = Float(inT.quantizationParameters?.scale ?? (1.0 / 255.0))
    self.inZero  = inT.quantizationParameters?.zeroPoint ?? -128
    self.outScale = Float(outT.quantizationParameters?.scale ?? 1.0)
    self.outZero  = outT.quantizationParameters?.zeroPoint ?? 0

    let oshape = outT.shape.dimensions
    if oshape.count == 3 {
      self.outRows = oshape[1]
      self.outCols = oshape[2]
    } else {
      dlog("UNEXPECTED output shape: \(oshape)")
      self.outRows = 300
      self.outCols = 6
    }

    self.resizeBuf = [UInt8](repeating: 0, count: inputW * inputH * 4)
    self.inputBuf  = [UInt8](repeating: 0, count: inputW * inputH * 3)

    dlog("===== YoloDetector init =====")
    dlog("input  shape=\(inT.shape.dimensions) dtype=\(inT.dataType) scale=\(inScale) zp=\(inZero)")
    dlog("output shape=\(oshape) dtype=\(outT.dataType) scale=\(outScale) zp=\(outZero)")
    dlog("outTensorCount=\(interp.outputTensorCount) rows=\(outRows) cols=\(outCols)")
  }

  func run(pixelBuffer: CVPixelBuffer, frameId: Int, threshold: Float) -> [[String: Any]] {
    let logThis = (frameId % 30 == 0)
    guard let inputData = preprocess(pixelBuffer, logThis: logThis) else {
      if logThis { dlog("preprocess returned nil") }
      return []
    }
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
  // MARK: Preprocess
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

    // BGRA(0..255) -> RGB int8 bit-pattern.
    // Quantization is exact: real = pixel/255, q = real/scale + zp = pixel - 128.
    // Stored as Int8 (UInt8 bit pattern): pixel - 128 with overflow.
    let count = inputW * inputH
    var rSum: Int = 0, gSum: Int = 0, bSum: Int = 0
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
            rSum &+= Int(r); gSum &+= Int(g); bSum &+= Int(b)
            if r < rMin { rMin = r }
            if r > rMax { rMax = r }
          }
          dst[di + 0] = r &- 128
          dst[di + 1] = g &- 128
          dst[di + 2] = b &- 128
          di += 3
        }
      }
    }

    if logThis {
      let n = max(1, count)
      dlog(String(format: "preproc src=%dx%d crop=%d Rmean=%d Gmean=%d Bmean=%d Rrange=[%d..%d]",
                  w, h, side, rSum / n, gSum / n, bSum / n, rMin, rMax))
    }
    return Data(inputBuf)
  }

  // -----------------------------------------------------------------
  // MARK: Decode
  // -----------------------------------------------------------------
  private func decode(frameId: Int, threshold: Float, logThis: Bool) -> [[String: Any]] {
    guard let out0 = try? interpreter.output(at: 0) else {
      dlog("decode: output(0) failed")
      return []
    }
    let raw = [UInt8](out0.data)
    let n = outRows
    let k = outCols
    let scale = outScale
    let zp = Float(outZero)

    @inline(__always) func deq(_ idx: Int) -> Float {
      let v = Int8(bitPattern: raw[idx])
      return (Float(Int(v)) - zp) * scale
    }

    var out: [[String: Any]] = []
    out.reserveCapacity(8)
    var topScore: Float = 0
    var topIdx: Int = 0
    var nAboveZero = 0

    for i in 0..<n {
      let base = i * k
      let conf = deq(base + 4)
      if conf > 0.001 { nAboveZero += 1 }
      if conf > topScore { topScore = conf; topIdx = i }
      if conf < threshold { continue }
      var x1 = deq(base + 0)
      var y1 = deq(base + 1)
      var x2 = deq(base + 2)
      var y2 = deq(base + 3)
      let cls = Int(deq(base + 5).rounded())
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
      let b = topIdx * k
      let row: [Float] = (0..<k).map { deq(b + $0) }
      dlog(String(format: "decode rows=%d nonZero=%d topScore=%.3f kept=%d (thr=%.2f)",
                  n, nAboveZero, Double(topScore), out.count, Double(threshold)))
      dlog("decode topRow#\(topIdx)=\(row.map { String(format: "%.3f", $0) })")
    }
    return out
  }

  // -----------------------------------------------------------------
  // MARK: Self-test (synthetic checkerboard square)
  // -----------------------------------------------------------------
  func runSelfTest() -> String {
    var inp = [UInt8](repeating: 0, count: inputW * inputH * 3)
    var di = 0
    for y in 0..<inputH {
      for x in 0..<inputW {
        let inSquare = (x >= 110 && x < 210 && y >= 110 && y < 210)
        let bg: UInt8 = 230
        var pix: UInt8
        if inSquare {
          let cellOn = (((x - 110) / 10 + (y - 110) / 10) & 1) == 0
          pix = cellOn ? 0 : 16
        } else {
          pix = bg
        }
        // Already RGB (gray, all channels equal). Quant = pix - 128.
        let q = pix &- 128
        inp[di + 0] = q
        inp[di + 1] = q
        inp[di + 2] = q
        di += 3
      }
    }
    do {
      try interpreter.copy(Data(inp), toInputAt: 0)
      try interpreter.invoke()
      guard let out0 = try? interpreter.output(at: 0) else { return "no out0" }
      let raw = [UInt8](out0.data)
      let zp = Float(outZero); let sc = outScale
      var topScore: Float = 0
      var topRow: [Float] = []
      for i in 0..<outRows {
        let b = i * outCols
        let conf = (Float(Int(Int8(bitPattern: raw[b + 4]))) - zp) * sc
        if conf > topScore {
          topScore = conf
          topRow = (0..<outCols).map { k in
            (Float(Int(Int8(bitPattern: raw[b + k]))) - zp) * sc
          }
        }
      }
      let rs = topRow.map { String(format: "%.3f", $0) }
      return "synthDM topScore=\(String(format: "%.3f", topScore)) topRow=\(rs)"
    } catch {
      return "self-test error: \(error)"
    }
  }
}
