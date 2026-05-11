# Integration Guide: TFLite + Vision API

## Полная интеграция распознавания кодов

### 1. Установка зависимостей TensorFlow Lite

Обновите `ios/Podfile`:

```ruby
target 'BarcodeScanner' do
  # Существующие зависимости Expo...
  
  # TensorFlow Lite для iOS
  pod 'TensorFlowLiteSwift', '~> 2.13.0'
  pod 'TensorFlowLiteMetalDelegate', '~> 2.13.0'
  
  # Дополнительно (опционально)
  pod 'TensorFlowLiteCoreML', '~> 2.13.0'
end

post_install do |installer|
  # Стандартная конфигурация
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
  end
end
```

Затем:
```bash
cd ios && pod install && cd ..
```

### 2. Native Code: Полная реализация TFLiteInterpreter

**File:** `modules/barcode-detector/ios/TFLiteInterpreter.swift`

```swift
import TensorFlowLite
import CoreVideo
import Accelerate

class TFLiteInterpreter {
  private var interpreter: Interpreter?
  private var inputTensor: Tensor?
  private var outputTensors: [Tensor]?
  
  private let queue = DispatchQueue(
    label: "com.barcode.tflite",
    qos: .userInitiated
  )
  
  let modelPath: String
  
  init(modelPath: String) {
    self.modelPath = modelPath
  }
  
  /**
   Загружает модель в памяти
   */
  func load() throws {
    try queue.sync {
      var options = Interpreter.Options()
      options.threads = 2
      
      // Используем Metal делегат для ускорения на GPU
      let metalDelegate = MetalDelegate()
      options.addDelegate(metalDelegate)
      
      interpreter = try Interpreter(
        modelPath: modelPath,
        options: options
      )
      
      try interpreter?.allocateTensors()
      
      inputTensor = try interpreter?.input(at: 0)
      outputTensors = []
      
      // Собираем все выходные тензоры
      let outputCount = try interpreter?.outputTensorCount ?? 0
      for i in 0..<outputCount {
        if let outputTensor = try interpreter?.output(at: i) {
          outputTensors?.append(outputTensor)
        }
      }
    }
  }
  
  /**
   Запускает инференс
   */
  func predict(pixelBuffer: CVPixelBuffer) throws -> InferenceResult {
    guard let interpreter = interpreter else {
      throw NSError(domain: "TFLiteInterpreter", code: 1)
    }
    
    return try queue.sync {
      // 1. Конвертируем CVPixelBuffer в УМ (UInt8)
      let inputData = try pixelBufferToData(pixelBuffer)
      
      // 2. Копируем данные в input тензор
      try interpreter.copy(inputData, toInputAt: 0)
      
      // 3. Запускаем инференс
      try interpreter.invoke()
      
      // 4. Читаем выходные тензоры
      guard let outputTensor = try interpreter.output(at: 0) else {
        throw NSError(domain: "TFLiteInterpreter", code: 2)
      }
      
      let outputData = outputTensor.data
      let detections = try parseDetections(from: outputData)
      
      return InferenceResult(
        detections: detections,
        processingTime: 0
      )
    }
  }
  
  /**
   Конвертирует CVPixelBuffer в Data для модели
   */
  private func pixelBufferToData(_ pixelBuffer: CVPixelBuffer) throws -> Data {
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer {
      CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
    }
    
    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
      throw NSError(domain: "PixelBuffer", code: 1)
    }
    
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    
    // Копируем данные
    var data = Data()
    for row in 0..<height {
      let rowPointer = baseAddress.advanced(by: row * bytesPerRow)
      data.append(
        UnsafeRawBufferPointer(
          start: rowPointer,
          count: width * 4  // BGRA format
        )
      )
    }
    
    return data
  }
  
  /**
   Декодирует выходные тензоры в детекции
   */
  private func parseDetections(from data: Data) throws -> [DetectionData] {
    // YOLO26N выдает: [batch, 25200, 85] для COCO
    // или [batch, 25200, 88] для custom с 3 классами
    
    // Структура выходного тензора:
    // - первые 4 значения: x, y, w, h (координаты)
    // - 5-е значение: objectness (вероятность объекта)
    // - остальные: class probabilities
    
    var detections: [DetectionData] = []
    let pointer = data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
      bytes.baseAddress?.assumingMemoryBound(to: Float32.self)
    }
    
    guard let pointer = pointer else { return detections }
    
    let numDetections = 25200 // YOLO27-N по умолчанию
    let numClasses = 3 // datamatrix, pdf417, code128
    let classStart = 5 // После x, y, w, h, objectness
    
    for i in 0..<numDetections {
      let baseIdx = i * (classStart + numClasses)
      
      // Проверяем objectness score
      let objectness = pointer[baseIdx + 4]
      guard objectness > 0.3 else { continue } // Фильтруем низкие scores
      
      // Получаем координаты
      let cx = pointer[baseIdx]
      let cy = pointer[baseIdx + 1]
      let w = pointer[baseIdx + 2]
      let h = pointer[baseIdx + 3]
      
      // Получаем класс с максимальной вероятностью
      var maxClassScore: Float = 0
      var bestClassIdx = 0
      
      for classIdx in 0..<numClasses {
        let classScore = pointer[baseIdx + classStart + classIdx]
        if classScore > maxClassScore {
          maxClassScore = classScore
          bestClassIdx = classIdx
        }
      }
      
      let confidence = objectness * maxClassScore
      guard confidence > 0.4 else { continue }
      
      // Конвертируем в реальные координаты
      let x = cx - w / 2
      let y = cy - h / 2
      
      let barcodeType = getBarcodeType(classIdx: bestClassIdx)
      
      let detection = DetectionData(
        id: UUID().uuidString,
        type: barcodeType,
        rawCode: "", // Будет заполнено Vision API
        confidence: confidence,
        bbox: CGRect(x: CGFloat(x), y: CGFloat(y), 
                     width: CGFloat(w), height: CGFloat(h)),
        timestamp: Date().timeIntervalSince1970,
        frameGeneration: 0
      )
      
      detections.append(detection)
    }
    
    // Применяем NMS (Non-Maximum Suppression)
    return applyNMS(detections, threshold: 0.5)
  }
  
  /**
   Применяет NMS к детекциям
   */
  private func applyNMS(_ detections: [DetectionData], threshold: Float) -> [DetectionData] {
    var result: [DetectionData] = []
    var sorted = detections.sorted { $0.confidence > $1.confidence }
    
    while !sorted.isEmpty {
      let current = sorted.removeFirst()
      result.append(current)
      
      sorted.removeAll { candidate in
        let iou = calculateIOU(current.bbox, candidate.bbox)
        return iou > threshold
      }
    }
    
    return result
  }
  
  private func calculateIOU(_ box1: CGRect, _ box2: CGRect) -> Float {
    let intersection = box1.intersection(box2).area
    let union = box1.area + box2.area - intersection
    return union == 0 ? 0 : Float(intersection / union)
  }
  
  private func getBarcodeType(classIdx: Int) -> BarcodeType {
    switch classIdx {
    case 0: return .datamatrix
    case 1: return .pdf417
    case 2: return .code128
    default: return .datamatrix
    }
  }
}

struct InferenceResult {
  let detections: [DetectionData]
  let processingTime: TimeInterval
}

extension CGRect {
  var area: CGFloat {
    return width * height
  }
}
```

