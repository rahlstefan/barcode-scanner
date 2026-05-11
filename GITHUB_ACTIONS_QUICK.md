# 🔧 GitHub Actions - Быстрая настройка

## ⚡ За 5 минут - от кода к .ipa через GitHub Actions!

### Шаг 1: Создайте GitHub репозиторий
```bash
cd m:\bboxfix\BarcodeScanner

# Инициализируйте git
git init
git add .
git commit -m "Initial commit"

# Добавьте remote (замените USERNAME)
git remote add origin https://github.com/USERNAME/barcode-scanner.git
git branch -M main
git push -u origin main
```

### Шаг 2: Запустите сборку

**Вариант A - Автоматически:**
```bash
git push origin main
# Автоматически запускается workflow!
```

**Вариант B - Вручную:**
1. Перейдите в ваш репозиторий на GitHub
2. Нажмите: **Actions**
3. Выберите: **Build Unsigned iOS .ipa (for Sideloadly)**
4. Нажмите: **Run workflow** → **Run workflow**

### Шаг 3: Получите .ipa

1. Ждите завершения (обычно 10-20 минут)
2. Откройте run в **Actions**
3. Скачайте artifact **BarcodeScanner-unsigned-ipa**
4. Передайте `BarcodeScanner-unsigned.ipa` в Sideloadly

---

## 📊 Что происходит?

```
push на GitHub
      ↓
GitHub Actions запускает workflow
      ↓
Устанавливает зависимости
      ↓
Запускает `expo prebuild`
      ↓
Делает `pod install`
      ↓
Собирает unsigned iOS archive
      ↓
Упаковывает `.ipa` для Sideloadly
      ↓
✅ Готово! Скачивайте .ipa
```

---

## 📁 Структура GitHub Actions

```
.github/
└── workflows/
      ├── build-unsigned-ipa.yml  ← ☁️ unsigned .ipa для Sideloadly
      ├── build-eas.yml           ← legacy / manual only
      └── test.yml                ← ✅ Проверка кода
```

---

## 🎯 Рекомендуемый workflow

### Разработка:
```bash
# 1. Создайте ветку
git checkout -b feature/new-feature

# 2. Делайте изменения
# ... edit files ...

# 3. Коммитьте
git add .
git commit -m "Add feature"

# 4. Push
git push origin feature/new-feature

# 5. На GitHub: Create Pull Request
# 6. Автоматически запускается test.yml
# 7. Если всё ОК → Merge to main
- 8. build-unsigned-ipa.yml создаёт unsigned .ipa автоматически!
```

---

## 🚀 Быстрые команды

### Пересчитать сборку:
```bash
git commit --allow-empty -m "Rebuild"
git push origin main
```

### Проверить статус:
```
GitHub → Actions → выберите workflow → смотрите статус
```

### Скачать .ipa:
```
GitHub → Actions → откройте run → Artifacts → BarcodeScanner-unsigned-ipa
```

---

## ⚙️ Вариант 2: Локальная сборка (опционально)

Если хотите собирать на собственном macOS вместо GitHub Actions:

1. Используйте `xcodebuild` и `pod install` вручную
2. Установите на macOS:
   ```bash
   xcode-select --install
   brew install ruby
   ```
3. Для подписанной сборки нужны сертификаты (Apple Developer Account)
4. Для unsigned архива подпись отключайте вручную аналогично workflow

---

## 📋 Проверка

### После первого push:

1. ✅ GitHub Actions запустился?
   - GitHub → Actions tab
   - Должны видеть workflow runs

2. ✅ Тесты прошли?
   - GitHub → Actions → test.yml
   - Зелёная ✅ галочка

3. ✅ Сборка началась?
      - GitHub → Actions → build-unsigned-ipa
   - Статус "In progress" или "Complete"

4. ✅ .ipa готов?
      - GitHub → Actions → откройте run
      - Скачайте artifact `BarcodeScanner-unsigned-ipa`

---

## 💡 Советы

✨ **Первый раз медленнее** - обычно 10-15 минут  
✨ **Следующие - быстрее** - 5-8 минут (кэш)  
✨ **Используйте GitHub Actions** - без ручной подписи  
✨ **Сохраняйте .ipa** - для распределения  

---

## 🎉 Готово!

Ваше приложение теперь строится автоматически в GitHub Actions! 🚀

```
✅ Код → Push
✅ GitHub Actions → Automatic Build  
✅ .ipa → Ready for Download
```

**Начните:**
```bash
git push origin main
```

И смотрите GitHub Actions tab! 👀

---

**Дальше:** Читайте [GITHUB_ACTIONS.md](GITHUB_ACTIONS.md) для полной документации.
