# 🚀 QUICKSTART - Barcode Scanner

Быстрая настройка и запуск приложения за 5 минут.

## ⚡ Минимальный старт (без Native модулей)

### Шаг 1: Установка зависимостей
```bash
cd BarcodeScanner
npm install
```

### Шаг 2: Запуск в Expo Go
```bash
npm start
```

Затем:
- iOS: Нажмите `i`
- Android: Нажмите `a`

**Результат:** Приложение запустится с mock детекциями, которые движутся по экрану.

---

## 🔧 Полный старт с Native модулями

### Требования
- Xcode 15+ (для iOS)
- iOS 14+
- Expo CLI

### Шаг 1: Подготовка моделей
```bash
# Скопируйте TFLite модель
bash scripts/prepare-models.sh /path/to/candidate3_balanced_adamw_musgd_phase1_v2/weights

# Или скопируйте вручную
cp ../candidate3_balanced_adamw_musgd_phase1_v2/weights/best_full_integer_quant.tflite \
   assets/models/best_quant.tflite
```

### Шаг 2: Установка зависимостей
```bash
npm install
```

### Шаг 3: Prebuild для iOS
```bash
npm run prebuild
```

Это создаст:
- `ios/` - Xcode проект
- `android/` - Android Studio проект

### Шаг 4: Запуск на реальном устройстве
```bash
# iOS
npm run ios

# Или откройте Xcode и запустите вручную
open ios/BarcodeScanner.xcworkspace
```

---

## 📊 Структура проекта

```
BarcodeScanner/
├── App.tsx                      # Основное приложение (React Native)
├── app.json                     # Конфигурация Expo
├── package.json
├── tsconfig.json
│
├── src/                         # React/TypeScript код
│   ├── types/
│   │   └── index.ts            # TypeScript типы
│   ├── utils/
│   │   ├── TemporalDetectionBuffer.ts  # Алгоритм сглаживания ✨
│   │   └── config.ts           # Конфигурация приложения
│   └── components/             # React компоненты (пусто, готово расширению)
│
├── modules/
│   └── barcode-detector/       # Expo Native Module
│       ├── index.ts            # TypeScript интерфейс
│       ├── ios/
│       │   ├── BarcodeDetectorModule.swift
│       │   ├── BarcodeTypes.swift
│       │   └── BarcodeDetectorModule+Swift.swift
│       └── package.json
│
├── assets/
│   ├── models/                 # TFLite модели (скопируйте сюда)
│   │   └── best_quant.tflite
│   └── (иконки и splash)
│
└── scripts/
    └── prepare-models.sh       # Скрипт подготовки моделей
```

---

## 🎯 Что работает

### ✅ Готовое
1. **Temporal Smoothing Engine** (`TemporalDetectionBuffer.ts`)
   - Буферизация детекций за N кадров
   - Кластеризация по IOU
   - Интерполяция позиций
   - Плавное отслеживание bbox (как в Честный Знак)

2. **React Native UI**
   - Камера с высоким FPS
   - Отрисовка bbox с цветами
   - Информационная панель
   - Статистика FPS и обработки

3. **Expo Native Module шаблон**
   - Готовая структура для Custom Native Code
   - Swift интеграция

### ⏳ Требует интеграции TFLite

Для полного функционала нужно:
1. Добавить TensorFlow Lite SDK (см. `INTEGRATION_GUIDE.md`)
2. Реализовать инференс в `BarcodeDetectorModule.swift`
3. Подключить Vision API для декодирования

---

## 🎮 Демо-режим

При первом запуске приложение работает в демо-режиме:
- Mock детекции движутся по экрану
- Демонстрирует алгоритм сглаживания
- Показывает статистику FPS

```typescript
// Отключить демо (в App.tsx):
const mockDetections: Detection[] = []; // Оставить пусто
```

---

## 📱 Использование приложения

1. **Разрешить доступ к камере** - нажмите "Предоставить доступ"
2. **Нацелите камеру на код** - движимый бокс будет следовать за кодом
3. **Тапните на информацию** - см. детали распознанных кодов

### Эффекты плавности
- **returnWindowSize: 5** - Держит детекции за 5 кадров
- **returnFrameInterval: 2** - Выводит каждый 2-й кадр
- **IOU clustering: 0.5** - Объединяет похожие детекции
- **Interpolation: 0.7** - Плавная интерполяция позиций

---

## ⚙️ Настройка параметров

### Редактируем `src/utils/config.ts`:

```typescript
detector: {
  returnWindowSize: 5,        // 👈 Больше = плавнее
  returnFrameInterval: 2,     // 👈 Больше = менее отзывчиво
  stabilityThreshold: 0.65,   // 👈 Больше = строже фильтр
  iouThreshold: 0.5,          // 👈 Порог кластеризации
}
```

### Параметры для разных сценариев:

**Максимальная плавность:**
```
returnWindowSize: 8
returnFrameInterval: 3
stabilityThreshold: 0.6
```

**Максимальная отзывчивость:**
```
returnWindowSize: 3
returnFrameInterval: 1
stabilityThreshold: 0.7
```

---

## 🐛 Отладка

### Включить логирование
```typescript
// App.tsx
console.log(bufferRef.current.getDebugInfo());
```

### Проверить статистику
- Нижняя панель показывает: кадры, детекции, время обработки
- Тап на панель = развернуть детали

### Проблемы

**"Camera access denied"**
```bash
# iOS: Settings > BarcodeScanner > Camera
# Дайте доступ и перезапустите
```

**"Too slow / Low FPS"**
```
1. Уменьшите returnWindowSize
2. Пропускайте кадры (skip frames)
3. Оптимизируйте TFLite модель
```

**"Native module not found"**
```bash
npm run prebuild --clean
npm run ios
```

---

## 📚 Документация

- **[README.md](README.md)** - Полная документация архитектуры
- **[INTEGRATION_GUIDE.md](INTEGRATION_GUIDE.md)** - TFLite интеграция
- **[src/utils/TemporalDetectionBuffer.ts](src/utils/TemporalDetectionBuffer.ts)** - Алгоритм сглаживания (с комментариями)
- **[dmtx_bbox_reconstruction.md](../dmtx_bbox_reconstruction.md)** - Анализ Честного Знака

---

## 🚀 Следующие шаги

1. **Для демо на Expo Go:**
   - `npm start` ✓ (работает сейчас)

2. **Для Native сборки:**
   - Интегрируйте TFLite (см. INTEGRATION_GUIDE.md)
   - `npm run prebuild`
   - `npm run ios`

3. **Для Production:**
   - Оптимизируйте размер модели
   - Добавьте звуковую обратную связь
   - Сохранение истории кодов
   - Обработка нескольких кодов

---

## 💡 Советы

✨ **Алгоритм плавности основан на анализе приложения Честный Знак:**
- Временная буферизация вместо immediate rendering
- Кластеризация по IOU вместо tracking
- Интерполяция вместо raw predictions
- Результат = супер плавное отслеживание

🎯 **Для максимальной плавности:**
- Используйте GPU-ускорение (Metal на iOS)
- Пропускайте неважные кадры
- Регулируйте paramety под ваш FPS

---

**Готово к разработке! 🎉**

Вопросы? → Смотрите документацию выше или пересмотрите `dmtx_bbox_reconstruction.md` для деталей архитектуры.