### 3. Интеграция с Vision API для декодирования

**File:** `modules/barcode-detector/ios/VisionIntegration.swift`

```swift
import Vision
import CoreImage

class VisionBarcodeDecoder {
  private let queue = DispatchQueue(
    label: "com.barcode.vision",
    qos: .userInitiated
  )
  
  /**
   Декодирует коды в регионе интереса используя Vision API
   */
  func decodeBarcode(
    pixelBuffer: CVPixelBuffer,
    region: CGRect,
    completion: @escaping ([VNBarcodeObservation]?) -> Void
  ) {
    queue.async {
      let requestHandler = VNImageRequestHandler(
        cvPixelBuffer: pixelBuffer,
        orientation: .up
      )
      
      let request = VNDetectBarcodesRequest { request, error in
        if let error = error {
          print("Vision error: \(error)")
          completion(nil)
          return
        }
        
        let observations = request.results as? [VNBarcodeObservation]
        let filtered = observations?.filter { observation in
          observation.boundingBox.intersects(region)
        }
        
        completion(filtered)
      }
      
      // Поддерживаемые типы кодов
      request.symbologies = [
        .datamatrix,
        .pdf417,
        .code128
      ]
      
      do {
        try requestHandler.perform([request])
      } catch {
        print("Vision request error: \(error)")
        completion(nil)
      }
    }
  }
}
```

