import { NativeModule, requireNativeModule } from 'expo';

export interface DetectionResult {
  id: string;
  type: 'datamatrix' | 'pdf417' | 'code128';
  rawCode: string;
  confidence: number;
  bbox: {
    x: number;
    y: number;
    width: number;
    height: number;
  };
  timestamp: number;
}

export interface FrameProcessResult {
  detections: DetectionResult[];
  frameId: number;
  processingTime: number;
}

export interface BarcodeDetectorConfig {
  modelPath: string;
  confidenceThreshold: number;
  iouThreshold: number;
  maxDetections: number;
}

export interface CameraFrameData {
  pixelBuffer: any;
  width: number;
  height: number;
  timestamp: number;
}

declare class BarcodeDetectorModule extends NativeModule {
  initialize(config: BarcodeDetectorConfig): Promise<boolean>;
  processFrame(frame: CameraFrameData): Promise<FrameProcessResult>;
  getModelInfo(): Promise<{ name: string; version: string }>;
  release(): Promise<void>;
}

const BarcodeDetector = requireNativeModule(
  'BarcodeDetector'
) as typeof BarcodeDetectorModule;

export default BarcodeDetector;
