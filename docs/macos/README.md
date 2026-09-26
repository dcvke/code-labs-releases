# Code Labs на macOS

Да, получится — и это заметно проще, чем iOS. Electron кроссплатформенный, ваш код уже
почти готов. Но **три вещи на macOS сломаются молча**, и я их нашёл в вашей сборке 1.6.2.

Ниже всё проверено по `CodeLabs-Setup-1.6.2.exe`: я распаковал NSIS-установщик,
достал `app.asar` и прочитал `dist-electron/main.cjs`.

---

## 1. Два разных вопроса

Если вопрос был «**запустится ли сборка на Маке**» — да, и тогда всё проще: ставите Xcode
из App Store, `npm ci && npx cap add ios && npx cap sync ios`, открываете
`ios/App/App.xcworkspace`, подключаете iPhone кабелем и жмёте Run. GitHub Actions и
руководство [`../ios/README.md`](../ios/README.md) нужны ровно для того, чтобы обойтись
**без** Мака. Есть Мак — они не нужны.

Если вопрос был «**сделать версию Code Labs для Мака**» — тоже да, дальше про это.

## 2. Что уже готово

| Что | Статус |
|---|---|
| Electron сам по себе | кроссплатформенный, отдельная кодовая база не нужна |
| `electron-updater` | macOS поддерживает: в бандле есть `MacUpdater`, он выбирается по `process.platform === "darwin"` |
| Кэш-пути | библиотека сама считает `~/Library/Caches` на macOS |
| Веб-часть | та же, что на Windows и Android |

Важно: обе `darwin`-ветки, которые я нашёл в `main.cjs`, — **внутри библиотеки
electron-updater**, а не в вашем коде. Своей обработки macOS в приложении пока нет.

## 3. Три подтверждённые поломки

### 3.1. `Menu.setApplicationMenu(null)` убивает горячие клавиши

В `main.cjs` при старте:

```js
app.whenReady().then(async () => {
  Menu.setApplicationMenu(null);   // <-- вот это
  ...
})
```

На Windows это просто убирает меню окна — нормально. На macOS меню приложения **глобальное**,
и `null` выносит его целиком вместе со стандартными сочетаниями: перестанут работать
**⌘Q, ⌘W, ⌘C, ⌘V, ⌘X, ⌘A, ⌘Z**. Приложение будет выглядеть сломанным, и закрыть его
можно будет только через Force Quit.

Лечится так — на macOS отдаём минимальное нативное меню:

```js
if (process.platform === 'darwin') {
  Menu.setApplicationMenu(Menu.buildFromTemplate([
    { role: 'appMenu' },
    { role: 'editMenu' },     // сюда входят Cut/Copy/Paste/Select All/Undo
    { role: 'windowMenu' },
  ]));
} else {
  Menu.setApplicationMenu(null);
}
```

### 3.2. `titleBarStyle: 'hidden'` даст двойные кнопки окна

Окно создаётся с `titleBarStyle: "hidden"` и `autoHideMenuBar: true`, а кнопки закрыть/
свернуть/развернуть приложение рисует само (в preload есть `windowControl`).

На macOS `titleBarStyle: 'hidden'` убирает заголовок, но **оставляет нативные «светофорные»
кружки** слева сверху. Получится два набора кнопок управления окном друг на друге.

Варианты:

```js
// вариант А: нативные кружки, свои кнопки скрыть на macOS
titleBarStyle: process.platform === 'darwin' ? 'hiddenInset' : 'hidden',
trafficLightPosition: { x: 14, y: 14 },   // подогнать под вашу панель
```

и в веб-части не рисовать свои кнопки, когда `platform === 'darwin'`.

`autoHideMenuBar` на macOS игнорируется — оставлять можно.

### 3.3. Deep links на macOS не сработают

Сейчас реализована **Windows/Linux-схема**:

| API в `main.cjs` | Найдено |
|---|---|
| `setAsDefaultProtocolClient` | да |
| `requestSingleInstanceLock` | да |
| `second-instance` | да |
| `open-url` | **нет** |
| `will-finish-launching` | **нет** |

На Windows ссылка приходит в `argv` второго экземпляра — это у вас обработано. macOS
доставляет её **только** через событие `open-url`, которого нет. То есть `onDeepLink` и
`takeInitialDeepLink` на Маке будут молчать.

Добавить:

