# 🚀 GitHub Actions - iOS Build

Настройка автоматической сборки iOS приложения через GitHub Actions.

---

## 🎯 Два варианта сборки

### 1️⃣ **EAS Build** (Рекомендуется) ⭐
- ☁️ Облачная сборка от Expo
- ✅ Не требует Xcode/macOS локально
- ✅ Автоматические сертификаты
- ✅ Проще настраивать
- ⏱️ Немного медленнее (облако)

### 2️⃣ **Xcode на macOS** (GitHub Actions)
- 💻 Локальная сборка на macOS runner
- ✅ Полный контроль над процессом
- ⚠️ Нужны сертификаты + provisioning profiles
- ⏱️ Быстрее на 2-3 минуты
- ⚠️ Сложнее настраивать

---

## 📋 Шаг 1: Подготовка репозитория

### Создайте GitHub репозиторий
```bash
cd m:\bboxfix\BarcodeScanner
git init
git add .
git commit -m "Initial commit: BarcodeScanner iOS app"
git remote add origin https://github.com/YOUR_USERNAME/barcode-scanner.git
git push -u origin main
```

---

## 🔐 Шаг 2: Настройка Secrets (для EAS Build)

### В GitHub репозитории:
1. Перейдите в **Settings → Secrets and variables → Actions**
2. Нажмите **New repository secret**
3. Добавьте `EXPO_TOKEN`:

```bash
# Получите токен:
# 1. Создайте аккаунт на https://expo.dev
# 2. Запустите: eas login
# 3. Получите токен из: eas credentials
# Или через: npx eas token create --scope admin
```

**Добавьте в Secrets:**
- `EXPO_TOKEN` - ваш Expo токен

---

## 🔐 Шаг 3: Настройка для Xcode (опционально)

Если используете локальную сборку через Xcode, нужны сертификаты:

```bash
# Генерируйте сертификаты
# Требуется Apple Developer Account ($99/год)

# Или используйте EAS (проще!)
```

---

## ✅ Шаг 4: Workflows готовы!

Файлы созданы в `.github/workflows/`:

1. **build-eas.yml** - Сборка через EAS (рекомендуется)
2. **build-xcode.yml** - Сборка через Xcode (альтернатива)
3. **test.yml** - Проверка кода перед сборкой

---

## 🚀 Использование

### Вариант A: Автоматическая сборка при push

```bash
git push origin main
# → Автоматически запускается workflow
# → Видите в GitHub: Actions tab
```

### Вариант B: Ручной запуск (workflow_dispatch)

**На GitHub:**
1. Перейдите в **Actions**
2. Выберите **Build iOS with EAS**
3. Нажмите **Run workflow**
4. Выберите опции (simulator/device)
5. Нажмите **Run workflow**

### Вариант C: При Pull Request

```bash
git checkout -b feature/my-feature
git commit -m "Add new feature"
git push origin feature/my-feature
# → Автоматически запускается test.yml
# → Видите результаты в PR
```

---

## 📊 Workflow: build-eas.yml

### Когда запускается:
- ✅ При `push` на `main` или `develop`
- ✅ При `pull_request` на `main`
- ✅ Вручную (workflow_dispatch)

### Что делает:
1. Проверяет код (`git checkout`)
2. Устанавливает Node.js
3. Устанавливает зависимости (`npm ci`)
4. Запускает EAS Build
5. Скачивает артифакты (логи)
6. Загружает в GitHub Artifacts

