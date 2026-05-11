#!/bin/bash

# Скрипт для подготовки модели TFLite

MODELS_DIR="assets/models"
MODEL_SOURCE="${1:-.}"
MODEL_NAME="best_quant.tflite"

echo "🔄 Подготовка моделей TFLite..."

# Создаем директорию если её нет
mkdir -p "$MODELS_DIR"

# Ищем модель в исходной папке
if [ -d "$MODEL_SOURCE" ]; then
    # Ищем .tflite файлы в папке и подпапках
    echo "📁 Ищу TFLite модели в: $MODEL_SOURCE"
    
    # Копируем best_full_integer_quant.tflite если найдена
    if [ -f "$MODEL_SOURCE/best_full_integer_quant.tflite" ]; then
        echo "✅ Найдена best_full_integer_quant.tflite"
        cp "$MODEL_SOURCE/best_full_integer_quant.tflite" "$MODELS_DIR/$MODEL_NAME"
        echo "📦 Скопирована в $MODELS_DIR/$MODEL_NAME"
    fi
    
    # Копируем best_int8.tflite если найдена
    if [ -f "$MODEL_SOURCE/best_int8.tflite" ]; then
        echo "✅ Найдена best_int8.tflite"
        cp "$MODEL_SOURCE/best_int8.tflite" "$MODELS_DIR/best_int8.tflite"
    fi
    
    # Копируем best_float32.tflite если найдена
    if [ -f "$MODEL_SOURCE/best_float32.tflite" ]; then
        echo "✅ Найдена best_float32.tflite"
        cp "$MODEL_SOURCE/best_float32.tflite" "$MODELS_DIR/best_float32.tflite"
    fi
else
    echo "⚠️  Папка не найдена: $MODEL_SOURCE"
    echo "Использование: $0 <path_to_models>"
    echo "Пример: $0 /path/to/candidate3_balanced_adamw_musgd_phase1_v2/weights"
fi

# Проверяем что модель готова
if [ -f "$MODELS_DIR/$MODEL_NAME" ]; then
    SIZE=$(ls -lh "$MODELS_DIR/$MODEL_NAME" | awk '{print $5}')
    echo "✅ Модель готова! Размер: $SIZE"
    echo "📍 Путь: $MODELS_DIR/$MODEL_NAME"
else
    echo "❌ Модель не найдена в $MODELS_DIR"
    exit 1
fi
