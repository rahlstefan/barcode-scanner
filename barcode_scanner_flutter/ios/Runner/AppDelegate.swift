import UIKit
import Flutter
import AVFoundation
import TensorFlowLite
import Accelerate

// =====================================================================
//  DMTX Scanner — native iOS layer
//  - AVFoundation capture (AVCaptureSession + AVCaptureVideoDataOutput)
//  - TensorFlowLiteSwift int8 inference (YOLO26n, 320x320, single class)
//  - Streams normalized detections to Flutter via EventChannel
//  - Hosts camera preview as a Flutter PlatformView
// =====================================================================

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
    GeneratedPluginRegistrant.register(with: self)
    let controller = window?.rootViewController as! FlutterViewController
    let messenger = controller.binaryMessenger

    // 1. Load TFLite model.
    do {
      detector = try YoloDetector()
      NSLog("[DMTX] YOLO int8 model loaded OK")
    } catch {
      NSLog("[DMTX] FAILED to load model: \(error)")
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
    guard let det = detector else { return }
    let dets = det.run(pixelBuffer: pixelBuffer, frameId: frameId,
                       threshold: confidenceThreshold)
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
//  YOLO int8 detector
// ---------------------------------------------------------------------
//
//  Model: best_int8.tflite (YOLO26n, single class "item", 320x320, NMS embedded).
//  Output assumed shape [1, N, 6] = (x1, y1, x2, y2, conf, cls) normalized to 0..1.
//  Robust fallback: also tries [1, 6, N] layout.

enum YoloError: Error { case modelNotFound, allocFailed }

final class YoloDetector {
  private let interpreter: Interpreter
  private let inputW = 320
  private let inputH = 320
  private let inputChannels = 3
  private var resizeBuf = [UInt8](repeating: 0, count: 320 * 320 * 4)
  private var rgbBuf = [UInt8](repeating: 0, count: 320 * 320 * 3)
  // int8 quant params for input tensor.
  private let inScale: Float
  private let inZero: Int

  init() throws {
    guard let path = Bundle.main.path(forResource: "best_int8",
                                      ofType: "tflite",
                                      inDirectory: "flutter_assets/assets/models")
            ?? Bundle.main.path(forResource: "best_int8", ofType: "tflite")
    else {
      throw YoloError.modelNotFound
    }
    var opts = Interpreter.Options()
    opts.threadCount = 2
    let interp = try Interpreter(modelPath: path, options: opts)
    try interp.allocateTensors()
    self.interpreter = interp
    let inT = try interp.input(at: 0)
    if let q = inT.quantizationParameters {
      self.inScale = Float(q.scale)
      self.inZero = q.zeroPoint
    } else {
      self.inScale = 1.0 / 255.0
      self.inZero = 0
    }
    NSLog("[DMTX] input shape=\(inT.shape) dtype=\(inT.dataType) scale=\(inScale) zero=\(inZero)")
    let outCount = interp.outputTensorCount
    NSLog("[DMTX] output tensor count=\(outCount)")
    for i in 0..<outCount {
      if let t = try? interp.output(at: i) {
        NSLog("[DMTX] output[\(i)] shape=\(t.shape) dtype=\(t.dataType)")
      }
    }
  }

  func run(pixelBuffer: CVPixelBuffer, frameId: Int, threshold: Float) -> [[String: Any]] {
    guard let inputData = preprocess(pixelBuffer) else { return [] }
    do {
      try interpreter.copy(inputData, toInputAt: 0)
      try interpreter.invoke()
      return decode(frameId: frameId, threshold: threshold)
    } catch {
      NSLog("[DMTX] invoke error: \(error)")
      return []
    }
  }

  // Center-crop & resize BGRA pixel buffer → 320x320 RGB → int8.
  private func preprocess(_ pb: CVPixelBuffer) -> Data? {
    CVPixelBufferLockBaseAddress(pb, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }

    let w = CVPixelBufferGetWidth(pb)
    let h = CVPixelBufferGetHeight(pb)
    let stride = CVPixelBufferGetBytesPerRow(pb)
    guard let base = CVPixelBufferGetBaseAddress(pb) else { return nil }

    // Center-crop square.
    let side = min(w, h)
    let xOff = (w - side) / 2
    let yOff = (h - side) / 2

    var srcBuf = vImage_Buffer(
      data: base.advanced(by: yOff * stride + xOff * 4),
      height: vImagePixelCount(side),
      width: vImagePixelCount(side),
      rowBytes: stride)

    var dstBuf = resizeBuf.withUnsafeMutableBufferPointer { ptr -> vImage_Buffer in
      vImage_Buffer(data: ptr.baseAddress,
                    height: vImagePixelCount(inputH),
                    width: vImagePixelCount(inputW),
                    rowBytes: inputW * 4)
    }

    let err = vImageScale_ARGB8888(&srcBuf, &dstBuf, nil, vImage_Flags(kvImageHighQualityResampling))
    if err != kvImageNoError { return nil }

    // BGRA → RGB int8 with quantization: q = round(real/scale) + zero,
    // but model expects normalized [0,1] in int8 representation, so:
    //   real = pixel/255.0
    //   q = round(real / scale) + zero
    let scale = inScale
    let zero = inZero
    let invScale = scale > 0 ? (1.0 / scale) : 255.0
    var di = 0
    let resized = resizeBuf
    var rgb = rgbBuf
    let count = inputW * inputH
    for i in 0..<count {
      let b = Float(resized[i * 4 + 0])
      let g = Float(resized[i * 4 + 1])
      let r = Float(resized[i * 4 + 2])
      // YOLO trained on RGB 0..1.
      let qr = Int((r / 255.0) * invScale) + zero
      let qg = Int((g / 255.0) * invScale) + zero
      let qb = Int((b / 255.0) * invScale) + zero
      rgb[di + 0] = UInt8(truncatingIfNeeded: qr)
      rgb[di + 1] = UInt8(truncatingIfNeeded: qg)
      rgb[di + 2] = UInt8(truncatingIfNeeded: qb)
      di += 3
    }
    rgbBuf = rgb
    return Data(rgbBuf)
  }

  private func decode(frameId: Int, threshold: Float) -> [[String: Any]] {
    guard let out0 = try? interpreter.output(at: 0) else { return [] }
    let shape = out0.shape.dimensions
    let qp = out0.quantizationParameters
    let scale: Float = qp.map { Float($0.scale) } ?? 1.0
    let zero: Int = qp?.zeroPoint ?? 0

    // Single-tensor [1, N, 6] or [1, 6, N] layout.
    if shape.count == 3 && (shape[2] == 6 || shape[1] == 6) {
      let n: Int
      let stride: Int
      let strideAttr: Int
      let layoutNxK: Bool
      if shape[2] == 6 {
        n = shape[1]; stride = 6; strideAttr = 1; layoutNxK = true
      } else {
        n = shape[2]; stride = 1; strideAttr = n; layoutNxK = false
      }
      let raw = [UInt8](out0.data)
      // Detect dtype via string description (TFLite 2.14 Swift enum
      // does not expose .int8 publicly on all builds; using `String(describing:)`
      // works for .int8/.uInt8/.float32 alike).
      let dtypeStr = String(describing: out0.dataType)
      let isInt8 = dtypeStr.contains("int8") && !dtypeStr.contains("uInt8") && !dtypeStr.contains("UInt8")
      let isUInt8 = dtypeStr.lowercased().contains("uint8")
      func getF(_ idx: Int) -> Float {
        if isInt8 {
          let v = Int8(bitPattern: raw[idx])
          return (Float(Int(v)) - Float(zero)) * scale
        } else if isUInt8 {
          return (Float(Int(raw[idx])) - Float(zero)) * scale
        } else {
          // float32
          return raw.withUnsafeBytes { buf in
            buf.bindMemory(to: Float32.self)[idx]
          }
        }
      }
      var out: [[String: Any]] = []
      out.reserveCapacity(min(n, 50))
      for i in 0..<n {
        let base = layoutNxK ? i * stride : i
        let getAt: (Int) -> Float = { k in
          getF(layoutNxK ? base + k : i + k * strideAttr)
        }
        let conf = getAt(4)
        if conf < threshold { continue }
        var x1 = getAt(0), y1 = getAt(1), x2 = getAt(2), y2 = getAt(3)
        let cls = Int(getAt(5).rounded())
        // If coords look like pixels (>1.5), normalize by model size.
        if max(x2, y2) > 1.5 {
          x1 /= Float(inputW); x2 /= Float(inputW)
          y1 /= Float(inputH); y2 /= Float(inputH)
        }
        // Clamp
        x1 = min(max(x1, 0), 1); y1 = min(max(y1, 0), 1)
        x2 = min(max(x2, 0), 1); y2 = min(max(y2, 0), 1)
        if x2 <= x1 || y2 <= y1 { continue }
        out.append([
          "x1": x1, "y1": y1, "x2": x2, "y2": y2,
          "score": conf, "cls": cls, "fid": frameId,
        ])
        if out.count >= 50 { break }
      }
      return out
    }

    // Fallback: 4-tensor TFLite Detection_PostProcess layout.
    if interpreter.outputTensorCount >= 4,
       let boxesT = try? interpreter.output(at: 0),
       let classesT = try? interpreter.output(at: 1),
       let scoresT = try? interpreter.output(at: 2),
       let countT = try? interpreter.output(at: 3)
    {
      let boxes = boxesT.data.toFloatArray()
      let classes = classesT.data.toFloatArray()
      let scores = scoresT.data.toFloatArray()
      let count = Int(countT.data.toFloatArray().first ?? 0)
      var out: [[String: Any]] = []
      for i in 0..<min(count, scores.count) {
        let s = scores[i]
        if s < threshold { continue }
        let ymin = boxes[i * 4 + 0]
        let xmin = boxes[i * 4 + 1]
        let ymax = boxes[i * 4 + 2]
        let xmax = boxes[i * 4 + 3]
        out.append([
          "x1": xmin, "y1": ymin, "x2": xmax, "y2": ymax,
          "score": s, "cls": Int(classes[i]), "fid": frameId,
        ])
      }
      return out
    }

    return []
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
