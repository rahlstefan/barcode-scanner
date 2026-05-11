import { Detection, BoundingBox, SmoothedDetection, DetectorConfig } from '../types';

/**
 * Управляет буфером временных детекций
 * Реализует алгоритм, похожий на Честный Знак:
 * 1. Хранит детекции за последние N кадров
 * 2. Выбирает стабильные детекции по IOU и уверенности
 * 3. Выдает их с задержкой (returnFrameInterval)
 */
export class TemporalDetectionBuffer {
  private buffer: Detection[] = [];
  private smoothedCache: Map<string, SmoothedDetection> = new Map();
  private frameGeneration = 0;
  private lastOutputGeneration = 0;
  private config: DetectorConfig;

  constructor(config: Partial<DetectorConfig> = {}) {
    this.config = {
      returnWindowSize: config.returnWindowSize ?? 5,
      returnFrameInterval: config.returnFrameInterval ?? 2,
      stabilityThreshold: config.stabilityThreshold ?? 0.6,
      maxDetectionAge: config.maxDetectionAge ?? 500, // 500ms
    };
  }

  /**
   * Добавляет детекции из текущего кадра
   */
  appendDetections(detections: Detection[]): void {
    this.frameGeneration++;

    // Добавляем новые детекции с информацией о поколении
    for (const detection of detections) {
      const withGeneration = {
        ...detection,
        frameGeneration: this.frameGeneration,
      };
      this.buffer.push(withGeneration);
    }

    // Удаляем старые детекции (за пределами временного окна)
    const minGeneration = Math.max(
      0,
      this.frameGeneration - this.config.returnWindowSize
    );
    this.buffer = this.buffer.filter(
      (d) => d.frameGeneration >= minGeneration
    );
  }

  /**
   * Выбирает стабильные детекции для отрисовки
   * Применяется логика задержки (returnFrameInterval)
   */
  drainStableDetections(): SmoothedDetection[] {
    // Проверяем, нужно ли выводить детекции на этом кадре
    const frameDiff = this.frameGeneration - this.lastOutputGeneration;
    if (frameDiff < this.config.returnFrameInterval) {
      // Возвращаем кэшированные детекции
      return Array.from(this.smoothedCache.values());
    }

    this.lastOutputGeneration = this.frameGeneration;

    // Выбираем детекции из последнего окна
    const windowStart =
      this.frameGeneration - this.config.returnFrameInterval;
    const recentDetections = this.buffer.filter(
      (d) => d.frameGeneration >= windowStart
    );

    // Группируем по типу и координатам (IOU)
    const stableDetections = this.selectStableDetections(
      recentDetections
    );

    // Обновляем кэш
    this.smoothedCache.clear();
    for (const detection of stableDetections) {
      const displayBbox = this.interpolateBbox(detection);
      const smoothed: SmoothedDetection = {
        ...detection,
        displayBbox,
        isStable: true,
        remainingFrames: Math.round(
          this.config.maxDetectionAge / 16.67
        ), // ~60fps
      };
      this.smoothedCache.set(detection.id, smoothed);
    }

    return Array.from(this.smoothedCache.values());
  }

  /**
   * Выбирает стабильные детекции из буфера
   * (объединяет похожие детекции из нескольких кадров)
   */
  private selectStableDetections(detections: Detection[]): Detection[] {
    if (detections.length === 0) {
      return [];
    }

    // Группируем по типу кода
    const byType = new Map<string, Detection[]>();
    for (const detection of detections) {
      if (!byType.has(detection.type)) {
        byType.set(detection.type, []);
      }
      byType.get(detection.type)!.push(detection);
    }

    const stableDetections: Detection[] = [];

    // Для каждого типа выбираем лучшие детекции
    for (const [type, typeDetections] of byType.entries()) {
      // Группируем по пространственной близости (IOU)
      const clusters = this.clusterByIOU(typeDetections, 0.5);

      for (const cluster of clusters) {
        // Выбираем детекцию с наибольшей уверенностью из кластера
        const best = cluster.reduce((a, b) =>
          a.confidence > b.confidence ? a : b
        );

        // Сглаживаем координаты детекции внутри кластера
        const smoothedBbox = this.averageBbox(
          cluster.map((d) => d.bbox)
        );

        stableDetections.push({
          ...best,
          bbox: smoothedBbox,
        });
      }
    }

    return stableDetections;
  }