### Результат:
- 📱 **.ipa файл** в EAS dashboard (https://expo.dev/builds)
- 📊 **Логи** в GitHub Artifacts (7 дней)

---

## 🔧 Workflow: build-xcode.yml

### Когда запускается:
- ⚠️ Только вручную (workflow_dispatch)
- ⚠️ Требует macOS runner

### Что делает:
1. Проверяет код
2. Устанавливает Node.js и Ruby
3. Запускает `npm run prebuild`
4. Устанавливает CocoaPods
5. Компилирует через Xcode
6. Создаёт IPA архив
7. Загружает в GitHub Artifacts

### Результат:
- 📱 **.ipa файл** в GitHub Artifacts (30 дней)
- 📊 **Размер сборки** в логах

---

## 🧪 Workflow: test.yml

### Когда запускается:
- ✅ При каждом `push`
- ✅ При каждом `pull_request`

### Что проверяет:
- ✓ TypeScript типы (`tsc --noEmit`)
- ✓ Код формат (линтер)
- ✓ Зависимости

### Результат:
- ✅/❌ Статус проверки в PR

---

## 📱 Получение .ipa файла

### С EAS Build:
```
1. Workflow завершается
2. Перейдите на https://expo.dev/builds
3. Найдите ваш build
4. Нажмите Download → получите .ipa
```

### С Xcode (GitHub Actions):
```
1. Workflow завершается
2. GitHub: Actions → choose run
3. Artifacts → BarcodeScanner.ipa
4. Скачайте .ipa файл
```

---

## 🔄 Continuous Deployment (опционально)

### Добавить автоматическую загрузку на TestFlight:

```yaml
- name: 📤 Upload to TestFlight
  run: |
    xcrun altool --upload-app \
      --file build/ipa/*.ipa \
      --username ${{ secrets.APPLE_ID }} \
      --password ${{ secrets.APPLE_PASSWORD }} \
      --team-id ${{ secrets.TEAM_ID }}
```

Требует:
- `APPLE_ID` - Apple ID
- `APPLE_PASSWORD` - App-specific password
- `TEAM_ID` - Team ID

---

## 📋 Статус сборки

### Видите в GitHub:

```
✅ All checks passed
  ├── test.yml
  ├── build-eas.yml
  └── [Your other checks]
```

### Или красный ❌:
```
❌ Some checks failed
  ├── ❌ TypeScript compilation failed
  └── ✅ Build would pass if fixed
```

---

## 🐛 Troubleshooting

### ❌ "EXPO_TOKEN not found"
```
1. GitHub → Settings → Secrets → Actions
2. Добавьте EXPO_TOKEN
3. Re-run workflow
```

### ❌ "Pod install failed"
```
# Для Xcode workflow
# Увеличьте timeout в build-xcode.yml
```

### ❌ "Xcode not found"
```
# Используйте macos-latest
# Текущий: macos-12.6
# Обновите: macos-latest
```

### ❌ "Build timeout"
```
# EAS обычно быстро
# Если медленно - проверьте логи на https://expo.dev
```

---

## ⚡ Оптимизация

### Кэширование зависимостей:
```yaml
- uses: actions/cache@v3
  with:
    path: ~/.npm
    key: ${{ runner.os }}-npm-${{ hashFiles('package-lock.json') }}
    restore-keys: |
      ${{ runner.os }}-npm-
```

### Параллельные сборки:
```yaml
strategy:
  matrix:
    node-version: [18, 20]
```

### Уведомления (опционально):
```yaml
- name: 📧 Send Slack notification
  uses: slackapi/slack-github-action@v1
  with:
    webhook-url: ${{ secrets.SLACK_WEBHOOK }}
```

---

## 📚 Файлы конфигурации

| Файл | Назначение |
|------|-----------|
| `.github/workflows/build-eas.yml` | Сборка через EAS (облако) |
| `.github/workflows/build-xcode.yml` | Сборка через Xcode (macOS) |
| `.github/workflows/test.yml` | Проверка кода |
| `scripts/export-options.plist` | Параметры экспорта iOS |
| `eas.json` | Конфигурация EAS |

---

## 🎯 Рекомендуемый поток

### Разработка:
```
1. git checkout -b feature/xyz
2. Делайте изменения
3. git push → test.yml проверяет
4. Pull Request → тесты запускаются
5. Merge → build-eas.yml создаёт .ipa
```

### Релиз:
```
1. git tag v1.0.0
2. git push --tags
3. build-eas.yml запускается
4. .ipa готов на EAS Dashboard
5. Загружаете на TestFlight/App Store
```

---

## ✅ Готово!

Ваше приложение теперь строится автоматически! 🎉

```
✓ Код проверяется автоматически
✓ .ipa создаётся на сервере
✓ Артифакты сохраняются
✓ Уведомления отправляются
```

**Начните:**
```bash
git push origin main
# Смотрите GitHub Actions tab!
```

---

## 📞 Справка

| Что? | Где? |
|------|------|
| Статус сборки | GitHub → Actions tab |
| .ipa файл (EAS) | https://expo.dev/builds |
| .ipa файл (Xcode) | GitHub Actions → Artifacts |
| Логи | GitHub Actions → Logs |
| Secrets | GitHub → Settings → Secrets |

---

**Удачи с CI/CD! 🚀**
