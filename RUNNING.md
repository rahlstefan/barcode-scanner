# Инструкции по запуску

## 🟢 Рекомендуемый путь

```
START
  │
  ├──→ ✅ npm install
  │
  ├──→ ✅ npm start        (Expo Dev)
  │     └─→ Press 'i'     (для iOS)
  │
  └──→ ✨ Готово!
      Видите приложение с движущимися боксами
```

---

## 📱 Полная сборка (если нужен Native код)

```
START
  │
  ├──→ ✅ npm install
  │
  ├──→ 📂 Подготовьте модели
  │     bash scripts/prepare-models.sh /path/to/weights/
  │
  ├──→ ✅ npm run prebuild
  │     Создаст ios/ и android/ папки
  │
  ├──→ ✅ npm run ios
  │     Откроет Xcode и установит на Device/Simulator
  │
  └──→ ✨ Готово!
```

---

## 🎬 Пошаговые команды

### Вариант A: Быстро (Demo в Expo Go)

```bash
cd BarcodeScanner
npm install
npm start
# Press 'i'
```

**Что видите:** 
- Камера включается
- Зелёные движущиеся боксы
- Плавное следование за движением

### Вариант B: С Native (на реальном устройстве)

```bash
cd BarcodeScanner

# 1. Подготовка
npm install
bash scripts/prepare-models.sh ../candidate3_balanced_adamw_musgd_phase1_v2/weights

# 2. Prebuild
npm run prebuild

# 3. Запуск
npm run ios
```

**Что видите:**
- Xcode открывается
- Проект компилируется
- Приложение запускается на Device/Simulator

---

## ⚙️ Системные требования

```
✅ Node.js 18+
✅ npm 10+
✅ Xcode 15+ (для iOS)
✅ iOS 14+
✅ Internet (для npm пакетов)
```

**Проверка:**
```bash
node --version    # v20.x или выше
npm --version     # 10.x или выше
```

---

## 📋 Troubleshooting

### ❌ "npm command not found"
```bash
# Установите Node.js с https://nodejs.org
# Выберите LTS версию
```

### ❌ "Cannot find module expo"
```bash
npm install
npm cache clean --force
rm -rf node_modules
npm install
```

### ❌ "Camera access denied"
iOS Settings → BarcodeScanner → Camera → Allow

### ❌ "Expo Go not installed"
App Store → Поищите "Expo Go" → Install

### ❌ "Cannot connect to expo server"
```bash
# Убедитесь что на одной сети (WiFi)
# Или используйте: npm start -- --tunnel
```

---

## 📊 Что произойдёт

### При `npm start`

```
┌──────────────────────────────┐
│ Expo Dev Server              │
│ Listening on:                │
│ exp://192.168.1.100:19000    │
│                              │
│ Options:                     │
│ › Press 'i' for iOS Simulator
│ › Press 'a' for Android      │
│ › Press 'w' for Web          │
└──────────────────────────────┘

# Введите 'i'

Запустится iOS Simulator
Загрузится приложение
Вы видите камеру с боксами
```

### При `npm run ios`

```
1. Компилирует Swift код
2. Связывает Native модули
3. Создаёт iOS app bundle
4. Запускает на Device/Simulator
5. Приложение видит реальную камеру
```

---

## 🎯 Чеклист

- [ ] Node.js установлен
- [ ] `cd BarcodeScanner`
- [ ] `npm install` завершилась без ошибок
- [ ] Разрешили камеру на телефоне
- [ ] `npm start` показывает Expo меню
- [ ] Нажал 'i' и видишь приложение

**Всё работает? ✨ Поздравляю!**

---

## 🔄 Обновление / Пересборка

```bash
# Если что-то сломалось:
npm run prebuild --clean
npm run ios

# Или просто рестарт:
Ctrl+C  (в npm start терминале)
npm start
```

---

## 📞 Получение помощи

1. **Документация:**
   - `QUICKSTART.md` - для первого запуска
   - `README.md` - для понимания архитектуры
   - `ARCHITECTURE.md` - как работает алгоритм

2. **Примеры:**
   - `App.tsx` - React Native код
   - `TemporalDetectionBuffer.ts` - алгоритм сглаживания
   - `config.ts` - параметры

3. **Файлы конфигурации:**
   - `app.json` - Expo конфигурация
   - `tsconfig.json` - TypeScript
   - `babel.config.js` - JS трансформация

---

**Готовы? Начнём! 🚀**

```bash
cd BarcodeScanner && npm install && npm start
```
