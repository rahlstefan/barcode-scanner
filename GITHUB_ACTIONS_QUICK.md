# 🔧 GitHub Actions - Быстрая настройка

## ⚡ За 5 минут - от кода к .ipa!

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

### Шаг 2: Добавьте Expo Token

1. Создайте аккаунт на https://expo.dev (если нет)
2. Получите токен:
```bash
# Установите eas-cli
npm install -g eas-cli

# Логинитесь
eas login

# Получите токен
eas credentials
```

3. В GitHub репозитории:
   - Перейдите: **Settings → Secrets and variables → Actions**
   - Нажмите: **New repository secret**
   - Имя: `EXPO_TOKEN`
   - Значение: `ваш_токен_из_eas`
   - Save

### Шаг 3: Запустите сборку

**Вариант A - Автоматически:**
```bash
git push origin main
# Автоматически запускается workflow!
```

**Вариант B - Вручную:**
1. Перейдите в ваш репозиторий на GitHub
2. Нажмите: **Actions**
3. Выберите: **Build iOS with EAS**
4. Нажмите: **Run workflow** → **Run workflow**

### Шаг 4: Получите .ipa

1. Ждите завершения (обычно 5-10 минут)
2. Перейдите: https://expo.dev/builds
3. Найдите свой build
4. Нажмите: **Download** → **.ipa файл**

---

## 📊 Что происходит?

```
push на GitHub
      ↓
GitHub Actions запускает workflow
      ↓
Устанавливает зависимости
      ↓
Запускает EAS Build (облако Expo)
      ↓
Компилирует iOS приложение
      ↓
Создаёт .ipa файл
      ↓
✅ Готово! Скачивайте .ipa
```

---

## 📁 Структура GitHub Actions

```
.github/
└── workflows/
    ├── build-eas.yml      ← ☁️ Облачная сборка (рекомендуется)
    ├── build-xcode.yml    ← 💻 Локальная сборка (альтернатива)
    └── test.yml           ← ✅ Проверка кода
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
# 8. build-eas.yml создаёт .ipa автоматически!
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
https://expo.dev/builds → найдите build → Download
```

---

## ⚙️ Вариант 2: Локальная сборка (опционально)

Если хотите собирать на собственном macOS вместо облака:

1. Используйте workflow `build-xcode.yml`
2. Установите на macOS:
   ```bash
   xcode-select --install
   brew install ruby
   ```
3. Нужны сертификаты (Apple Developer Account)
4. Запустите вручную через GitHub Actions

---

## 🔐 Что такое EXPO_TOKEN?

- Это ключ для доступа к облаку Expo
- Нужен для автоматической сборки
- Хранится в GitHub Secrets (безопасно)
- Не выкладывайте в интернет!

Получить:
```bash
# Способ 1: Через CLI
eas login
eas credentials

# Способ 2: Через веб
# https://expo.dev/settings/tokens
```

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
   - GitHub → Actions → build-eas
   - Статус "In progress" или "Complete"

4. ✅ .ipa готов?
   - https://expo.dev/builds
   - Найдите последний build
   - Статус "Finished"

---

## 💡 Советы

✨ **Первый раз медленнее** - обычно 10-15 минут  
✨ **Следующие - быстрее** - 5-8 минут (кэш)  
✨ **Используйте EAS** - проще чем локальная сборка  
✨ **Сохраняйте .ipa** - для распределения  

---

## 🎉 Готово!

Ваше приложение теперь строится автоматически в облаке! 🚀

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