```js
app.on('will-finish-launching', () => {
  app.on('open-url', (event, url) => {
    event.preventDefault();
    handleDeepLink(url);        // та же функция, что для argv
  });
});
```

Плюс в конфиге electron-builder нужен `mac.protocols`, иначе система не свяжет схему
с приложением.

## 4. Мелочи, которые стоит поправить

- **Нет обработчика `window-all-closed`.** По умолчанию Electron завершает приложение при
  закрытии последнего окна на всех платформах. На macOS принято оставаться в Dock:
  ```js
  app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit(); });
  app.on('activate', () => { if (BrowserWindow.getAllWindows().length === 0) createWindow(); });
  ```
- **Иконка.** Нужен `build/icon.icns` (у вас сейчас `build/icon.png`). electron-builder
  умеет сделать `.icns` из PNG 1024×1024 автоматически, но только **на macOS** — то есть
  в CI это соберётся само.
- **Архитектуры.** Собирайте под обе: `--mac --x64 --arm64` или universal-бинарник.
  Только x64 на Apple Silicon пойдёт через Rosetta и будет тяжелее.

## 5. Конфиг electron-builder

В `app.asar` секции `build` нет — electron-builder её вырезает, так что вашего конфига
я не вижу. В исходниках (в `package.json` или `electron-builder.yml`) нужно добавить блок
`mac`:

```json
"mac": {
  "category": "public.app-category.productivity",
  "target": [
    { "target": "dmg", "arch": ["x64", "arm64"] },
    { "target": "zip", "arch": ["x64", "arm64"] }
  ],
  "icon": "build/icon.png",
  "hardenedRuntime": true,
  "gatekeeperAssess": false,
  "entitlements": "build/entitlements.mac.plist",
  "entitlementsInherit": "build/entitlements.mac.plist",
  "protocols": [
    { "name": "Code Labs", "schemes": ["codelabs"] }
  ]
}
```

Цель **`zip` обязательна** — без неё `electron-updater` на macOS не умеет обновляться,
`.dmg` ему не подходит.

Схему в `protocols` подставьте свою — ту же, что уходит в `setAsDefaultProtocolClient`.

Файл `build/entitlements.mac.plist` для обычного Electron-приложения:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.cs.allow-jit</key><true/>
  <key>com.apple.security.cs.allow-unsigned-executable-memory</key><true/>
  <key>com.apple.security.cs.disable-library-validation</key><true/>
</dict>
</plist>
```

## 6. Сборка

Workflow готов: [`workflows/macos-build.yml`](workflows/macos-build.yml) →
в репозиторий исходников как `.github/workflows/macos-build.yml`.
Запуск: Actions → «macOS build (Electron)» → Run workflow.

Два режима:

| `sign` | Что получится |
|---|---|
| `false` | `.dmg` без подписи. Запускается только через правый клик → «Открыть» (Gatekeeper). Автообновление не работает. Годится проверить, что сборка вообще проходит |
| `true` | Подписанный и нотаризованный `.dmg` + `.zip`. Запускается двойным кликом, автообновление работает |

## 7. Про подпись — тут снова нужны 99 $/год

Для `sign = true` нужен сертификат **Developer ID Application**, а он выдаётся только
участникам Apple Developer Program. Тот же аккаунт, что и для iOS, — второй раз платить
не надо.

Без подписи macOS-версия технически работает, но при первом запуске Gatekeeper скажет
«Программу не удалось проверить», и автообновление через `electron-updater` не заработает:
`MacUpdater` требует валидную подпись.

Сертификат можно получить **не имея Мака**: CSR генерируется OpenSSL на Windows, затем
загружается на developer.apple.com, скачивается `.cer`, и снова через OpenSSL собирается
`.p12` для секрета `MAC_CSC_LINK` (в base64). Ключ нотаризации — тот же
App Store Connect API key, что вы сделали для iOS.

## 8. Бонус: iOS-сборка сама запустится на Apple Silicon

Отдельный приятный факт. Приложения для iPhone/iPad запускаются на Маках с чипами
M-серии как есть. Если в App Store Connect у iOS-версии оставить галку доступности на Mac,
то iOS-сборка Code Labs будет ставиться через TestFlight и на Apple Silicon Мак — без
отдельной Electron-версии.

Это **не замена** нормальной десктопной версии: окно будет вести себя как iPad-приложение,
без своего меню и нормальной работы с окнами. Но как быстрый способ получить Code Labs
на Маке — работает и стоит ноль дополнительных усилий.
