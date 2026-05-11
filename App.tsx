import React, { useEffect, useRef, useState, useCallback } from 'react';
import {
  View,
  StyleSheet,
  Text,
  TouchableOpacity,
  ActivityIndicator,
  ScrollView,
  Dimensions,
  Platform,
} from 'react-native';
import {
  Camera,
  useCameraDevice,
  useCameraPermission,
  useFrameProcessor,
} from 'react-native-vision-camera';
import { loadTensorflowModel, TensorflowModel } from 'react-native-fast-tflite';
import { useResizePlugin } from 'vision-camera-resize-plugin';
import { Worklets } from 'react-native-worklets-core';
import { bundleDirectory } from 'expo-file-system/legacy';
import { TemporalDetectionBuffer } from './src/utils/TemporalDetectionBuffer';
import { Detection, SmoothedDetection } from './src/types';

const MODEL_INPUT_SIZE = 320;
const SCORE_THRESHOLD = 0.4;
const SCREEN = Dimensions.get('window');

// ----- raw detection from worklet -----
type RawDet = {
  x1: number; // normalized 0..1
  y1: number;
  x2: number;
  y2: number;
  score: number;
  cls: number;
};

export default function App() {
  const { hasPermission, requestPermission } = useCameraPermission();
  const device = useCameraDevice('back');

  const [modelLoadState, setModelLoadState] = useState<'loading' | 'loaded' | 'error'>('loading');
  const [modelError, setModelError] = useState<string | null>(null);
  const [actualModel, setActualModel] = useState<TensorflowModel | undefined>(
    undefined
  );

  useEffect(() => {
    let cancelled = false;
    const loadModelWithFallbacks = async () => {
      try {
        setModelLoadState('loading');
        setModelError(null);

        const attempts: Array<{ label: string; source: number | { url: string } }> = [
          { label: 'require(./assets/models/yolo.tflite)', source: require('./assets/models/yolo.tflite') as number },
        ];

        if (Platform.OS === 'ios' && bundleDirectory) {
          const normalizedBundleDir = bundleDirectory.endsWith('/')
            ? bundleDirectory
            : `${bundleDirectory}/`;
          const bundleUrl = normalizedBundleDir.startsWith('file://')
            ? normalizedBundleDir
            : `file://${normalizedBundleDir}`;

          // В iOS bundle путь может резолвиться по-разному между сборками.
          const relCandidates = [
            'assets/assets/models/yolo.tflite',
            'assets/models/yolo.tflite',
            'yolo.tflite',
          ];

          for (const rel of relCandidates) {
            attempts.push({
              label: `bundle-url:${rel}`,
              source: { url: `${bundleUrl}${rel}` },
            });
            attempts.push({
              label: `bundle-path:${rel}`,
              source: { url: `${normalizedBundleDir}${rel}` },
            });
          }
        }

        const errors: string[] = [];
        for (const attempt of attempts) {
          try {
            const loaded = await loadTensorflowModel(attempt.source);
            if (!cancelled) {
              setActualModel(loaded);
              setModelLoadState('loaded');
            }
            return;
          } catch (e: any) {
            errors.push(`${attempt.label}: ${String(e?.message ?? e)}`);
          }
        }

        if (!cancelled) {
          setActualModel(undefined);
          setModelLoadState('error');
          setModelError(errors.join('\n\n'));
        }
      } catch (e: any) {
        if (!cancelled) {
          setActualModel(undefined);
          setModelLoadState('error');
          setModelError(String(e?.message ?? e));
        }
      }
    };

    loadModelWithFallbacks();
    return () => {
      cancelled = true;
    };
  }, []);
  const { resize } = useResizePlugin();

  const [detections, setDetections] = useState<SmoothedDetection[]>([]);
  const [stats, setStats] = useState({ inferMs: 0, fps: 0, raw: 0 });
  const [showDetails, setShowDetails] = useState(false);
  const [frameSize, setFrameSize] = useState<{ w: number; h: number } | null>(
    null
  );

  const bufferRef = useRef(
    new TemporalDetectionBuffer({
      returnWindowSize: 6,
      returnFrameInterval: 2,
      stabilityThreshold: 0.5,
      maxDetectionAge: 600,
    })
  );
  const frameCountRef = useRef(0);
  const lastInferTimesRef = useRef<number[]>([]);
  const lastTickRef = useRef(Date.now());
  const fpsCounterRef = useRef(0);

  useEffect(() => {
    if (!hasPermission) requestPermission();
  }, [hasPermission, requestPermission]);

  /**
   * Вызывается из worklet через runOnJS.
   * Принимает сырые детекции YOLO (нормализованные 0..1),
   * прогоняет через TemporalDetectionBuffer и обновляет state.
   */
  const onRawDetections = useCallback(
    (raw: RawDet[], inferMs: number, fw: number, fh: number) => {
      frameCountRef.current++;
      fpsCounterRef.current++;

      // Обновляем размеры кадра если изменились
      if (!frameSize || frameSize.w !== fw || frameSize.h !== fh) {
        setFrameSize({ w: fw, h: fh });
      }

      // Координаты модели → координаты экрана (учёт aspect ratio
      // через cover-режим Camera).
      const screenW = SCREEN.width;
      const screenH = SCREEN.height;
      const frameAspect = fw / fh;
      const screenAspect = screenW / screenH;

      // VisionCamera "cover" — кадр заполняет весь экран, обрезая
      // по более узкой стороне.
      let scale: number;
      let offsetX = 0;
      let offsetY = 0;
      if (frameAspect > screenAspect) {
        // Кадр шире — ограничивает высота
        scale = screenH / fh;
        offsetX = (fw * scale - screenW) / 2;
      } else {
        // Кадр уже — ограничивает ширина
        scale = screenW / fw;
        offsetY = (fh * scale - screenH) / 2;
      }

      const dets: Detection[] = raw.map((d, i) => {
        const x1px = d.x1 * fw * scale - offsetX;
        const y1px = d.y1 * fh * scale - offsetY;
        const x2px = d.x2 * fw * scale - offsetX;
        const y2px = d.y2 * fh * scale - offsetY;
        return {
          id: `det-${frameCountRef.current}-${i}`,
          type: 'datamatrix',
          rawCode: '',
          confidence: d.score,
          bbox: {
            x: x1px,
            y: y1px,
            width: x2px - x1px,
            height: y2px - y1px,
          },
          timestamp: Date.now(),
          frameGeneration: frameCountRef.current,
        };
      });

      bufferRef.current.appendDetections(dets);
      const smoothed = bufferRef.current.drainStableDetections();
      setDetections(smoothed);

      // Stats
      lastInferTimesRef.current.push(inferMs);
      if (lastInferTimesRef.current.length > 30)
        lastInferTimesRef.current.shift();
      const avg =
        lastInferTimesRef.current.reduce((a, b) => a + b, 0) /
        lastInferTimesRef.current.length;
      const now = Date.now();
      if (now - lastTickRef.current >= 1000) {
        setStats({
          inferMs: parseFloat(avg.toFixed(1)),
          fps: fpsCounterRef.current,
          raw: raw.length,
        });
        fpsCounterRef.current = 0;
        lastTickRef.current = now;
      }
    },
    [frameSize]
  );

  const onRawDetectionsJS = Worklets.createRunOnJS(onRawDetections);

  const frameProcessor = useFrameProcessor(
    (frame) => {
      'worklet';
      if (actualModel == null) return;

      const t0 = Date.now();

      // Resize кадр до 320x320 RGB float32 [0..1]
      const resized = resize(frame, {
        scale: { width: MODEL_INPUT_SIZE, height: MODEL_INPUT_SIZE },
        pixelFormat: 'rgb',
        dataType: 'float32',
      });

      const outputs = actualModel.runSync([resized]);
      const t1 = Date.now();

      // Output формат YOLO26n с встроенным NMS:
      // outputs[0] shape = [1, max_dets, 6] -> (x1, y1, x2, y2, score, cls)
      // координаты нормализованы 0..1
      const out = outputs[0] as unknown as Float32Array;
      const numDets = Math.floor(out.length / 6);
      const raw: RawDet[] = [];
      for (let i = 0; i < numDets; i++) {
        const off = i * 6;
        const score = out[off + 4];
        if (score < SCORE_THRESHOLD) continue;
        raw.push({
          x1: out[off + 0],
          y1: out[off + 1],
          x2: out[off + 2],
          y2: out[off + 3],
          score: score,
          cls: out[off + 5],
        });
      }

      onRawDetectionsJS(raw, t1 - t0, frame.width, frame.height);
    },
    [actualModel]
  );

  // ---- UI ----
  if (!hasPermission) {
    return (
      <View style={styles.center}>
        <Text style={styles.statusText}>Нет доступа к камере</Text>
        <TouchableOpacity style={styles.button} onPress={requestPermission}>
          <Text style={styles.buttonText}>Запросить доступ</Text>
        </TouchableOpacity>
      </View>
    );
  }

  if (device == null) {
    return (
      <View style={styles.center}>
        <ActivityIndicator color="#0f0" size="large" />
        <Text style={styles.statusText}>Поиск камеры...</Text>
      </View>
    );
  }

  if (modelLoadState === 'error') {
    return (
      <View style={styles.center}>
        <Text style={[styles.statusText, { color: '#f44' }]}>Ошибка загрузки модели:</Text>
        <Text style={styles.errorText}>{modelError}</Text>
      </View>
    );
  }

  if (modelLoadState === 'loading') {
    return (
      <View style={styles.center}>
        <ActivityIndicator color="#0f0" size="large" />
        <Text style={styles.statusText}>Загрузка YOLO модели...</Text>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <Camera
        style={StyleSheet.absoluteFill}
        device={device}
        isActive={true}
        frameProcessor={frameProcessor}
        pixelFormat="yuv"
      />

      {/* Bbox overlay */}
      <View style={styles.overlay} pointerEvents="none">
        {detections.map((d) => (
          <BboxView key={d.id} det={d} />
        ))}
      </View>

      {/* Info panel */}
      <View style={styles.info}>
        <TouchableOpacity onPress={() => setShowDetails(!showDetails)}>
          <Text style={styles.infoText}>
            FPS: {stats.fps} | Inference: {stats.inferMs}ms | Raw: {stats.raw}{' '}
            | Smoothed: {detections.length}
          </Text>
        </TouchableOpacity>
        {showDetails && (
          <ScrollView style={styles.details}>
            {detections.map((d) => (
              <Text key={d.id} style={styles.detailText}>
                {(d.confidence * 100).toFixed(0)}% [
                {Math.round(d.displayBbox.x)},{Math.round(d.displayBbox.y)},
                {Math.round(d.displayBbox.width)}×
                {Math.round(d.displayBbox.height)}]
              </Text>
            ))}
          </ScrollView>
        )}
      </View>
    </View>
  );
}

function BboxView({ det }: { det: SmoothedDetection }) {
  const { displayBbox: b, confidence } = det;
  return (
    <View
      style={[
        styles.bbox,
        {
          left: b.x,
          top: b.y,
          width: b.width,
          height: b.height,
        },
      ]}
    >
      <View style={styles.bboxLabel}>
        <Text style={styles.bboxLabelText}>
          DM {(confidence * 100).toFixed(0)}%
        </Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#000' },
  center: {
    flex: 1,
    backgroundColor: '#000',
    justifyContent: 'center',
    alignItems: 'center',
    padding: 20,
  },
  statusText: { color: '#fff', fontSize: 16, marginTop: 16 },
  errorText: {
    color: '#f88',
    fontSize: 12,
    marginTop: 8,
    textAlign: 'center',
  },
  button: {
    marginTop: 20,
    backgroundColor: '#0a84ff',
    paddingVertical: 12,
    paddingHorizontal: 24,
    borderRadius: 8,
  },
  buttonText: { color: '#fff', fontSize: 16, fontWeight: '600' },
  overlay: { ...StyleSheet.absoluteFillObject },
  bbox: {
    position: 'absolute',
    borderWidth: 2,
    borderColor: '#0f0',
    borderRadius: 2,
  },
  bboxLabel: {
    position: 'absolute',
    top: -22,
    left: 0,
    backgroundColor: '#0f0',
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 2,
  },
  bboxLabelText: { color: '#000', fontSize: 11, fontWeight: 'bold' },
  info: {
    position: 'absolute',
    top: 60,
    left: 12,
    right: 12,
    backgroundColor: 'rgba(0,0,0,0.65)',
    padding: 10,
    borderRadius: 8,
  },
  infoText: { color: '#0f0', fontFamily: 'Courier', fontSize: 12 },
  details: { maxHeight: 200, marginTop: 6 },
  detailText: {
    color: '#aaa',
    fontFamily: 'Courier',
    fontSize: 10,
    marginTop: 2,
  },
});
