import React, { useState, useEffect, useRef, useCallback } from 'react';
import {
  View,
  StyleSheet,
  Alert,
  Text,
  ActivityIndicator,
  TouchableOpacity,
  ScrollView,
} from 'react-native';
import { CameraView, useCameraPermissions } from 'expo-camera';
import { TemporalDetectionBuffer } from './src/utils/TemporalDetectionBuffer';
import { Detection, SmoothedDetection, DetectorConfig } from './src/types';
import { config } from './src/utils/config';

// Используем конфигурацию из config.ts
const DETECTOR_CONFIG: DetectorConfig = {
  returnWindowSize: config.detector.returnWindowSize,
  returnFrameInterval: config.detector.returnFrameInterval,
  stabilityThreshold: config.detector.stabilityThreshold,
  maxDetectionAge: config.detector.maxDetectionAge,
};

export default function App() {
  const cameraRef = useRef<CameraView>(null);
  const [permission, requestPermission] = useCameraPermissions();
  const [detections, setDetections] = useState<SmoothedDetection[]>([]);
  const [loading, setLoading] = useState(true);
  const [frameCount, setFrameCount] = useState(0);
  const [stats, setStats] = useState({
    avgProcessingTime: 0,
    detectionRate: 0,
  });
  const [showDetails, setShowDetails] = useState(false);

  const bufferRef = useRef(new TemporalDetectionBuffer(DETECTOR_CONFIG));
  const frameCountRef = useRef(0);
  const processingTimesRef = useRef<number[]>([]);
  const detectionHistoryRef = useRef<number[]>([]);

  useEffect(() => {
    if (!permission?.granted) {
      requestPermission();
    } else {
      setLoading(false);
    }
  }, [permission]);

  /**
   * Обработка каждого видеокадра
   */
  const handleFrameCapture = useCallback(async (frame: any) => {
    frameCountRef.current++;
    const frameStartTime = Date.now();

    try {
      // Генерируем тестовые детекции (в реальном коде здесь TFLite инференс)
      const mockDetections: Detection[] = [];

      // Каждый 3-й кадр добавляем тестовую детекцию
      if (frameCountRef.current % 3 === 0) {
        const detectionTypes: Array<'datamatrix' | 'pdf417' | 'code128'> = [
          'datamatrix',
          'pdf417',
          'code128',
        ];
        const typeIndex = Math.floor(
          Math.random() * detectionTypes.length
        );

        mockDetections.push({
          id: `detection-${frameCountRef.current}`,
          type: detectionTypes[typeIndex],
          rawCode: `CODE${frameCountRef.current}`,
          confidence: 0.85 + Math.random() * 0.14,
          bbox: {
            x: 50 + Math.sin(frameCountRef.current * 0.05) * 50,
            y: 100 + Math.cos(frameCountRef.current * 0.05) * 50,
            width: 200,
            height: 200,
          },
          timestamp: Date.now(),
          frameGeneration: frameCountRef.current,
        });
      }

      // Добавляем детекции в буфер временного сглаживания
      bufferRef.current.appendDetections(mockDetections);

      // Получаем стабилизированные детекции для отрисовки
      const stable = bufferRef.current.drainStableDetections();
      setDetections(stable);
      setFrameCount(frameCountRef.current);

      // Обновляем статистику
      const processingTime = Date.now() - frameStartTime;
      processingTimesRef.current.push(processingTime);
      if (processingTimesRef.current.length > 30) {
        processingTimesRef.current.shift();
      }

      detectionHistoryRef.current.push(stable.length);
      if (detectionHistoryRef.current.length > 30) {
        detectionHistoryRef.current.shift();
      }

      const avgTime =
        processingTimesRef.current.reduce((a, b) => a + b, 0) /
        processingTimesRef.current.length;
      const detectionRate =
        detectionHistoryRef.current.reduce((a, b) => a + b, 0) /
        detectionHistoryRef.current.length;

      setStats({
        avgProcessingTime: parseFloat(avgTime.toFixed(2)),
        detectionRate: parseFloat(detectionRate.toFixed(1)),
      });
    } catch (error) {
      console.error('Frame processing error:', error);
    }
  }, []);

  if (!permission) {
    return (
      <View style={styles.container}>
        <ActivityIndicator size="large" color="#00ff00" />
        <Text style={styles.text}>Запрашиваю доступ к камере...</Text>
      </View>
    );
  }

  if (!permission.granted) {
    return (
      <View style={styles.container}>
        <Text style={styles.text}>
          Необходимо предоставить доступ к камере
        </Text>
        <TouchableOpacity
          style={styles.button}
          onPress={requestPermission}
        >
          <Text style={styles.buttonText}>Предоставить доступ</Text>
        </TouchableOpacity>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <CameraView
        ref={cameraRef}
        style={styles.camera}
        facing="back"
        onFrameDropped={handleFrameCapture}
      >
        {/* Отрисовка bbox */}
        <View style={styles.overlayContainer}>
          {detections.map((detection) => (
            <BboxBox key={detection.id} detection={detection} />
          ))}
        </View>

        {/* Информационная панель */}
        <View style={styles.info}>
          <TouchableOpacity
            onPress={() => setShowDetails(!showDetails)}
            style={styles.infoHeader}
          >
            <Text style={styles.infoText}>
               Кадр: {frameCount} | Детекций: {detections.length}
            </Text>
          </TouchableOpacity>

          {showDetails && (
            <ScrollView style={styles.detailsScroll} nestedScrollEnabled>
              <Text style={styles.statsText}>
                Обработка: {stats.avgProcessingTime}ms
              </Text>
              <Text style={styles.statsText}>
                Сред. детекций: {stats.detectionRate}
              </Text>

              {detections.map((det) => (
                <View key={det.id} style={styles.detectionItem}>
                  <Text style={[styles.detectionText,
                    { color: getColorForType(det.type) }
                  ]}>
                    {det.type.toUpperCase()}
                  </Text>
                  <Text style={styles.codeText}>{det.rawCode}</Text>
                  <Text style={styles.confidenceText}>
                    Уверенность: {(det.confidence * 100).toFixed(0)}%
                  </Text>
                </View>
              ))}
            </ScrollView>
          )}
        </View>
      </CameraView>
    </View>
  );
}

interface BboxBoxProps {
  detection: SmoothedDetection;
}

function BboxBox({ detection }: BboxBoxProps) {
  const { displayBbox } = detection;
  const color = getColorForType(detection.type);

  return (
    <View
      style={[
        styles.bbox,
        {
          left: displayBbox.x,
          top: displayBbox.y,
          width: displayBbox.width,
          height: displayBbox.height,
          borderColor: color,
        },
      ]}
    >
      <View
        style={[
          styles.label,
          {
            backgroundColor: color,
          },
        ]}
      >
        <Text style={styles.labelText}>{detection.type.toUpperCase()}</Text>
      </View>
    </View>
  );
}

/**
 * Получить цвет для типа кода
 */
function getColorForType(
  type: 'datamatrix' | 'pdf417' | 'code128'
): string {
  return config.ui.barcodeColors[type];
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#000',
    justifyContent: 'center',
    alignItems: 'center',
  },
  camera: {
    flex: 1,
  },
  overlayContainer: {
    ...StyleSheet.absoluteFillObject,
    pointerEvents: 'none',
  },
  info: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    backgroundColor: 'rgba(0, 0, 0, 0.8)',
    paddingBottom: 20,
    maxHeight: '40%',
  },
  infoHeader: {
    padding: 12,
    borderBottomWidth: 1,
    borderBottomColor: '#333',
  },
  infoText: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '600',
  },
  detailsScroll: {
    maxHeight: '90%',
    paddingHorizontal: 10,
  },
  statsText: {
    color: '#0f0',
    fontSize: 12,
    marginTop: 8,
    fontFamily: 'Courier New',
  },
  detectionItem: {
    borderLeftWidth: 2,
    borderLeftColor: '#0f0',
    paddingLeft: 10,
    marginVertical: 8,
  },
  detectionText: {
    fontSize: 12,
    fontWeight: 'bold',
  },
  codeText: {
    color: '#fff',
    fontSize: 11,
    marginTop: 2,
  },
  confidenceText: {
    color: '#aaa',
    fontSize: 10,
    marginTop: 2,
  },
  text: {
    color: '#fff',
    fontSize: 16,
    marginTop: 20,
    textAlign: 'center',
  },
  button: {
    marginTop: 20,
    paddingHorizontal: 30,
    paddingVertical: 12,
    backgroundColor: '#0f0',
    borderRadius: 6,
  },
  buttonText: {
    color: '#000',
    fontWeight: '600',
    fontSize: 14,
  },
  bbox: {
    position: 'absolute',
    borderWidth: 2,
  },
  label: {
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 3,
    alignSelf: 'flex-start',
    marginTop: 4,
    marginLeft: 4,
  },
  labelText: {
    color: '#fff',
    fontSize: 10,
    fontWeight: 'bold',
  },
});
