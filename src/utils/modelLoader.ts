import { cacheDirectory, downloadAsync, getInfoAsync } from 'expo-file-system/legacy';

// Модель хранится в GitHub репозитории и скачивается один раз при первом запуске.
const MODEL_DOWNLOAD_URL =
  'https://raw.githubusercontent.com/rahlstefan/barcode-scanner/main/assets/models/best_full_integer_quant.tflite';
const MODEL_CACHE_FILENAME = 'yolo-model-int8-v1.tflite';

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
  const result = await downloadAsync(MODEL_DOWNLOAD_URL, cacheFile);
  if (result.status !== 200) {
    throw new Error(`Failed to download model: HTTP ${result.status}`);
  }

  const downloadedInfo = await getInfoAsync(cacheFile);
  if (!downloadedInfo.exists || !downloadedInfo.size || downloadedInfo.size < 1000000) {
    throw new Error(`Downloaded model looks invalid: size=${downloadedInfo.size ?? 0}`);
  }

  console.log('[ModelLoader] Cached to:', cacheFile);
  return cacheFile;
}
