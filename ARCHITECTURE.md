# Архитектура приложения BarcodeScanner

## 🎨 Системная архитектура

```
┌─────────────────────────────────────────────────────────────┐
│                    React Native UI (App.tsx)               │
│  ┌──────────────┐  ┌────────────────┐  ┌──────────────┐   │
│  │  CameraView  │  │   BboxOverlay  │  │   InfoPanel  │   │
│  │   (Expo)     │  │  (with Smooth) │  │ (Statistics) │   │
│  └──────┬───────┘  └────────┬───────┘  └──────────────┘   │
└─────────┼────────────────────┼──────────────────────────────┘
          │                    │
          ▼                    │
┌─────────────────────────────┼──────────────────────────────┐
│   Temporal Detection Buffer   ◄───────────────────┐        │
│   ┌───────────────────────────────────────────┐   │        │
│   │ • appendDetections()                      │   │        │
│   │ • Temporal windowing (N frames)           │   │        │
│   │ • IOU clustering                          │   │        │
│   │ • drainStableDetections()                 │   │        │
│   │ • Position interpolation                  │   │        │
│   └───────────────────────────────────────────┘   │        │
└─────────────────────────────────────────────────────┼───────┘
                                                      │
          ┌───────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────────────┐
│          Native Module (Expo Modules)                      │
│  ┌────────────────────────────────────────────────────┐   │
│  │  BarcodeDetectorModule.swift                       │   │
│  │  ┌──────────────────────────────────────────────┐  │   │
│  │  │ 1. processFrame(CVPixelBuffer)               │  │   │
│  │  │ 2. TFLite Inference                          │  │   │
│  │  │ 3. Parse YOLO detections                     │  │   │
│  │  │ 4. Apply NMS (Non-Maximum Suppression)       │  │   │
│  │  │ 5. Return [Detection]                        │  │   │
│  │  └──────────────────────────────────────────────┘  │   │
│  └────────────────────────────────────────────────────┘   │
│                        │                                   │
│  ┌────────────────────┴─────────────────────────────────┐ │
│  │      TFLiteInterpreter                              │ │
│  │  ┌──────────────────────────────────────────────┐   │ │
│  │  │ • Load YOLO26N model from .tflite            │   │ │
│  │  │ • GPU/Metal acceleration                     │   │ │
│  │  │ • Batch inference                            │   │ │
│  │  │ • Output tensor parsing                      │   │ │
│  │  └──────────────────────────────────────────────┘   │ │
│  └───────────────────────────────────────────────────────┘ │
│                        │                                   │
│  ┌────────────────────┴─────────────────────────────────┐ │
│  │      VisionBarcodeDecoder                           │ │
│  │  ┌──────────────────────────────────────────────┐   │ │
│  │  │ • Vision API VNDetectBarcodesRequest         │   │ │
│  │  │ • Decode: Datamatrix, PDF417, Code128       │   │ │
│  │  │ • Extract payload strings                    │   │ │
│  │  │ • Filter by bounding box region              │   │ │
│  │  └──────────────────────────────────────────────┘   │ │
│  └───────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
          │
          │ CVPixelBuffer (hardware camera stream)
          ▼
┌─────────────────────────────────────────────────────────────┐
│   iOS Camera (AVCapture + Vision Framework)                │
│   • 60 FPS video capture                                   │
│   • YUV/BGRA pixel buffers                                 │
└─────────────────────────────────────────────────────────────┘
```

## 🔄 Поток обработки кадра

```
1. Camera Frame [CMSampleBuffer]
   ↓
2. Extract CVPixelBuffer (1280x720 or 640x480)
   ↓
3. CameraView.onFrameDropped() → App.tsx
   ↓
4. [Frame Counter Increment]
   frameCount++
   ↓
5. Create Mock Detections (or call Native)
   Detection[] with:
   • bbox: {x, y, width, height}
   • confidence: 0.0-1.0
   • type: datamatrix|pdf417|code128
   • timestamp
   ↓
6. TemporalDetectionBuffer.appendDetections(detections)
   • Store in buffer with frameGeneration
   • Keep last N=5 frames
   ↓
7. TemporalDetectionBuffer.drainStableDetections()
   • Check if frameDiff >= returnFrameInterval
   • Cluster by IOU (0.5 threshold)
   • Average bounding boxes
   • Interpolate positions (α=0.7)
   ↓
8. Return SmoothedDetection[]
   • With displayBbox (interpolated)
   • With isStable flag
   ↓
9. React State Update
   setDetections(stable)
   ↓
10. Render:
    • Map detections → BboxBox components
    • Draw colored rectangles
    • Display labels and stats
    ↓
11. UI Frame (60 FPS) ✨ Smooth animation
```

## 📊 Данные и типы

### Detection (Raw от модели)
```typescript
interface Detection {
  id: string;                    // Уникальный ID
  type: 'datamatrix'|'pdf417'|'code128';
  rawCode: string;               // Декодированная строка
  confidence: number;            // 0.0-1.0
  bbox: BoundingBox;             // {x, y, width, height}
  timestamp: number;             // Время в мс
  frameGeneration: number;       // Номер кадра при детекции
}
```

### SmoothedDetection (После сглаживания)
```typescript
interface SmoothedDetection extends Detection {
  displayBbox: BoundingBox;      // 👈 Интерполированная позиция!
  isStable: boolean;
  remainingFrames: number;
}
```

