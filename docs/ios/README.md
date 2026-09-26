# Code Labs на iPhone с Windows-ПК

Короткий ответ: **переписывать приложение на Swift не нужно** (нужен ровно один небольшой Swift-файл,
см. 4.4), а собрать iOS-версию **без Mac можно** — на облачном macOS-раннере GitHub Actions.
Ниже — что именно делать.

---

## 1. Почему переписывать на Swift не нужно

Я разобрал ваш `CodeLabs-1.6.2.apk` и релизные файлы. Code Labs собран так:

| Платформа | Технология | Подтверждение |
|---|---|---|
| Windows | Electron + electron-builder | `CodeLabs-Setup-1.6.2.exe`, `latest.yml`, `.blockmap` — формат electron-updater |
| Android | **Capacitor** | `assets/capacitor.config.json`, `assets/native-bridge.js`, веб-часть в `assets/public/` |
| Веб-ядро | Vite-сборка (`index-*.js`, чанки `NotesPage`, `TasksPage`, `Calendar`, `NoteEditor`, `SettingsPage`, `TrashPage`, `CommandPalette`) | общее для обеих платформ |

`appId` — `studio.codelabs.mobile`.

**Capacitor — кроссплатформенный, iOS он поддерживает официально.** Android-версия уже работает, значит
iOS — это не переписывание, а добавление третьей цели сборки к тому же `dist/`.

Все четыре используемых плагина имеют официальную iOS-реализацию:

| Плагин из `capacitor.plugins.json` | iOS |
|---|---|
| `@capacitor/app` | да |
| `@capacitor/filesystem` | да |
| `@capacitor/local-notifications` | да |
| `@capacitor/share` | да |

Переписывание всех экранов на SwiftUI — это недели работы и вторая кодовая база, которую придётся
поддерживать параллельно. И оно **всё равно не снимает** ограничение из пункта 2. Смысла нет.

Swift понадобится ровно в одном месте: у вас есть собственный нативный плагин
`studio.codelabs.mobile.CodeLabsPlugin` (открытие ссылок и печать в PDF), и для iOS его нужно
реализовать заново — это ~100 строк, файл уже готов в [`CodeLabsPlugin.swift`](CodeLabsPlugin.swift).
Подробности в 4.4.

> Про десктопную версию для Мака — отдельно в [`../macos/README.md`](../macos/README.md).

## 2. Что обойти нельзя

Скомпилировать и подписать iOS-приложение можно **только на macOS** — Xcode и цепочка
подписи существуют лишь там. Официального способа сделать это на Windows нет.

Это ограничение на **сборку**, а не на вас: писать код, запускать сборки и устанавливать
приложение на iPhone вы будете с Windows. macOS живёт в облаке и запускается по кнопке.

## 3. Что понадобится