### 4. Объединение: TFLite + Vision в BarcodeDetectorModule

```swift
// В BarcodeDetectorModule.swift

class BarcodeDetectorModule: Module {
  private var tfliteInterpreter: TFLiteInterpreter?
  private var visionDecoder: VisionBarcodeDecoder?
  
  AsyncFunction("processFrame") { (frameData: [String: Any], promise: Promise) in
    guard let pixelBuffer = frameData["pixelBuffer"] as? CVPixelBuffer else {
      promise.reject("INVALID_FRAME", "No pixel buffer")
      return
    }
    
    // 1. TFLite детекция
    do {
      let inferenceResult = try self.tfliteInterpreter?.predict(
        pixelBuffer: pixelBuffer
      )
      
      var detections = inferenceResult?.detections ?? []
      
      // 2. Vision API декодирование для каждой детекции
      let dispatchGroup = DispatchGroup()
      var finalDetections: [DetectionData] = []
      
      for detection in detections {
        dispatchGroup.enter()
        
        self.visionDecoder?.decodeBarcode(
          pixelBuffer: pixelBuffer,
          region: detection.bbox
        ) { observations in
          if let observation = observations?.first {
            // Обновляем детекцию с декодированным кодом
            var updated = detection
            updated.rawCode = observation.payloadStringValue ?? ""
            finalDetections.append(updated)
          }
          dispatchGroup.leave()
        }
      }
      
      dispatchGroup.notify(queue: .main) {
        let result: [String: Any] = [
          "detections": finalDetections.map { $0.toDictionary() },
          "frameId": frameData["frameId"] ?? 0,
          "processingTime": 0
        ]
        promise.resolve(result)
      }
      
    } catch {
      promise.reject("INFERENCE_ERROR", error.localizedDescription)
    }
  }
}
```

## Тестирование интеграции

```bash
# 1. Подготовьте модели
./scripts/prepare-models.sh /path/to/candidate3_balanced_adamw_musgd_phase1_v2/weights

# 2. Установите зависимости
npm install

# 3. Prebuild
npm run prebuild

# 4. Запустите на устройстве
npm run ios
```

## Оптимизация производительности

### GPU Acceleration (Metal)
- ✅ Уже включено в TFLite Metal Delegate
- ~3x ускорение по сравнению с CPU

### Quantization
- Используйте `best_full_integer_quant.tflite`
- ~10x ускорение + сокращение памяти

### Frame Skipping
- Обрабатывайте каждый 2-3-й кадр
- Сохраняйте гладкость через temporal buffer

## Troubleshooting

### "Model not found"
```bash
# Проверьте что модель скопирована
ls -la assets/models/
```

### "TensorFlow Lite not found"
```bash
# Переустановите pods
cd ios && rm -rf Pods && pod install && cd ..
```

### Низкая производительность
- Используйте Metal delegate
- Оптимизируйте размер входного изображения
- Включите skip frames в config
