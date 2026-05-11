import ExpoModulesCore
import Vision
import CoreML

public class BarcodeDetectorModule: Module {
  private var visionModel: VNCoreMLModel?
  private var modelPath: String?
  private var confidenceThreshold: Float = 0.6
  private var iouThreshold: Float = 0.5
  private var maxDetections: Int = 10
  
  private let queue = DispatchQueue(label: "com.barcode.detector.queue", qos: .userInitiated)
  
  public func definition() -> ModuleDefinition {
    Name("BarcodeDetector")
    
    AsyncFunction("initialize") { (config: [String: Any], promise: Promise) in
      self.queue.async {
        do {
          if let modelPath = config["modelPath"] as? String {
            self.modelPath = modelPath
          }
          
          if let threshold = config["confidenceThreshold"] as? Float {
            self.confidenceThreshold = threshold
          }
          
          if let iouThreshold = config["iouThreshold"] as? Float {
            self.iouThreshold = iouThreshold
          }
          
          if let maxDetections = config["maxDetections"] as? Int {
            self.maxDetections = maxDetections
          }
          
          // Load Core ML model (we'll use a custom TFLite interpreter)
          promise.resolve(true)
        } catch {
          promise.reject("MODEL_LOAD_ERROR", error.localizedDescription)
        }
      }
    }
    
    AsyncFunction("processFrame") { (frameData: [String: Any], promise: Promise) in
      self.queue.async {
        do {
          // Frame processing will be implemented here
          // For now, return empty detections as placeholder
          let result: [String: Any] = [
            "detections": [],
            "frameId": frameData["frameId"] ?? 0,
            "processingTime": 0
          ]
          promise.resolve(result)
        } catch {
          promise.reject("FRAME_PROCESS_ERROR", error.localizedDescription)
        }
      }
    }
    
    AsyncFunction("getModelInfo") { (promise: Promise) in
      let info: [String: String] = [
        "name": "YOLO26N-Barcode",
        "version": "1.0.0"
      ]
      promise.resolve(info)
    }
    
    AsyncFunction("release") { (promise: Promise) in
      self.visionModel = nil
      self.modelPath = nil
      promise.resolve(nil)
    }
  }
}