- **Apple Developer Program — 99 $/год.** Это обязательно, если хотите, чтобы приложение
  стояло на iPhone постоянно, а не перестало запускаться через 7 дней. Оформляется на
  [developer.apple.com](https://developer.apple.com/programs/) полностью из браузера.
- **Аккаунт GitHub.** Публичный репозиторий — macOS-минуты бесплатны. Приватный на Free-плане:
  2000 минут/мес, но macOS тарифицируется ×10, то есть ~200 macOS-минут — при сборке
  5–10 мин это 20–40 сборок в месяц. Хватает с запасом.
- **Ваш iPhone.** Регистрировать UDID не нужно: раздача через TestFlight этого не требует.

## 4. Шаг 1 — правки в коде (делаются на Windows)

Всё ниже **проверено по вашему бандлу** `CodeLabs-1.6.2.apk`, а не предположения.
Хорошая новость: три пункта из моего первого чеклиста у вас уже сделаны.

### Уже готово — трогать не надо

| Что | Статус в 1.6.2 |
|---|---|
| `viewport-fit=cover` | есть в `index.html` |
| Безопасные зоны в CSS | есть, `env(safe-area-inset-top)` и `env(safe-area-inset-bottom)` (7 использований) |
| Запрос разрешений на уведомления | есть, `requestPermissions` / `checkPermissions` вызываются |
| Android-only пути файловой системы | не используются — `Directory.External*` в коде нет, только `Cache` |
| Платформенный хук для CSS | есть: `document.documentElement.dataset.native = getPlatform()`, в CSS 8 правил на `[data-native]` — на iOS станет `data-native="ios"` |

### 4.1. Секция `ios` в `capacitor.config.json`

Сейчас есть только `android`. Добавьте рядом:

```json
"ios": {
  "backgroundColor": "#0D0C0B",
  "contentInset": "never",
  "scrollEnabled": false,
  "limitsNavigationsToAppBoundDomains": true
}
```

`#0D0C0B` — это цвет из вашего `index.html` (`theme-color` и `body{background}`), он же
уберёт вспышку другого оттенка при старте. `scrollEnabled: false` убирает «резиновое»
протягивание всей страницы. `smallIcon`/`iconColor` у `LocalNotifications` iOS игнорирует —
удалять не нужно.

### 4.2. Обязательно: обновления через APK сломаются на iOS

Это **подтверждённая проблема**, а не риск. В `index-*.js` логика такая:

```js
bs = Capacitor.isNativePlatform()        // на iOS это тоже true
xs = bs ? registerPlugin('CodeLabs') : null
Gc = !!V || bs                            // «обновления поддерживаются»
```

Проверка версии (`Vc()`) дёргает
`https://api.github.com/repos/dcvke/code-labs-releases/releases/latest`,
ищет ассет по `/\.apk$/i` и, если версия новее, показывает кнопку
«Скачать версию X». Нажатие вызывает `openExternal({url})` с ссылкой на **APK**.

Поскольку гейт — `isNativePlatform()`, а не проверка Android, на iPhone произойдёт ровно это:
приложение предложит скачать Android-APK. Бесполезно для пользователя и прямо нарушает
правило App Store 2.5.2 (загрузка исполняемого кода) — сборку могут отклонить.

Замените гейт на явную проверку платформы:

```ts
import { Capacitor } from '@capacitor/core';

const isAndroidNative = Capacitor.getPlatform() === 'android';
// было:  const bs = Capacitor.isNativePlatform();
// стало: используйте isAndroidNative во всех трёх местах —
//        в Vc()/Uc() (проверка), в Wc() (скачивание) и в Gc (флаг поддержки).
```

Кастомный плагин `xs` при этом должен остаться на **обеих** нативных платформах — он
нужен для печати (см. 4.4), так что его регистрацию гейтить по Android нельзя.

### 4.3. Гейтнуть `createChannel` по Android

В коде есть вызов `LocalNotifications.createChannel` — это Android-only API.
На iOS он отклоняется с «not implemented». Оберните:

```ts
if (Capacitor.getPlatform() === 'android') {
  await LocalNotifications.createChannel({ /* ... */ });
}
```

### 4.4. Главное: кастомный плагин надо реализовать на Swift

Вот единственное место, где Swift действительно нужен. В Android-проекте у вас есть свой
плагин `studio.codelabs.mobile.CodeLabsPlugin` (он не в `capacitor.plugins.json`, потому что
объявлен локально и регистрируется в `MainActivity`). У него ровно два метода:

| Метод | Вызов из JS | Android-реализация | iOS-эквивалент |
|---|---|---|---|
| `openExternal` | `{ url }` | `Intent(ACTION_VIEW)` | `UIApplication.shared.open(url)` |
| `printHtml` | `{ html, name }` | `WebView.createPrintDocumentAdapter()` + `PrintManager` | `UIMarkupTextPrintFormatter` + `UIPrintInteractionController` |

`printHtml` — это экспорт в PDF: на десктопе используется `V.invoicePdf`, на мобильном —
`xs.printHtml`, в браузере — печать через скрытый `iframe`. На iOS системный диалог печати
умеет «Сохранить в Файлы» как PDF, так что поведение сохраняется.

Готовая реализация лежит рядом: [`CodeLabsPlugin.swift`](CodeLabsPlugin.swift).
Положите её в `ios/App/App/CodeLabsPlugin.swift` после шага 4 (bootstrap).
Регистрировать вручную не надо — Capacitor 6+ находит плагин по `CAPBridgedPlugin` сам.
Если у вас Capacitor 5 или ниже, дополнительно нужен `.m`-файл с макросом `CAP_PLUGIN`.

Без этого файла приложение соберётся, но печать и открытие ссылок на iPhone будут падать
с «CodeLabs plugin is not implemented on ios».

### 4.5. Иконки и splash

```
npx @capacitor/assets generate --ios
```

Берёт `assets/icon.png` (1024×1024) и `assets/splash.png`, раскладывает по iOS-ресурсам.
Работает на Windows.

## 5. Шаг 2 — настройка на стороне Apple (всё в браузере)

1. **Team ID** — [developer.apple.com](https://developer.apple.com) → Membership details.
   10 символов, вида `A1B2C3D4E5`.
2. **Ключ App Store Connect API** — [App Store Connect](https://appstoreconnect.apple.com) →
   Users and Access → Integrations → App Store Connect API → «+».
   Роль: **App Manager** (или Admin). Скачайте файл `AuthKey_XXXXXXXXXX.p8` —
   **он даётся один раз, второй раз скачать нельзя.** Запишите **Key ID** и **Issuer ID**.
3. **Запись приложения** — App Store Connect → Apps → «+» → New App.
   Платформа iOS, Bundle ID `studio.codelabs.mobile`, SKU любой.
   Если Bundle ID в списке нет — сначала Identifiers → «+» на developer.apple.com.

Сертификат подписи и provisioning profile **вручную делать не надо**: в workflow стоит
`-allowProvisioningUpdates`, Xcode на раннере выпустит их сам по API-ключу.

## 6. Шаг 3 — секреты в GitHub

Репозиторий исходников → Settings → Secrets and variables → Actions → New repository secret:

| Имя секрета | Значение |
|---|---|
| `APPLE_TEAM_ID` | Team ID, 10 символов |
| `ASC_KEY_ID` | Key ID ключа API |
| `ASC_ISSUER_ID` | Issuer ID |
| `ASC_KEY_P8` | **всё** содержимое `.p8`-файла, включая строки `-----BEGIN PRIVATE KEY-----` и `-----END PRIVATE KEY-----` |

## 7. Шаг 4 — разовый bootstrap

Скопируйте [`workflows/ios-bootstrap.yml`](workflows/ios-bootstrap.yml) в репозиторий исходников
как `.github/workflows/ios-bootstrap.yml`, закоммитьте и запустите:
Actions → «iOS bootstrap (создать папку ios/)» → Run workflow.

Он на macOS-раннере поставит `@capacitor/ios` нужной версии, выполнит `npx cap add ios`,
допишет ключи в `Info.plist` и **закоммитит папку `ios/` обратно в репозиторий**.

Именно поэтому шаг делается в CI: `cap add ios` тянет CocoaPods, которого на Windows нет.
Нужен один раз.

После того как workflow закоммитит `ios/`, сделайте `git pull` и добавьте туда Swift-плагин:

```
copy docs\ios\CodeLabsPlugin.swift ios\App\App\CodeLabsPlugin.swift
git add ios/App/App/CodeLabsPlugin.swift
git commit -m "feat(ios): нативный плагин CodeLabs для iOS"
git push
```

Файл нужно один раз добавить в target «App» — в `ios/App/App.xcodeproj`. Если работаете только
с Windows, проще всего сделать это следующим шагом: `npx cap sync ios` в CI подхватит файл,
лежащий в папке группы `App`, при первой же сборке.

## 8. Шаг 5 — сборка и отправка в TestFlight

Скопируйте [`workflows/ios-testflight.yml`](workflows/ios-testflight.yml) как
`.github/workflows/ios-testflight.yml`. Запуск: Actions → «iOS -> TestFlight» → Run workflow
(поле версии можно оставить пустым — возьмёт из `package.json`).

Что делает: `npm ci` → `npm run build` → `npx cap sync ios` → `xcodebuild archive` →
`-exportArchive` в `.ipa` → `altool --upload-app` в TestFlight. Готовый `.ipa` дополнительно
кладётся в артефакты сборки, чтобы его можно было скачать.

Номер сборки берётся из `github.run_number` — он растёт сам, а TestFlight требует уникальный
номер для каждой загрузки.

## 9. Шаг 6 — установка на iPhone

1. Дождитесь письма «App Store Connect: сборка обработана» (5–30 минут после загрузки).
2. App Store Connect → ваше приложение → TestFlight → **Internal Testing** → создайте группу
   и добавьте себя (свой Apple ID) как тестировщика.
3. На iPhone установите из App Store приложение **TestFlight**, войдите тем же Apple ID.
4. Code Labs появится в TestFlight → **Install**.

Ключевой момент: **internal-тестирование не проходит проверку Apple**. Это не публикация в
App Store — ревью нет, модерации нет, ждать никого не нужно. До 100 внутренних тестировщиков.
Сборка живёт 90 дней, новая загрузка продлевает. Обновления прилетают на iPhone сами.

Провода и Mac для установки не нужны вообще.

## 10. Альтернативы, если 99 $/год платить не хотите

| Вариант | Цена | Насколько годится |
|---|---|---|
| **TestFlight (пункты выше)** | 99 $/год | **Рекомендую.** Windows-only, приложение стоит постоянно, обновления автоматом |
| Бесплатный Apple ID + Xcode | 0 ₽ | Подпись живёт **7 дней**, потом приложение не запускается. И всё равно нужен Mac для пересборки каждую неделю |
| Аренда облачного Mac (MacinCloud, Scaleway Mac mini) | ~20–30 $/мес или почасово | Работает, но дороже TestFlight и вы сидите в Xcode по RDP. Разумно для отладки на реальном устройстве |
| Sideloadly / AltStore на Windows | 0 ₽ | Устанавливает готовый `.ipa`, но **сам `.ipa` всё равно надо где-то собрать на macOS**. Плюс те же 7 дней на бесплатном Apple ID |
| Hackintosh / macOS в VMware | 0 ₽ | Нарушает лицензию Apple, ломается на обновлениях, подпись часто отваливается. Не советую |

Без Apple Developer Program любой путь сводится к перепривязке раз в 7 дней. Для приложения,
которым вы пользуетесь каждый день, это мучение — 99 $/год решают вопрос целиком.

## 11. Если всё-таки нужен именно нативный Swift

Тогда это полноценная переработка: SwiftUI-экраны вместо `NotesPage`, `TasksPage`, `Calendar`,
`NoteEditor`, `SettingsPage`, `TrashPage`, `CommandPalette`, своя модель данных и своя
синхронизация — и вторая кодовая база навсегда. Ограничение «собирать только на macOS»
при этом никуда не девается, то есть пункты 5–9 всё равно нужны.

Разумный компромисс, если упирается в производительность отдельного экрана: оставить Capacitor
и вынести узкое место в нативный Swift-плагин Capacitor. Тогда Swift появляется ровно там, где
он что-то даёт.

## 12. Частые грабли

- **`altool` ругается на дубликат номера сборки** — перезапустите workflow, `run_number` увеличится.
- **«No profiles for studio.codelabs.mobile»** — Bundle ID не зарегистрирован в Identifiers
  или у API-ключа роль ниже App Manager.
- **Белый экран на iPhone, на Android всё хорошо** — почти всегда CSP. В вашем `index.html`
  стоит `default-src 'self'`, а Capacitor на iOS отдаёт страницу с `capacitor://localhost`.
  Если экран пустой, смотрите консоль через Safari на Mac либо временно ослабьте CSP для проверки.
- **`CodeLabs plugin is not implemented on ios`** — не добавлен `CodeLabsPlugin.swift` (пункт 4.4)
  либо файл не входит в target «App».
- **На iPhone предлагает скачать `.apk`** — не заменён гейт `isNativePlatform()` на проверку
  Android (пункт 4.2). Это же — причина возможного отказа при ревью.
- **`createChannel` падает с «not implemented»** — не гейтнут по Android (пункт 4.3).