  /**
   * Кластеризует детекции по IOU (Intersection Over Union)
   */
  private clusterByIOU(
    detections: Detection[],
    threshold: number
  ): Detection[][] {
    if (detections.length === 0) return [];

    const clusters: Detection[][] = [];
    const used = new Set<number>();

    for (let i = 0; i < detections.length; i++) {
      if (used.has(i)) continue;

      const cluster = [detections[i]];
      used.add(i);

      for (let j = i + 1; j < detections.length; j++) {
        if (used.has(j)) continue;

        const iou = this.calculateIOU(
          detections[i].bbox,
          detections[j].bbox
        );
        if (iou > threshold) {
          cluster.push(detections[j]);
          used.add(j);
        }
      }

      clusters.push(cluster);
    }

    return clusters;
  }

  /**
   * Вычисляет IOU между двумя bbox
   */
  private calculateIOU(box1: BoundingBox, box2: BoundingBox): number {
    const intersection = this.getIntersectionArea(box1, box2);
    const union =
      box1.width * box1.height +
      box2.width * box2.height -
      intersection;

    return union === 0 ? 0 : intersection / union;
  }

  /**
   * Вычисляет площадь пересечения двух bbox
   */
  private getIntersectionArea(
    box1: BoundingBox,
    box2: BoundingBox
  ): number {
    const x1 = Math.max(box1.x, box2.x);
    const y1 = Math.max(box1.y, box2.y);
    const x2 = Math.min(box1.x + box1.width, box2.x + box2.width);
    const y2 = Math.min(box1.y + box1.height, box2.y + box2.height);

    if (x2 < x1 || y2 < y1) return 0;
    return (x2 - x1) * (y2 - y1);
  }

  /**
   * Усредняет координаты bbox из нескольких детекций
   */
  private averageBbox(boxes: BoundingBox[]): BoundingBox {
    if (boxes.length === 0) {
      return { x: 0, y: 0, width: 0, height: 0 };
    }

    const avg = boxes.reduce(
      (acc, box) => ({
        x: acc.x + box.x,
        y: acc.y + box.y,
        width: acc.width + box.width,
        height: acc.height + box.height,
      }),
      { x: 0, y: 0, width: 0, height: 0 }
    );

    return {
      x: avg.x / boxes.length,
      y: avg.y / boxes.length,
      width: avg.width / boxes.length,
      height: avg.height / boxes.length,
    };
  }

  /**
   * Интерполирует bbox для гладкого отображения
   * (линейная интерполяция между последними известными позициями)
   */
  private interpolateBbox(detection: Detection): BoundingBox {
    // Ищем предыдущие позиции этой детекции в буфере
    const history = this.buffer
      .filter(
        (d) =>
          d.id === detection.id ||
          this.isSameBarcodeType(d, detection)
      )
      .sort((a, b) => b.frameGeneration - a.frameGeneration)
      .slice(0, 3);

    if (history.length < 2) {
      return detection.bbox;
    }

    // Простая линейная интерполяция между последними позициями
    const current = history[0].bbox;
    const previous = history[1].bbox;

    // Коэффициент интерполяции (0-1, где 1 = полностью текущая позиция)
    const alpha = 0.7;

    return {
      x: previous.x + (current.x - previous.x) * alpha,
      y: previous.y + (current.y - previous.y) * alpha,
      width: previous.width + (current.width - previous.width) * alpha,
      height:
        previous.height +
        (current.height - previous.height) * alpha,
    };
  }

  /**
   * Проверяет, является ли это той же детекцией (для сопоставления)
   */
  private isSameBarcodeType(
    d1: Detection,
    d2: Detection
  ): boolean {
    return d1.type === d2.type;
  }

  /**
   * Очищает буфер
   */
  clear(): void {
    this.buffer = [];
    this.smoothedCache.clear();
    this.frameGeneration = 0;
    this.lastOutputGeneration = 0;
  }

  /**
   * Получает текущее состояние буфера (для отладки)
   */
  getDebugInfo() {
    return {
      bufferSize: this.buffer.length,
      frameGeneration: this.frameGeneration,
      lastOutputGeneration: this.lastOutputGeneration,
      smoothedCount: this.smoothedCache.size,
    };
  }
}
