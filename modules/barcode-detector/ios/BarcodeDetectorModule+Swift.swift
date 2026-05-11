import ExpoModulesCore
import Vision
import CoreML
import CoreVideo
import CoreImage

/**
 BarcodeDetectorModule - Expo модуль для распознавания кодов через Vision API и TFLite
 */
public class BarcodeDetectorModule: Module {
  private var visionModel: VNCoreMLModel?
  private var modelPath: String?
  private var confidenceThreshold: Float = 0.6
  private var iouThreshold: Float = 0.5
  private var maxDetections: Int = 10
  private var frameCounter = 0
  
  private let processingQueue = DispatchQueue(
    label: "com.barcode.detector.processing",
    qos: .userInitiated,
    attributes: .concurrent
  )
  
  public func definition() -> ModuleDefinition {
    Name("BarcodeDetector")
    
    // Инициализация модуля
    AsyncFunction("initialize") { (config: [String: Any], promise: Promise) in
      DispatchQueue.global(qos: .default).async {
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
          
          // Пытаемся загрузить CoreML модель если путь указан
          if let modelPath = self.modelPath {
            let fileURL = URL(fileURLWithPath: modelPath)
            if FileManager.default.fileExists(atPath: fileURL.path) {
              // В реальности здесь загружалась бы модель
              // try self.visionModel = VNCoreMLModel(for: MLModel(contentsOf: fileURL))
            }
          }
          
          promise.resolve(true)
        } catch {
          promise.reject("INIT_ERROR", error.localizedDescription)
        }
      }
    }
    
    // Обработка видеокадра
    AsyncFunction("processFrame") { (frameData: [String: Any], promise: Promise) in
      self.processingQueue.async {
        do {
          self.frameCounter += 1
          let processingStartTime = Date()
          
          // Получаем информацию о кадре
          guard let width = frameData["width"] as? Int,
                let height = frameData["height"] as? Int else {
            promise.reject("INVALID_FRAME", "Missing frame dimensions")
            return
          }
          
          // Здесь должна быть реальная обработка видеокадра
          // 1. Конвертировать CVPixelBuffer в формат для TFLite
          // 2. Запустить инференс модели
          // 3. Декодировать выходные тензоры в детекции
          
          // Mock результаты для демонстрации
          let mockDetections: [[String: Any]] = [
            // Можно добавить mock детекции для тестирования UI
          ]
          
          let processingTime = Date().timeIntervalSince(processingStartTime) * 1000
          
          let result: [String: Any] = [
            "detections": mockDetections,
            "frameId": self.frameCounter,
            "processingTime": processingTime,
            "width": width,
            "height": height
          ]
          
          promise.resolve(result)
        } catch {
          promise.reject("PROCESS_ERROR", error.localizedDescription)
        }
      }
    }
    
    // Получение информации о модели
    AsyncFunction("getModelInfo") { (promise: Promise) in
      let info: [String: Any] = [
        "name": "YOLO26N-Barcode-Detector",
        "version": "1.0.0",
        "supportedTypes": ["datamatrix", "pdf417", "code128"],
        "inputSize": 640,
        "outputClasses": 3
      ]
      promise.resolve(info)
    }
    
    // Получение статистики обработки
    AsyncFunction("getStats") { (promise: Promise) in
      let stats: [String: Any] = [
        "framesProcessed": self.frameCounter,
        "modelLoaded": self.visionModel != nil || self.modelPath != nil,
        "confidenceThreshold": self.confidenceThreshold,
        "maxDetections": self.maxDetections
      ]
      promise.resolve(stats)
    }
    
    // Очистка ресурсов
    AsyncFunction("release") { (promise: Promise) in
      self.visionModel = nil
      self.modelPath = nil
      self.frameCounter = 0
      promise.resolve(nil)
    }
  }
  
  // MARK: - Helper Methods
  
  /**
   Применяет Non-Maximum Suppression к детекциям
   */
  private func applyNMS(
    detections: [(bbox: CGRect, score: Float, type: Int)],
    threshold: Float
  ) -> [(bbox: CGRect, score: Float, type: Int)] {
    var result: [(bbox: CGRect, score: Float, type: Int)] = []
    var sortedDetections = detections.sorted { $0.score > $1.score }
    
    while !sortedDetections.isEmpty {
      let current = sortedDetections.removeFirst()
      result.append(current)
      
      sortedDetections.removeAll { candidate in
        let iou = self.calculateIOU(current.bbox, candidate.bbox)
        return iou > threshold
      }
    }
    
    return result
  }
  
  /**
   Вычисляет IOU (Intersection Over Union) между двумя bbox
   */
  private func calculateIOU(_ box1: CGRect, _ box2: CGRect) -> Float {
    let intersection = box1.intersection(box2).area
    let union = box1.area + box2.area - intersection
    return union == 0 ? 0 : Float(intersection / union)
  }
}

// MARK: - Extensions

extension CGRect {
  var area: CGFloat {
    return width * height
  }
}
