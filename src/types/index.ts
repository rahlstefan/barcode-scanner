export interface BoundingBox {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface Detection {
  id: string;
  type: 'datamatrix' | 'pdf417' | 'code128';
  rawCode: string;
  confidence: number;
  bbox: BoundingBox;
  timestamp: number;
  frameGeneration: number;
}

export interface SmoothedDetection extends Detection {
  displayBbox: BoundingBox;
  isStable: boolean;
  remainingFrames: number;
}

export interface FrameResult {
  detections: Detection[];
  frameId: number;
  timestamp: number;
}

export interface DetectorConfig {
  returnWindowSize: number; // Количество кадров для хранения
  returnFrameInterval: number; // Интервал кадров для вывода
  stabilityThreshold: number; // Порог уверенности
  maxDetectionAge: number; // Макс возраст детекции в мс
}

export interface VideoFrameData {
  pixelBuffer: any; // CVPixelBuffer на iOS
  frameWidth: number;
  frameHeight: number;
  timestamp: number;
}
