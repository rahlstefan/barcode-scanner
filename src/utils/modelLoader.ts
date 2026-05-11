import { cacheDirectory, writeAsStringAsync, getInfoAsync } from 'expo-file-system/legacy';

// Модель хранится в GitHub репозитории и скачивается один раз при первом запуске.
const MODEL_DOWNLOAD_URL =
  'https://raw.githubusercontent.com/rahlstefan/barcode-scanner/main/assets/models/yolo.tflite';
const MODEL_CACHE_FILENAME = 'yolo-model.tflite';

/**
 * Конвертирует ArrayBuffer в base64 строку без Buffer.
 */
function arrayBufferToBase64(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer);
  let binary = '';
  for (let i = 0; i < bytes.byteLength; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary);
}

/**
 * Скачивает модель один раз и кеширует.
 * При повторных запусках загружает из кеша.
 */
export async function ensureModelCached(): Promise<string> {
  if (!cacheDirectory) {
    throw new Error('cacheDirectory недоступен');
  }

  const cacheFile = `${cacheDirectory}${MODEL_CACHE_FILENAME}`;

  // Проверяем если уже в кеше
  try {
    const info = await getInfoAsync(cacheFile);
    if (info.exists && info.size && info.size > 1000000) {
      // Файл есть и имеет разумный размер (> 1 MB)
      console.log('[ModelLoader] Loaded from cache:', cacheFile);
      return cacheFile;
    }
  } catch (e) {
    console.log('[ModelLoader] Cache check failed, will download');
  }

  // Скачиваем модель
  console.log('[ModelLoader] Downloading from:', MODEL_DOWNLOAD_URL);
  const response = await fetch(MODEL_DOWNLOAD_URL);

  if (!response.ok) {
    throw new Error(`Failed to download model: HTTP ${response.status}`);
  }

  // Читаем как arrayBuffer и конвертируем в base64
  const buffer = await response.arrayBuffer();
  const base64 = arrayBufferToBase64(buffer);

  console.log(`[ModelLoader] Downloaded ${buffer.byteLength} bytes, encoding as base64`);

  // Пишем base64 версию
  await writeAsStringAsync(cacheFile, base64, { encoding: 'utf8' });

  console.log('[ModelLoader] Cached to:', cacheFile);
  return cacheFile;
}