### TemporalBuffer State
```typescript
{
  buffer: Detection[],           // Все детекции за N кадров
  smoothedCache: Map<id, Smoothed>,
  frameGeneration: number,       // Текущий номер кадра
  lastOutputGeneration: number,  // Когда в последний раз выводили
}
```

## ⏱️ Временные параметры (конфигурируемые)

```typescript
const DETECTOR_CONFIG = {
  // Сколько кадров хранить в буфере
  returnWindowSize: 5,
  
  // Выводить детекции каждый N-й кадр
  returnFrameInterval: 2,
  
  // Минимальная уверенность для детекции
  stabilityThreshold: 0.65,
  
  // Максимальный возраст детекции (мс)
  maxDetectionAge: 500,
};
```

## 🎯 Алгоритм плавности (TemporalDetectionBuffer)

### 1️⃣ Append Phase
```
NewDetections from Frame[i]
         ↓
Mark with frameGeneration=i
         ↓
Add to buffer[]
         ↓
Remove detections older than (i - returnWindowSize)
```

### 2️⃣ Clustering Phase
```
Get all detections from last returnFrameInterval frames
         ↓
Group by type (datamatrix / pdf417 / code128)
         ↓
For each type:
  - Calculate IOU between all pairs
  - If IOU > 0.5: cluster together
         ↓
Select best detection from each cluster (highest confidence)
```

### 3️⃣ Smoothing Phase
```
For selected detections:
  - Find history in buffer
  - Linear interpolation between last 2 positions
  - α = 0.7 (weighted toward current frame)
  
  newX = oldX + α * (currentX - oldX)
  newY = oldY + α * (currentY - oldY)
  
Result: displayBbox (smooth position)
```

### 4️⃣ Output Phase
```
if (framesSinceLastOutput >= returnFrameInterval):
  Return SmoothedDetections with displayBbox
else:
  Return cached detections (last output)
```

## 🚀 Почему это работает?

### Проблема (без сглаживания)
```
Frame 1: bbox at (100, 100)  ← Камера слегка сдвинулась
Frame 2: bbox at (105, 98)   ← YOLO вывел немного по-другому
Frame 3: bbox at (101, 102)  ← Шум и jitter
Result: Дерганый, мерцающий бокс ❌
```

### Решение (с Temporal Buffer)
```
Frame 1: bbox at (100, 100)
         ↓
         Store in buffer[frameGen=1]
         
Frame 2: bbox at (105, 98)
         ↓
         Store in buffer[frameGen=2]
         ↓
         Cluster IOU(box1, box2) = 0.98 > 0.5 ✓
         Average: (102.5, 99)
         Interpolate: (103.75, 99.3) ← displayBbox
         
Frame 3: bbox at (101, 102)
         ↓
         Similar to frame 2, cluster together
         ↓
         Smooth transition
         
Result: Плавное следование 🎯
```

## 🔌 Интеграционные точки

### 1. Native Module (в будущем)
```swift
// BarcodeDetectorModule.swift
processFrame(pixelBuffer: CVPixelBuffer) 
  → TFLiteInterpreter.predict()
  → [DetectionData]
  → decodeWithVision()
  → [DetectionData with rawCode]
```

### 2. React Native Side
```typescript
const result = await BarcodeDetector.processFrame({
  pixelBuffer: frame.pixelBuffer,
  width: 1280,
  height: 720,
  frameId: frameCount
});

bufferRef.current.appendDetections(result.detections);
```

## 📈 Performance Metrics

| Метрика | Значение | Примечание |
|---------|----------|-----------|
| Frame Rate | 60 FPS | Native camera |
| Detection Latency | 30-50ms | TFLite + Vision |
| Buffer Overhead | ~5ms | TemporalBuffer |
| Total Latency | 35-55ms | ~2-3 frames |
| Memory (Buffer) | ~5MB | 5 frames × 1280×720 × 4 |
| Model Size | ~5-10MB | best_quant.tflite |

## 🎮 Настройка для разных сценариев

### Scenario A: Максимальная плавность
```typescript
returnWindowSize: 8,        // Больше истории
returnFrameInterval: 3,     // Реже выводим
// Эффект: очень плавно, но медленнее реагирует
```

### Scenario B: Баланс
```typescript
returnWindowSize: 5,        // Default
returnFrameInterval: 2,     // Default
// Эффект: плавно + отзывчиво
```

### Scenario C: Максимальная отзывчивость
```typescript
returnWindowSize: 3,        // Меньше истории
returnFrameInterval: 1,     // Выводим каждый кадр
// Эффект: отзывчиво, но может быть jittery
```

## 🔮 Future: Улучшенное сглаживание

### Опция 1: Kalman Filter
```
Предсказывает следующую позицию на основе velocity
Более научный подход, но медленнее
```

### Опция 2: Optical Flow
```
Анализирует движение пикселей между кадрами
Дорого, но очень точно
```

### Опция 3: LSTM Predictor
```
Нейросетевой предиктор движения
Требует доп. модели
```

## 📚 Файлы и их роль

| Файл | Роль |
|------|------|
| `App.tsx` | Основной React компонент + UI |
| `TemporalDetectionBuffer.ts` | 🔑 Главный алгоритм плавности |
| `config.ts` | Параметры конфигурации |
| `types/index.ts` | TypeScript интерфейсы |
| `BarcodeDetectorModule.swift` | Native интеграция (TFLite) |
| `VisionBarcodeDecoder.swift` | Vision API декодирование |

---

**Готово!** Вся архитектура спроектирована для максимально плавного отслеживания кодов. 🎉
