import { Platform } from 'react-native';

/**
 * Конфигурация приложения для разных платформ
 */
export const config = {
  app: {
    name: 'BarcodeScanner',
    version: '1.0.0',
    description: 'Advanced barcode detection with smooth tracking',
  },
  
  // Параметры детектора
  detector: {
    // Временное окно для буферизации детекций (кадры)
    returnWindowSize: 5,
    
    // Интервал вывода детекций (выводим каждый N-й кадр)
    returnFrameInterval: 2,
    
    // Минимальная уверенность для детекции
    stabilityThreshold: 0.65,
    
    // Максимальный возраст детекции (мс)
    maxDetectionAge: 500,
    
    // Порог IOU для кластеризации
    iouThreshold: 0.5,
    
    // Максимум детекций на кадр
    maxDetections: 10,
  },
  
  // Параметры видео
  camera: {
    facing: 'back' as const,
    fps: 30,
    
    // Размер входного изображения для модели
    modelInputSize: Platform.OS === 'ios' ? 640 : 416,
    
    // Поддерживаемые разрешения
    presets: {
      ios: ['1280x720', '640x480'],
      android: ['1280x720', '640x480'],
    },
  },
  
  // Пути к моделям
  models: {
    // Путь к TFLite модели YOLO26N
    tflitePath: Platform.select({
      ios: './assets/models/best_quant.tflite',
      android: './assets/models/best_quant.tflite',
    }),
    
    // Типы кодов для распознавания
    supportedBarcodes: ['datamatrix', 'pdf417', 'code128'],
  },
  
  // UI параметры
  ui: {
    // Цвета для разных типов кодов
    barcodeColors: {
      datamatrix: '#00FF00',
      pdf417: '#FF0000',
      code128: '#0000FF',
    },
    
    // Толщина линии bbox
    bboxLineWidth: 2,
    
    // Шрифт
    fontSize: 12,
  },
  
  // Логирование и отладка
  debug: {
    enabled: true,
    logFrameStats: true,
    showBufferInfo: true,
    logDetections: true,
  },
};

/**
 * Получить текущую конфигурацию
 */
export function getConfig() {
  return config;
}

/**
 * Обновить конфигурацию
 */
export function updateConfig(updates: Partial<typeof config>) {
  Object.assign(config, updates);
}
