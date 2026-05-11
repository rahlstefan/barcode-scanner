# Barcode Scanner - Плавное распознавание кодов на iOS

Приложение для распознавания Datamatrix, PDF417 и Code128 кодов с плавным отслеживанием bbox (как в приложении "Честный Знак").

## Архитектура

### Слои приложения:

1. **React Native UI** (`App.tsx`)
   - Камера и отрисовка боксов
   - Управление пермиссиями
   - Вывод результатов

2. **Temporal Smoothing Engine** (`src/utils/TemporalDetectionBuffer.ts`)
   - Буферизация детекций за N кадров
   - Кластеризация по IOU
   - Интерполяция позиций
   - Задержанный вывод (returnFrameInterval)

3. **Native Module** (`modules/barcode-detector/`)
   - Vision API интеграция
   - TFLite инференс
   - Обработка видеокадров

## Алгоритм плавности

Вдохновлен анализом приложения Честный Знак (см. `dmtx_bbox_reconstruction.md`):

```
Видеокадр
  ↓
[Детекция YOLO26N + Vision API]
  ↓
[Валидация (NMS, фильтрация по локации)]
  ↓
appendDetections() → pendingDetections[]
  ↓
[Временное окно: returnWindowSize = 5 кадров]
  ↓
[Кластеризация по IOU]
  ↓
[Интерполяция позиций]
  ↓
drainPendingDetections() (каждый returnFrameInterval = 2 кадра)
  ↓
[Отрисовка стабилизированного bbox]
```

### Параметры конфигурации

```typescript
const DETECTOR_CONFIG = {
  returnWindowSize: 5,        // Держать детекции за 5 кадров
  returnFrameInterval: 2,     // Выводить каждый 2-й кадр  
  stabilityThreshold: 0.65,   // Min confidence 65%
  maxDetectionAge: 500,       // 500ms максимум
};
```

## Подготовка модели

### 1. Копирование TFLite модели

```bash
# Скопируйте best_quant.tflite в assets
cp candidate3_balanced_adamw_musgd_phase1_v2/weights/best_full_integer_quant.tflite \
   assets/models/best_quant.tflite
```

### 2. Структура проекта после подготовки

```
BarcodeScanner/
├── App.tsx                          # React Native UI
├── app.json                         # Конфигурация Expo
├── package.json
├── tsconfig.json
├── assets/
│   └── models/
│       └── best_quant.tflite        # TFLite модель
├── src/
│   ├── types/
│   │   └── index.ts                 # TypeScript типы
│   ├── utils/
│   │   └── TemporalDetectionBuffer.ts # Сглаживание
│   └── components/                  # React компоненты
└── modules/
    └── barcode-detector/
        ├── ios/
        │   ├── BarcodeDetectorModule.swift
        │   └── BarcodeTypes.swift
        ├── index.ts
        └── package.json
```

## Установка и запуск

### Требования

- Node.js 18+
- npm/yarn
- Xcode 15+ (для iOS)
- Expo CLI

### 1. Установка зависимостей

```bash
cd BarcodeScanner
npm install
# или
yarn install
```

### 2. Подготовка к prebuild

```bash
npm run prebuild
```

Это создаст нативный проект в `ios/` и `android/`.

### 3. Запуск в Expo DEV

```bash
npm start
```

Затем нажмите `i` для iOS или `a` для Android.

### 4. Сборка для тестирования на реальном устройстве

```bash
npm run ios
```

## Интеграция TFLite инференса

На текущий момент модель загружается, но инференс требует полной интеграции TensorFlow Lite SDK.

### Шаги для полной интеграции:

1. **Добавить TFLite SDK в Podfile** (`ios/Podfile`):
```ruby
target 'BarcodeScanner' do
  pod 'TensorFlowLiteSwift'
  pod 'TensorFlowLiteMetalDelegate'
end
```

2. **Реализовать TFLiteInterpreter** в `ios/BarcodeDetectorModule.swift`:
```swift
import TensorFlowLite

class TFLiteModel {
  var interpreter: Interpreter?
  
  func load(from path: String) throws {
    let options = Interpreter.Options()
    interpreter = try Interpreter(modelPath: path, options: options)
    try interpreter?.allocateTensors()
  }
}
```

3. **Подключить к CameraView**:
```typescript
// Каждый видеокадр → TFLite инференс → детекции
const detections = await BarcodeDetector.processFrame(frame);
```

## Настройка параметров

### Регулировка плавности:

- **Более плавно**: увеличить `returnWindowSize` (6-8) и `returnFrameInterval` (3-4)
- **Более отзывчиво**: уменьшить (3-4 и 1-2)
- **Стабильнее**: увеличить `stabilityThreshold` (0.7-0.8)

### Регулировка производительности:

- Уменьшить размер входного изображения в TFLite
- Использовать GPU/Metal делегаты
- Оптимизировать обработку кадров (skip frames)

## Отладка

### Включение логирования:

```typescript
// В App.tsx
console.log(bufferRef.current.getDebugInfo());
// Выведет: bufferSize, frameGeneration, smoothedCount
```

### Визуализация временного окна:

В приложении показывается:
- Номер текущего кадра
- Количество активных детекций
- Каждая детекция с кодом и уверенностью

## Дальнейшее развитие

- [ ] Полная интеграция TFLite инференса
- [ ] Audio feedback при успешном распознавании
- [ ] Сохранение истории сканирований
- [ ] Обработка нескольких кодов одновременно
- [ ] Расширенное сглаживание (Kalman filter)
- [ ] Оптимизация под разные разрешения экрана

## Лицензия

ISC
